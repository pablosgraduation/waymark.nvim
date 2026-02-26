-- ============================================================================
-- waymark.state — Shared mutable state for all waymark modules.
-- ============================================================================
-- Centralises every piece of runtime state so modules can communicate without
-- circular dependencies. Every other module reads/writes this table.

local uv = vim.uv or vim.loop

local M = {}

-- ---------------------------------------------------------------------------
-- Architecture & design rationale
-- ---------------------------------------------------------------------------
-- This module is the single source of truth for all mutable state that
-- other waymark modules share. Understanding a few non-obvious design
-- choices here saves a lot of head-scratching in the rest of the codebase.
--
-- Dual-clock-domain design:
--   Automarks use monotonic millisecond timestamps (vim.uv.now()) because
--   they are session-only and need an ordering that is immune to wall-clock
--   adjustments (NTP skew, daylight saving, user `date -s`, etc.).
--   Bookmarks use epoch seconds (os.time()) because they persist across
--   sessions and need timestamps that are meaningful after restart.
--   The allmark merged timeline bridges the two domains using session
--   anchors (session_start_mono / session_start_epoch) to convert automark
--   monotonic timestamps into epoch space for unified sorting.
--
-- Navigation index sentinel (-1 = "staging"):
--   Both automarks_idx and bookmarks_idx use -1 to mean "not currently
--   navigating any list." This is distinct from index 0 or nil — it means
--   the user hasn't started traversing yet, so the next Prev/Next press
--   should enter the list from the appropriate end rather than continuing
--   from a stale position. Adding a new mark resets the index to -1 so
--   the next navigation always starts fresh.
--
-- Generation-counted navigation:
--   nav_generation is incremented on every begin_navigation() call. The
--   fallback timeout in begin_navigation_with_fallback() captures the
--   current generation and only clears `navigating` if the generation
--   hasn't changed. This prevents a stale timer from clearing the flag
--   after a *new* navigation has started — a race condition that would
--   cause automark creation to fire mid-jump-sequence.
--
-- Mark ID counter:
--   mark_id_counter is a monotonically increasing integer shared by both
--   automarks and bookmarks. It provides a stable identity for marks in
--   the merged timeline (allmark uses IDs to track "last visited mark"
--   across timeline rebuilds). On bookmark load, sync_mark_id_counter()
--   advances the counter past all persisted IDs to prevent collisions.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Extmark namespaces
-- ---------------------------------------------------------------------------
M.ns_automark = vim.api.nvim_create_namespace("waymark_auto")
M.ns_bookmark = vim.api.nvim_create_namespace("waymark_bookmark")
M.ns_flash = vim.api.nvim_create_namespace("waymark_flash")
M.ns_popup = vim.api.nvim_create_namespace("waymark_popup")
M.ns_onkey = vim.api.nvim_create_namespace("waymark_onkey")

-- ---------------------------------------------------------------------------
-- Hot-reload cleanup
-- ---------------------------------------------------------------------------
-- Global state table survives re-require during plugin development.
_G._waymark_state = _G._waymark_state or {}

--- Safely stop and close a libuv timer, suppressing errors.
---@param timer userdata  libuv timer handle
function M.close_timer(timer)
    pcall(function()
        timer:stop()
        timer:close()
    end)
end

if _G._waymark_state.debounce_timer then
    M.close_timer(_G._waymark_state.debounce_timer)
end
if _G._waymark_state.save_timer then
    M.close_timer(_G._waymark_state.save_timer)
end
if _G._waymark_state.onkey_ns then
    pcall(vim.on_key, nil, _G._waymark_state.onkey_ns)
end

_G._waymark_state.onkey_ns = M.ns_onkey

-- ---------------------------------------------------------------------------
-- Mark lists
-- ---------------------------------------------------------------------------
-- automarks: ordered oldest-first (index 1 = oldest).
-- bookmarks: ordered newest-first (index 1 = newest).
M.automarks = {}
M.automarks_idx = -1 -- -1 = staging (not currently navigating)
M.bookmarks = {}
M.bookmarks_idx = -1 -- -1 = staging

-- Monotonically increasing ID assigned to every mark (automarks + bookmarks).
M.mark_id_counter = 0

--- Generate the next unique mark ID.
---@return integer
function M.next_mark_id()
    M.mark_id_counter = M.mark_id_counter + 1
    return M.mark_id_counter
end

