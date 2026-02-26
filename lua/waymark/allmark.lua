-- ============================================================================
-- waymark.allmark — Merged timeline navigation (automarks + bookmarks).
-- ============================================================================

local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local filter = require("waymark.filter")
local extmarks = require("waymark.extmarks")

local M = {}

---@class WaymarkMergedMark
---@field id integer
---@field fname string
---@field row integer
---@field col integer
---@field sort_time number           Epoch seconds (unified timeline axis)
---@field kind "automark"|"bookmark"
---@field window_id integer?         Only present for automarks
---@field tab_id integer?            Only present for automarks

--- Convert a monotonic timestamp to epoch seconds for merged sorting.
--- Automarks live in monotonic-ms space (session-local), but the merged
--- timeline needs a single comparable axis. This converts automark timestamps
--- into epoch-seconds space using the session anchors so they can be sorted
--- alongside bookmark timestamps (which are already epoch seconds).
---@param mono_ms number  Monotonic timestamp in milliseconds
---@return number         Epoch seconds
local function mono_to_epoch(mono_ms)
    if not mono_ms or mono_ms == 0 then
        return 0
    end
    if mono_ms < state.session_start_mono then
        return 0
    end
    return state.session_start_epoch + (mono_ms - state.session_start_mono) / 1000
end

--- Build a merged list of all marks sorted by timestamp (oldest first).
--- Bookmarks are processed first so their positions can be recorded; automarks
--- at the same file:line as a bookmark are then suppressed to avoid showing
--- duplicate entries in the timeline (the bookmark "wins" since it's persistent).
---@return WaymarkMergedMark[]
local function build_merged_timeline()
    local merged = {}

    local bookmark_positions = {}
    for _, b in ipairs(state.bookmarks) do
        extmarks.sync_from_extmark(b, state.ns_bookmark)
        bookmark_positions[util.mark_key(b.fname, b.row)] = true

        table.insert(merged, {
            id = b.id,
            fname = b.fname,
            row = b.row,
            col = b.col,
            sort_time = b.timestamp or 0,
            kind = "bookmark",
        })
    end

    for _, a in ipairs(state.automarks) do
        extmarks.sync_from_extmark(a, state.ns_automark)
        if not bookmark_positions[util.mark_key(a.fname, a.row)] then
            table.insert(merged, {
                id = a.id,
                fname = a.fname,
                row = a.row,
                col = a.col,
                sort_time = mono_to_epoch(a.timestamp or 0),
                kind = "automark",
                window_id = a.window_id,
                tab_id = a.tab_id,
            })
        end
    end

    table.sort(merged, function(a, b)
        if a.sort_time == b.sort_time then
            return a.id < b.id
        end
        return a.sort_time < b.sort_time
    end)

    return merged
end

--- Locate the last-visited mark in a merged list by ID.
---@param merged WaymarkMergedMark[]
---@return integer|nil
local function find_merged_index(merged)
    if not state.merged_last_mark then
        return nil
    end
    return util.find_mark_index_by_id(merged, state.merged_last_mark)
end

--- Jump to a mark from the merged timeline.
---@param mark WaymarkMergedMark
---@param idx integer   1-based position in the merged list
---@param total integer Total number of marks in the merged list
local function goto_merged_mark(mark, idx, total)
    state.begin_navigation_with_fallback()

    state.merged_last_mark = mark.id

    if util.jump_to_position(mark.fname, mark.row, mark.col, mark.tab_id, mark.window_id) then
        local icon = mark.kind == "bookmark" and config.current.bookmark_sign or config.current.automark_sign
        local actual_row = vim.api.nvim_win_get_cursor(0)[1]
        local preview = util.get_line_preview(mark.fname, actual_row, 40)
        local msg =
            string.format("%s [%d/%d] %s:%d", icon, idx, total, vim.fn.fnamemodify(mark.fname, ":t"), actual_row)
        if preview then
            msg = msg .. "  │ " .. preview
        end
        util.echo_ephemeral(msg)
        state.end_navigation()
        return
    end

    if vim.fn.filereadable(mark.fname) == 0 then
        vim.notify(
            "File no longer exists - removing mark: " .. vim.fn.fnamemodify(mark.fname, ":t"),
            vim.log.levels.WARN
        )
        if mark.kind == "automark" then
            local i = util.find_mark_index_by_id(state.automarks, mark.id)
            if i then
                extmarks.remove(state.automarks[i], state.ns_automark)
                table.remove(state.automarks, i)
                state.automarks_idx = state.adjust_index_after_removal(state.automarks_idx, i, #state.automarks)
            end
        elseif mark.kind == "bookmark" then
            local i = util.find_mark_index_by_id(state.bookmarks, mark.id)
            if i then
                extmarks.remove(state.bookmarks[i], state.ns_bookmark)
                table.remove(state.bookmarks, i)
                state.bookmarks_idx = state.adjust_index_after_removal(state.bookmarks_idx, i, #state.bookmarks)
                require("waymark.bookmark").save()
            end
        end
    else
        vim.notify("Could not jump to mark", vim.log.levels.WARN)
    end
    state.merged_last_mark = nil
    state.end_navigation()
end

--- Navigate to the previous mark in the merged timeline.
---@param count integer|nil
function M.prev(count)
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    local merged = build_merged_timeline()

    if #merged == 0 then
        util.echo_ephemeral("No marks saved")
        return
    end

    local current = find_merged_index(merged)
    local target = current

    local n = count or 1
    for _ = 1, n do
        if not target then
            target = #merged
        elseif target <= 1 then
            target = #merged
        else
            target = target - 1
        end
    end

    goto_merged_mark(merged[target], target, #merged)
end

--- Navigate to the next mark in the merged timeline.
---@param count integer|nil
function M.next(count)
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    local merged = build_merged_timeline()

    if #merged == 0 then
        util.echo_ephemeral("No marks saved")
        return
    end

    local current = find_merged_index(merged)
    local target = current

    local n = count or 1
    for _ = 1, n do
        if not target then
            target = 1
        elseif target >= #merged then
            target = 1
        else
            target = target + 1
        end
    end

    goto_merged_mark(merged[target], target, #merged)
end

return M
