-- ============================================================================
-- waymark.bookmark — Bookmark persistence, CRUD, navigation, and toggle.
-- ============================================================================

local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local filter = require("waymark.filter")
local extmarks = require("waymark.extmarks")

local uv = vim.uv or vim.loop
local json_encode = vim.json and vim.json.encode or vim.fn.json_encode
local json_decode = vim.json and vim.json.decode or vim.fn.json_decode

local M = {}

-- ============================================================================
-- Persistence
-- ============================================================================

--- Build the JSON-serializable representation of bookmarks.
---@return WaymarkBookmarkFile
local function serialize_bookmarks()
    local to_save = {}
    for _, b in ipairs(state.bookmarks) do
        table.insert(to_save, {
            id = b.id,
            fname = b.fname,
            row = b.row,
            col = b.col,
            timestamp = b.timestamp,
        })
    end
    return {
        bookmarks = to_save,
        saved_at = os.time(),
    }
end

--- Save bookmarks to disk.
--- Both branches use an atomic write pattern: write to a temp file → fsync
--- to ensure data hits disk → rename over the target. This ensures readers
--- never see a partially-written file. The async branch additionally uses a
--- generation counter to abandon in-flight writes superseded by newer saves.
---@param sync boolean|nil  If true, perform a blocking write (for VimLeavePre).
function M.save(sync)
    if sync then
        state.bookmarks_save_timer:stop()
        state.bookmarks_dirty = false
        state.bookmarks_save_generation = state.bookmarks_save_generation + 1

        local ok, encoded = pcall(json_encode, serialize_bookmarks())
        if not ok then
            return
        end

        util.ensure_parent_dir(state.bookmarks_file)

        local tmp_path = state.bookmarks_file .. ".tmp.sync"
        local fd = uv.fs_open(tmp_path, "w", 420)
        if not fd then
            return
        end
        local write_ok = uv.fs_write(fd, encoded, 0)
        if write_ok then
            uv.fs_fsync(fd)
        end
        uv.fs_close(fd)
        if write_ok then
            uv.fs_rename(tmp_path, state.bookmarks_file)
        else
            uv.fs_unlink(tmp_path)
        end
    else
        state.bookmarks_dirty = true
        state.bookmarks_save_timer:stop()
        state.bookmarks_save_timer:start(
            300,
            0,
            vim.schedule_wrap(function()
                if not state.bookmarks_dirty then
                    return
                end
                state.bookmarks_dirty = false

                local ok, encoded = pcall(json_encode, serialize_bookmarks())
                if not ok then
                    return
                end

                util.ensure_parent_dir(state.bookmarks_file)

                local gen = state.bookmarks_save_generation
                state.bookmarks_save_seq = state.bookmarks_save_seq + 1
                local tmp_file = state.bookmarks_file .. ".tmp." .. state.bookmarks_save_seq

                uv.fs_open(tmp_file, "w", 420, function(err_open, fd)
                    if err_open or not fd then
                        vim.schedule(function()
                            vim.notify("Failed to save bookmarks (open): " .. tostring(err_open), vim.log.levels.WARN)
                        end)
                        return
                    end
                    if state.bookmarks_save_generation ~= gen then
                        uv.fs_close(fd, function()
                            uv.fs_unlink(tmp_file, function() end)
                        end)
                        return
                    end
                    uv.fs_write(fd, encoded, 0, function(err_write)
                        if err_write then
                            uv.fs_close(fd, function()
                                uv.fs_unlink(tmp_file, function() end)
                            end)
                            vim.schedule(function()
                                vim.notify("Failed to save bookmarks: " .. tostring(err_write), vim.log.levels.WARN)
                            end)
                            return
                        end
                        uv.fs_fsync(fd, function()
                            uv.fs_close(fd, function()
                                if state.bookmarks_save_generation ~= gen then
                                    uv.fs_unlink(tmp_file, function() end)
                                    return
                                end
                                uv.fs_rename(tmp_file, state.bookmarks_file, function(err_rename)
                                    if err_rename then
                                        vim.schedule(function()
                                            vim.notify(
                                                "Failed to save bookmarks: " .. tostring(err_rename),
                                                vim.log.levels.WARN
                                            )
                                        end)
                                        uv.fs_unlink(tmp_file, function() end)
                                    end
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        )
    end
end

--- Load bookmarks from the JSON file on disk.
function M.load()
    state.clear_list(state.bookmarks)

    -- Clean up orphaned temp files
    local data_dir = vim.fn.fnamemodify(state.bookmarks_file, ":h")
    local base_name = vim.fn.fnamemodify(state.bookmarks_file, ":t")
    local tmp_glob = vim.fn.glob(data_dir .. "/" .. base_name .. ".tmp.*", false, true)
    if #tmp_glob > 0 then
        local now = os.time()
        for _, f in ipairs(tmp_glob) do
            local mtime = vim.fn.getftime(f)
            if mtime ~= -1 and (now - mtime) > 10 then
                pcall(os.remove, f)
            end
        end
    end

    if vim.fn.filereadable(state.bookmarks_file) ~= 1 then
        return
    end

    local content = vim.fn.readfile(state.bookmarks_file)
    if #content == 0 then
        return
    end

    local ok, data = pcall(json_decode, table.concat(content, "\n"))
    if not ok then
        vim.notify(
            "waymark: bookmarks file is corrupted, starting fresh. File: " .. state.bookmarks_file,
            vim.log.levels.WARN
        )
        return
    end
    if not data or not data.bookmarks then
        return
    end

    local raw = data.bookmarks
    if type(raw) ~= "table" then
        return
    end

    for _, b in ipairs(raw) do
        local mark
        if b.fname then
            ---@type WaymarkBookmark
            mark = {
                id = b.id or state.next_mark_id(),
                fname = util.normalize_path(b.fname),
                row = b.row,
                col = b.col or 1,
                timestamp = b.timestamp or 0,
                extmark_id = nil,
                bufnr = nil,
            }
        elseif b[1] then
            ---@type WaymarkBookmark
            mark = {
                id = state.next_mark_id(),
                fname = util.normalize_path(b[1]),
                row = b[2] or 1,
                col = b[3] or 1,
                timestamp = b[4] or 0,
                extmark_id = nil,
                bufnr = nil,
            }
        end

        if mark and mark.fname and mark.fname ~= "" then
            table.insert(state.bookmarks, mark)
        end
    end
end

--- Remove bookmarks whose files have been deleted from disk.
--- The isdirectory(parent) guard distinguishes "file was deliberately deleted"
--- from "the entire drive/mount/project is temporarily unavailable." Without
--- it, unmounting an external drive would silently delete all bookmarks
--- pointing to files on that drive.
function M.cleanup()
    local cleaned = 0

    for i = #state.bookmarks, 1, -1 do
        local fname = state.bookmarks[i].fname
        if vim.fn.filereadable(fname) == 0 then
            local parent = vim.fn.fnamemodify(fname, ":h")
            if vim.fn.isdirectory(parent) == 1 then
                table.remove(state.bookmarks, i)
                cleaned = cleaned + 1
                state.bookmarks_idx = state.adjust_index_after_removal(state.bookmarks_idx, i, #state.bookmarks)
            end
        end
    end

    if cleaned > 0 then
        vim.notify(string.format("Cleaned up %d bookmarks from deleted files", cleaned))
        M.save()
    end
end

-- ============================================================================
-- Bookmark core
-- ============================================================================

--- Add a bookmark at the current cursor position.
function M.add()
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    local pos_data = util.get_cursor_position()
    if not pos_data then
        vim.notify("Cannot create bookmark in this buffer", vim.log.levels.WARN)
        return
    end

    for _, b in ipairs(state.bookmarks) do
        extmarks.sync_from_extmark(b, state.ns_bookmark)
        if b.fname == pos_data.fname and b.row == pos_data.row then
            util.echo_ephemeral("Bookmark already exists at this location")
            return
        end
    end

    ---@type WaymarkBookmark
    local mark = {
        id = state.next_mark_id(),
        fname = pos_data.fname,
        row = pos_data.row,
        col = pos_data.col,
        timestamp = state.session_start_epoch + (uv.now() - state.session_start_mono) / 1000,
        extmark_id = nil,
        bufnr = nil,
    }

    -- Remove any automark on the same line
    for i = #state.automarks, 1, -1 do
        local a = state.automarks[i]
        extmarks.sync_from_extmark(a, state.ns_automark)
        if a.fname == pos_data.fname and a.row == pos_data.row then
            extmarks.remove(a, state.ns_automark)
            table.remove(state.automarks, i)
            state.automarks_idx = state.adjust_index_after_removal(state.automarks_idx, i, #state.automarks)
        end
    end

    table.insert(state.bookmarks, 1, mark)
    state.bookmarks_idx = -1
    state.merged_last_mark = nil

    extmarks.place(mark, state.ns_bookmark, config.current.bookmark_sign, "WaymarkBookmarkSign", "WaymarkBookmarkNum")

    M.save()
    util.echo_ephemeral(
        string.format("Bookmark added (%d): %s:%d", #state.bookmarks, util.format_path(pos_data.fname), pos_data.row)
    )
end

--- Delete the bookmark at the current cursor position.
function M.delete_at_cursor()
    local pos_data = util.get_cursor_position()
    if not pos_data then
        return
    end

    for i, b in ipairs(state.bookmarks) do
        extmarks.sync_from_extmark(b, state.ns_bookmark)
        if b.fname == pos_data.fname and b.row == pos_data.row then
            extmarks.remove(b, state.ns_bookmark)
            table.remove(state.bookmarks, i)
            state.bookmarks_idx = state.adjust_index_after_removal(state.bookmarks_idx, i, #state.bookmarks)
            M.save()
            state.merged_last_mark = nil
            util.echo_ephemeral("Bookmark removed: " .. util.format_path(pos_data.fname) .. ":" .. pos_data.row)
            return
        end
    end

    util.echo_ephemeral("No bookmark found at current location")
end

--- Jump directly to a bookmark by its list index (1-based).
---@param index integer  1-based bookmark index
function M.jump_to_index(index)
    if index < 1 or index > #state.bookmarks then
        vim.notify("Invalid bookmark index: " .. index, vim.log.levels.WARN)
        return
    end

    state.begin_navigation_with_fallback()

    extmarks.sync_from_extmark(state.bookmarks[index], state.ns_bookmark)

    local b = state.bookmarks[index]

    if util.jump_to_position(b.fname, b.row, b.col) then
        state.bookmarks_idx = index

        local actual_row = vim.api.nvim_win_get_cursor(0)[1]
        local preview = util.get_line_preview(b.fname, actual_row, 40)
        local msg = string.format("Bookmark %d: %s:%d", index, util.format_path(b.fname), actual_row)
        if preview then
            msg = msg .. "  │ " .. preview
        end
        util.echo_ephemeral(msg)
        state.end_navigation()
        return
    end

    if vim.fn.filereadable(b.fname) == 0 then
        vim.notify("File no longer exists - removing bookmark: " .. util.format_path(b.fname), vim.log.levels.WARN)
        extmarks.remove(b, state.ns_bookmark)
        table.remove(state.bookmarks, index)
        state.bookmarks_idx = state.adjust_index_after_removal(state.bookmarks_idx, index, #state.bookmarks)
        M.save()
    else
        vim.notify("Could not jump to bookmark", vim.log.levels.WARN)
    end

    state.end_navigation()
end

-- ============================================================================
-- Navigation
-- ============================================================================

--- Navigate to the previous (older) bookmark.
---@param count integer|nil
function M.prev(count)
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    if #state.bookmarks == 0 then
        util.echo_ephemeral("No bookmarks saved")
        return
    end

    local n = count or 1
    for _ = 1, n do
        if #state.bookmarks == 1 then
            state.bookmarks_idx = 1
        elseif state.bookmarks_idx == -1 then
            state.bookmarks_idx = 1
        elseif state.bookmarks_idx >= #state.bookmarks then
            state.bookmarks_idx = 1
        else
            state.bookmarks_idx = state.bookmarks_idx + 1
        end
    end

    M.jump_to_index(state.bookmarks_idx)
end

--- Navigate to the next (newer) bookmark.
---@param count integer|nil
function M.next(count)
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    if #state.bookmarks == 0 then
        util.echo_ephemeral("No bookmarks saved")
        return
    end

    local n = count or 1
    for _ = 1, n do
        if #state.bookmarks == 1 then
            state.bookmarks_idx = 1
        elseif state.bookmarks_idx == -1 then
            state.bookmarks_idx = #state.bookmarks
        elseif state.bookmarks_idx <= 1 then
            state.bookmarks_idx = #state.bookmarks
        else
            state.bookmarks_idx = state.bookmarks_idx - 1
        end
    end

    M.jump_to_index(state.bookmarks_idx)
end

--- Public API: delete bookmark at cursor.
function M.delete()
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    M.delete_at_cursor()
end

--- Public API: jump to bookmark by index.
---@param index integer
function M.goto_bookmark(index)
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    M.jump_to_index(index)
end

-- ============================================================================
-- Toggle
-- ============================================================================

--- Toggle bookmark at the current line.
function M.toggle()
    state.warn_if_no_setup()
    if filter.should_ignore_buffer() then
        return
    end
    local pos_data = util.get_cursor_position()
    if not pos_data then
        vim.notify("Cannot toggle bookmark in this buffer", vim.log.levels.WARN)
        return
    end

    local r, fname = pos_data.row, pos_data.fname

    local auto_indices = {}
    for i, pos in ipairs(state.automarks) do
        extmarks.sync_from_extmark(pos, state.ns_automark)
        if pos.fname == fname and pos.row == r then
            table.insert(auto_indices, i)
        end
    end

    local bm_indices = {}
    for i, b in ipairs(state.bookmarks) do
        extmarks.sync_from_extmark(b, state.ns_bookmark)
        if b.fname == fname and b.row == r then
            table.insert(bm_indices, i)
        end
    end

    if #auto_indices > 0 or #bm_indices > 0 then
        for j = #auto_indices, 1, -1 do
            local i = auto_indices[j]
            extmarks.remove(state.automarks[i], state.ns_automark)
            table.remove(state.automarks, i)
            state.automarks_idx = state.adjust_index_after_removal(state.automarks_idx, i, #state.automarks)
        end

        for j = #bm_indices, 1, -1 do
            local i = bm_indices[j]
            extmarks.remove(state.bookmarks[i], state.ns_bookmark)
            table.remove(state.bookmarks, i)
            state.bookmarks_idx = state.adjust_index_after_removal(state.bookmarks_idx, i, #state.bookmarks)
        end

        state.merged_last_mark = nil

        if #bm_indices > 0 then
            M.save()
        end

        local parts = {}
        if #auto_indices > 0 then
            table.insert(parts, #auto_indices .. " automark" .. (#auto_indices > 1 and "s" or ""))
        end
        if #bm_indices > 0 then
            table.insert(parts, #bm_indices .. " bookmark" .. (#bm_indices > 1 and "s" or ""))
        end
        util.echo_ephemeral(string.format("Deleted %s at line %d", table.concat(parts, " + "), r))
    else
        M.add()
    end
end

--- Remove all bookmarks.
function M.clear()
    state.warn_if_no_setup()
    for _, mark in ipairs(state.bookmarks) do
        extmarks.remove(mark, state.ns_bookmark)
    end
    state.clear_list(state.bookmarks)
    state.bookmarks_idx = -1
    state.merged_last_mark = nil
    M.save()
    util.echo_ephemeral("All bookmarks cleared")
end

--- Return a deep copy of the bookmarks list.
---@return WaymarkBookmark[]
function M.get()
    return vim.deepcopy(state.bookmarks)
end

-- ============================================================================
-- Startup / Shutdown autocmds
-- ============================================================================

function M.setup()
    vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Load bookmarks from disk and clean up stale entries",
        group = vim.api.nvim_create_augroup("waymark_vim_enter", { clear = true }),
        callback = function()
            M.load()
            state.sync_mark_id_counter()
            M.cleanup()

            vim.defer_fn(function()
                local bufnr = vim.api.nvim_get_current_buf()
                if vim.api.nvim_buf_is_valid(bufnr) then
                    extmarks.restore_for_buffer(
                        bufnr,
                        state.bookmarks,
                        state.ns_bookmark,
                        config.current.bookmark_sign,
                        "WaymarkBookmarkSign",
                        "WaymarkBookmarkNum"
                    )
                end
            end, 100)
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        desc = "Sync all extmark positions and save bookmarks before Neovim exits",
        group = vim.api.nvim_create_augroup("waymark_vim_leave", { clear = true }),
        callback = function()
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
                    extmarks.sync_buffer_positions(buf, state.bookmarks, state.ns_bookmark)
                end
            end
            extmarks.deduplicate_bookmarks()
            M.save(true)

            state.close_timer(state.debounce_timer)
            state.close_timer(state.bookmarks_save_timer)
        end,
    })
end

return M