--- Ensure mark_id_counter is above all currently assigned IDs.
function M.sync_mark_id_counter()
    for _, b in ipairs(M.bookmarks) do
        if b.id and b.id >= M.mark_id_counter then
            M.mark_id_counter = b.id
        end
    end
    for _, a in ipairs(M.automarks) do
        if a.id and a.id >= M.mark_id_counter then
            M.mark_id_counter = a.id
        end
    end
end

-- ---------------------------------------------------------------------------
-- Tracking state
-- ---------------------------------------------------------------------------
M.last_position = { fname = "", row = 0, time = 0 }
M.last_key_time = 0 -- uv.now() timestamp of the most recent keypress
M.nav_generation = 0 -- incremented each begin_navigation()
M.navigating = false -- true while a jump is in progress
M.setup_done = false -- true after first successful setup()
M.setup_warned = false -- ensures the "setup() not called" warning fires once

-- ---------------------------------------------------------------------------
-- Timers
-- ---------------------------------------------------------------------------
M.debounce_timer = uv.new_timer()
_G._waymark_state.debounce_timer = M.debounce_timer

-- ---------------------------------------------------------------------------
-- Clock anchors for the allmark timeline
-- ---------------------------------------------------------------------------
M.session_start_mono = uv.now()
M.session_start_epoch = os.time()

-- ---------------------------------------------------------------------------
-- Merged (allmark) navigation state
-- ---------------------------------------------------------------------------
M.merged_last_mark = nil -- mark ID (integer) or nil for staging

-- ---------------------------------------------------------------------------
-- Bookmarks popup state
-- ---------------------------------------------------------------------------
M.popup_buf = nil
M.popup_win = nil
M.popup_selected = {}
M.popup_preview_cache = {}

-- ---------------------------------------------------------------------------
-- Bookmarks persistence
-- ---------------------------------------------------------------------------
M.bookmarks_file = vim.fn.stdpath("data") .. "/waymark-bookmarks.json"
M.bookmarks_save_timer = uv.new_timer()
_G._waymark_state.save_timer = M.bookmarks_save_timer
M.bookmarks_dirty = false
M.bookmarks_save_generation = 0
M.bookmarks_save_seq = 0

-- ---------------------------------------------------------------------------
-- Buffer-ignore cache
-- ---------------------------------------------------------------------------
M.ignore_cache = {}

-- ---------------------------------------------------------------------------
-- Active keymaps (for cleanup on re-setup)
-- ---------------------------------------------------------------------------
M.active_keymaps = {}

-- ---------------------------------------------------------------------------
-- Navigation helpers
-- ---------------------------------------------------------------------------

--- Enter navigation mode (suppresses automark creation).
function M.begin_navigation()
    M.nav_generation = M.nav_generation + 1
    M.navigating = true
end

--- Leave navigation mode (re-enables automark creation).
function M.end_navigation()
    M.navigating = false
end

--- Enter navigation mode with a 2-second safety timeout. If end_navigation()
--- is never called (e.g. due to an error during the jump), the timeout clears
--- the flag so automarks are not permanently disabled. The generation check
--- ensures that if the user triggers two rapid jumps, the first jump's timeout
--- won't clear `navigating` while the second jump is still in progress —
--- which would cause an unwanted automark at the landing position.
function M.begin_navigation_with_fallback()
    M.begin_navigation()
    local my_gen = M.nav_generation
    vim.defer_fn(function()
        if M.nav_generation == my_gen then
            M.navigating = false
        end
    end, 2000)
end

-- ---------------------------------------------------------------------------
-- List / index helpers
-- ---------------------------------------------------------------------------

--- Clear all elements from a list while preserving table identity.
---@param t table  Array-style table to clear
function M.clear_list(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

--- Adjust a navigation index after removing an element from a list.
---@param idx integer      Current navigation index (-1 = staging)
---@param removed integer  Index of the element that was removed
---@param list_len integer Length of the list AFTER the removal
---@return integer         Updated navigation index
function M.adjust_index_after_removal(idx, removed, list_len)
    if idx == removed then
        idx = -1
    elseif idx > removed then
        idx = idx - 1
    end
    if idx > list_len then
        return -1
    end
    return idx
end

--- Warn once if a user command is invoked before setup().
function M.warn_if_no_setup()
    if not M.setup_done and not M.setup_warned then
        M.setup_warned = true
        vim.notify(
            "waymark: setup() has not been called. Using defaults, but keymaps and "
                .. "bookmark loading are inactive. Call require('waymark').setup() to initialize.",
            vim.log.levels.WARN
        )
    end
end

return M
