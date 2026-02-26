-- ============================================================================
-- waymark.automark — Automark creation, navigation, and tracking.
-- ============================================================================

local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local filter = require("waymark.filter")
local extmarks = require("waymark.extmarks")

local uv = vim.uv or vim.loop

local M = {}

-- ---------------------------------------------------------------------------
-- Heuristics
-- ---------------------------------------------------------------------------

--- Determine whether the current position warrants a new automark.
---@param r integer       Current cursor row
---@param fname string    Current file (absolute path)
---@param force boolean   If true, skip heuristics
---@return boolean
function M.should_track_position(r, fname, force)
    if force then
        if fname == state.last_position.fname and r == state.last_position.row then
            return false
        end
        return true
    end

    local c = config.current
    local current_time = uv.now()
    local time_since_last = current_time - state.last_position.time
    local line_diff = math.abs(r - state.last_position.row)

    if fname ~= state.last_position.fname then
        return true
    end
    if line_diff >= c.automark_min_lines then
        return true
    end
    if time_since_last >= c.automark_min_interval_ms and line_diff > 0 then
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Core: add_automark
-- ---------------------------------------------------------------------------

--- Create a new automark at the given position.
---@param r integer       Row (1-indexed)
---@param c_col integer   Column (1-indexed)
---@param fname string    Absolute file path
---@param force boolean   If true, bypass distance/time heuristics
function M.add(r, c_col, fname, force)
    if not fname or fname == "" then
        return
    end
    if state.navigating then
        return
    end

    local c = config.current

    if not M.should_track_position(r, fname, force) then
        if force then
            local now = uv.now()
            local found_automark = false
            for i = #state.automarks, 1, -1 do
                if state.automarks[i].fname == fname and state.automarks[i].row == r then
                    state.automarks[i].timestamp = now
                    found_automark = true
                    break
                end
            end
            if not found_automark then
                for _, b in ipairs(state.bookmarks) do
                    if b.fname == fname and b.row == r then
                        b.timestamp = state.session_start_epoch + (now - state.session_start_mono) / 1000
                        require("waymark.bookmark").save()
                        break
                    end
                end
            end
            state.automarks_idx = -1
            state.merged_last_mark = nil
        end
        return
    end

    local current_time = uv.now()
    local window_id = vim.api.nvim_get_current_win()
    local tab_id = vim.api.nvim_get_current_tabpage()

    -- ---- Bookmark-line avoidance ----
    -- This check must happen BEFORE the cleanup pass below. If cleanup ran
    -- first, it might remove a nearby automark, and then we'd bail out here
    -- without creating a replacement — leaving a gap. Worse, if we didn't
    -- bail, the new automark would land on the bookmark's line, creating a
    -- duplicate. Checking bookmarks first and returning early prevents both.
    for _, b in ipairs(state.bookmarks) do
        if b.fname == fname then
            extmarks.sync_from_extmark(b, state.ns_bookmark)
            if b.row == r then
                state.last_position = { fname = fname, row = r, time = current_time }
                if force then
                    b.timestamp = state.session_start_epoch + (current_time - state.session_start_mono) / 1000
                    state.automarks_idx = -1
                    state.merged_last_mark = nil
                    require("waymark.bookmark").save()
                end
                return
            end
        end
    end

    -- ---- Cleanup pass ----
    -- Two-tier strategy in a single reverse-iteration pass:
    --   (a) Marks within 2 lines are *always* removed — they're effectively
    --       duplicates from micro-movements.
    --   (b) Marks within automark_cleanup_lines (default 10) are only removed
    --       if they're in the *same window and tab* and are older than
    --       automark_recent_ms. The window/tab constraint prevents cross-split
    --       cleanup from eating marks the user placed in a different context.
    for i = #state.automarks, 1, -1 do
        local pos = state.automarks[i]
        extmarks.sync_from_extmark(pos, state.ns_automark)

        if pos.fname == fname then
            local dist = math.abs(pos.row - r)

            if dist <= 2 then
                extmarks.remove(pos, state.ns_automark)
                table.remove(state.automarks, i)
                state.automarks_idx = state.adjust_index_after_removal(state.automarks_idx, i, #state.automarks)
            elseif dist <= c.automark_cleanup_lines and pos.window_id == window_id and pos.tab_id == tab_id then
                local should_preserve = c.automark_recent_ms > 0
                    and (current_time - (pos.timestamp or 0)) < c.automark_recent_ms

                if not should_preserve then
                    extmarks.remove(pos, state.ns_automark)
                    table.remove(state.automarks, i)
                    state.automarks_idx = state.adjust_index_after_removal(state.automarks_idx, i, #state.automarks)
                end
            end
        end
    end

    -- Create new automark
    ---@type WaymarkAutomark
    local mark = {
        id = state.next_mark_id(),
        fname = fname,
        row = r,
        col = c_col,
        timestamp = current_time,
        window_id = window_id,
        tab_id = tab_id,
        extmark_id = nil,
        bufnr = nil,
    }

    table.insert(state.automarks, mark)
    state.automarks_idx = -1
    state.merged_last_mark = nil

    extmarks.place(mark, state.ns_automark, c.automark_sign, "WaymarkAutomarkSign", "WaymarkAutomarkNum")

    -- ---- Eviction ----
    -- NOTE: table.remove(_, 1) is O(n) due to array shifting. At the default
    -- automark_limit of 15 this is negligible (~nanoseconds to shift 15
    -- pointers), but would warrant a circular buffer if the limit were raised
    -- significantly (e.g. 500+).
    if #state.automarks > c.automark_limit then
        local old = state.automarks[1]
        extmarks.remove(old, state.ns_automark)
        table.remove(state.automarks, 1)
        state.automarks_idx = state.adjust_index_after_removal(state.automarks_idx, 1, #state.automarks)
    end

    state.last_position = { fname = fname, row = r, time = current_time }
end

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

--- Jump to the automark at automarks_idx.
local function goto_automark()
    if #state.automarks == 0 then
        util.echo_ephemeral("No automarks saved")
        return
    end
    if state.automarks_idx < 1 or state.automarks_idx > #state.automarks then
        state.automarks_idx = #state.automarks
    end

    state.begin_navigation_with_fallback()

    local attempts = 0
    while attempts < #state.automarks do
        if state.automarks_idx < 1 or state.automarks_idx > #state.automarks then
            state.automarks_idx = #state.automarks
        end

        extmarks.sync_from_extmark(state.automarks[state.automarks_idx], state.ns_automark)

        local pos = state.automarks[state.automarks_idx]
        local fname, row, col = pos.fname, pos.row, pos.col

        if util.jump_to_position(fname, row, col, pos.tab_id, pos.window_id) then
            local actual_row = vim.api.nvim_win_get_cursor(0)[1]
            local preview = util.get_line_preview(fname, actual_row, 40)
            local msg = string.format(
                "Automark %d/%d: %s:%d",
                state.automarks_idx,
                #state.automarks,
                vim.fn.fnamemodify(fname, ":t"),
                actual_row
            )
            if preview then
                msg = msg .. "  │ " .. preview
            end
            util.echo_ephemeral(msg)
            state.end_navigation()
            return
        end

        if vim.fn.filereadable(fname) == 0 then
            vim.notify(
                "File no longer exists - removing automark: " .. vim.fn.fnamemodify(fname, ":t"),
                vim.log.levels.WARN
            )
            extmarks.remove(pos, state.ns_automark)
            table.remove(state.automarks, state.automarks_idx)

            if #state.automarks == 0 then
                util.echo_ephemeral("No valid automarks remaining")
                state.automarks_idx = -1
                state.end_navigation()
                return
            end

            if state.automarks_idx > #state.automarks then
                state.automarks_idx = #state.automarks
            end
            attempts = attempts + 1
        else
            vim.notify("Could not jump to automark", vim.log.levels.WARN)
            state.end_navigation()
            return
        end
    end

    util.echo_ephemeral("No valid automarks remaining")
    state.automarks_idx = -1
    state.end_navigation()
end

--- Navigate to the previous (older) automark.
---@param count integer|nil  Number of steps (default 1)
function M.prev(count)
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    if #state.automarks == 0 then
        util.echo_ephemeral("No automarks saved")
        return
    end

    local n = count or 1
    for _ = 1, n do
        if #state.automarks == 1 then
            state.automarks_idx = 1
        elseif state.automarks_idx == -1 then
            state.automarks_idx = #state.automarks
        elseif state.automarks_idx <= 1 then
            state.automarks_idx = #state.automarks
        else
            state.automarks_idx = state.automarks_idx - 1
        end
    end

    goto_automark()
end

--- Navigate to the next (newer) automark.
---@param count integer|nil  Number of steps (default 1)
function M.next(count)
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    if #state.automarks == 0 then
        util.echo_ephemeral("No automarks saved")
        return
    end

    local n = count or 1
    for _ = 1, n do
        if #state.automarks == 1 then
            state.automarks_idx = 1
        elseif state.automarks_idx == -1 then
            state.automarks_idx = 1
        elseif state.automarks_idx >= #state.automarks then
            state.automarks_idx = 1
        else
            state.automarks_idx = state.automarks_idx + 1
        end
    end

    goto_automark()
end

--- Display all automarks in a notification.
function M.show()
    state.warn_if_no_setup()
    if #state.automarks == 0 then
        util.echo_ephemeral("No automarks saved")
        return
    end

    local lines = { "Automarks:" }
    for i, pos in ipairs(state.automarks) do
        extmarks.sync_from_extmark(pos, state.ns_automark)
        local marker = (i == state.automarks_idx) and "→ " or "  "
        local fname = vim.fn.fnamemodify(pos.fname, ":t")
        local preview = util.get_line_preview(pos.fname, pos.row, 40)
        local line = string.format("%s%d. %s:%d", marker, i, fname, pos.row)
        if preview then
            line = line .. "  │ " .. preview
        end
        table.insert(lines, line)
    end
    vim.notify(table.concat(lines, "\n"))
end

--- Remove automarks whose files have been deleted from disk.
function M.purge()
    state.warn_if_no_setup()
    local cleaned = 0

    for i = #state.automarks, 1, -1 do
        local pos = state.automarks[i]
        if vim.fn.filereadable(pos.fname) == 0 then
            extmarks.remove(pos, state.ns_automark)
            table.remove(state.automarks, i)
            cleaned = cleaned + 1
            state.automarks_idx = state.adjust_index_after_removal(state.automarks_idx, i, #state.automarks)
        end
    end

    if cleaned > 0 then
        util.echo_ephemeral(string.format("Cleaned up %d automarks from deleted files", cleaned))
    else
        util.echo_ephemeral("All automarks are valid")
    end
end

--- Remove all automarks.
function M.clear()
    state.warn_if_no_setup()
    for _, mark in ipairs(state.automarks) do
        extmarks.remove(mark, state.ns_automark)
    end
    state.clear_list(state.automarks)
    state.automarks_idx = -1
    state.merged_last_mark = nil
    util.echo_ephemeral("All automarks cleared")
end

--- Return a deep copy of the automarks list.
---@return WaymarkAutomark[]
function M.get()
    return vim.deepcopy(state.automarks)
end

-- ---------------------------------------------------------------------------
-- Automatic tracking (idle, InsertLeave, BufLeave, LSP)
-- ---------------------------------------------------------------------------

--- Register all automatic tracking autocmds and the on_key handler.
function M.setup()
    -- Deregister any previous on_key handler (safe for re-setup() calls)
    pcall(vim.on_key, nil, state.ns_onkey)

    -- ---- Idle-based tracking ----
    -- vim.on_key fires on every keypress. We restart the debounce timer each
    -- time; when it finally fires (idle threshold reached), we place an automark.
    --
    -- The entire body is wrapped in pcall because Neovim silently unregisters
    -- on_key callbacks that throw errors — the callback simply stops firing
    -- with no notification. pcall keeps the callback alive through transient
    -- errors, and the scheduled vim.notify ensures the user is informed rather
    -- than silently losing idle tracking.
    vim.on_key(function()
        local ok, err = pcall(function()
            if vim.api.nvim_get_mode().mode ~= "n" then
                return
            end
            if state.navigating then
                return
            end
            if filter.should_ignore_buffer() then
                return
            end

            state.last_key_time = uv.now()

            state.debounce_timer:stop()
            state.debounce_timer:start(
                config.current.automark_idle_ms,
                0,
                vim.schedule_wrap(function()
                    if vim.api.nvim_get_mode().mode ~= "n" then
                        return
                    end
                    if filter.should_ignore_buffer(vim.api.nvim_get_current_buf()) then
                        return
                    end
                    if uv.now() - state.last_key_time >= config.current.automark_idle_ms then
                        local pos_data = util.get_cursor_position()
                        if pos_data then
                            M.add(pos_data.row, pos_data.col, pos_data.fname, false)
                        end
                    end
                end)
            )
        end)
        if not ok then
            vim.schedule(function()
                vim.notify("waymark on_key error: " .. tostring(err), vim.log.levels.WARN)
            end)
        end
    end, state.ns_onkey)

    -- Insert leave tracking
    vim.api.nvim_create_autocmd("InsertLeave", {
        desc = "Save automark when leaving insert mode",
        group = vim.api.nvim_create_augroup("waymark_insert_leave", { clear = true }),
        callback = function()
            local pos_data = util.get_cursor_position()
            if pos_data then
                M.add(pos_data.row, pos_data.col, pos_data.fname, false)
            end
        end,
    })

    -- Buffer leave tracking
    vim.api.nvim_create_autocmd("BufLeave", {
        desc = "Save automark when leaving buffer",
        group = vim.api.nvim_create_augroup("waymark_buf_leave", { clear = true }),
        callback = function()
            if state.navigating then
                return
            end
            if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
                return
            end
            local pos_data = util.get_cursor_position()
            if pos_data then
                M.add(pos_data.row, pos_data.col, pos_data.fname, true)
            end
        end,
    })

    -- LSP jump detection
    local lsp_jump_methods = {
        ["textDocument/definition"] = true,
        ["textDocument/declaration"] = true,
        ["textDocument/typeDefinition"] = true,
        ["textDocument/implementation"] = true,
    }

    vim.api.nvim_create_autocmd("LspRequest", {
        desc = "Save automark before LSP navigation jumps",
        group = vim.api.nvim_create_augroup("waymark_lsp_jump", { clear = true }),
        callback = function(args)
            if
                args.data
                and args.data.request
                and args.data.request.type == "pending"
                and lsp_jump_methods[args.data.request.method]
            then
                local pos_data = util.get_cursor_position()
                if pos_data then
                    M.add(pos_data.row, pos_data.col, pos_data.fname, true)
                end
            end
        end,
    })
end

return M
