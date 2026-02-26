-- ============================================================================
-- waymark.popup — Interactive bookmarks floating window.
-- ============================================================================
-- The popup is a modal floating window displaying one bookmark per line.
-- Navigate with j/k, toggle selection with Space, then act: Enter to jump
-- (or open multiple in vsplits), d to delete, K/J to reorder. The popup
-- auto-closes on q, Esc, or WinLeave. Cursor is clamped to bookmark lines.

local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local extmarks = require("waymark.extmarks")
local bookmark = require("waymark.bookmark")

local M = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---@return integer
local function count_selected()
    local count = 0
    for _, b in ipairs(state.bookmarks) do
        if state.popup_selected[b.id] then
            count = count + 1
        end
    end
    return count
end

---@return WaymarkBookmark[]
local function get_selected()
    local selected = {}
    for _, b in ipairs(state.bookmarks) do
        if state.popup_selected[b.id] then
            table.insert(selected, b)
        end
    end
    return selected
end

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------

---@return string[]
local function create_display_lines()
    local c = config.current
    local lines = { "" }

    if #state.bookmarks == 0 then
        table.insert(lines, "  No bookmarks created")
        table.insert(lines, "")
        table.insert(lines, "  q: quit")
        return lines
    end

    for i = 1, #state.bookmarks do
        local b = state.bookmarks[i]
        extmarks.sync_from_extmark(b, state.ns_bookmark)

        local checkbox = state.popup_selected[b.id] and "◆" or "◇"
        local indicator = (i == state.bookmarks_idx) and "→" or " "
        local path = util.format_path(b.fname)

        local cache_key = util.mark_key(b.fname, b.row)
        local preview = state.popup_preview_cache[cache_key]
        if preview == nil then
            preview = util.get_line_preview(b.fname, b.row, 40) or false
            state.popup_preview_cache[cache_key] = preview
        end

        local line = string.format("%s%s %s %s:%d", indicator, checkbox, c.bookmark_sign, path, b.row)
        if preview then
            line = line .. "  │ " .. preview
        end
        table.insert(lines, line)
    end

    table.insert(lines, "")

    local selected_count = count_selected()
    if selected_count > 0 then
        table.insert(
            lines,
            string.format(
                " Space: toggle  ↵: jump (%d selected)  d: delete (%d)  K/J: reorder  q: quit",
                selected_count,
                selected_count
            )
        )
    else
        table.insert(lines, " Space: toggle  ↵: jump  d: delete  K/J: reorder  q: quit")
    end

    return lines
end

local function apply_highlights(buf, lines)
    local c = config.current
    vim.api.nvim_buf_clear_namespace(buf, state.ns_popup, 0, -1)

    for i, line in ipairs(lines) do
        local row = i - 1

        if i == #lines then
            vim.api.nvim_buf_add_highlight(buf, state.ns_popup, "WaymarkPopupHelp", row, 0, -1)
        elseif line:match("◆") or line:match("◇") then
            local is_checked = line:match("◆") ~= nil
            local hl = is_checked and "WaymarkPopupCheck" or "WaymarkPopupUncheck"

            local arrow = "→"
            if line:sub(1, #arrow) == arrow then
                vim.api.nvim_buf_add_highlight(buf, state.ns_popup, "WaymarkBookmarkSign", row, 0, #arrow)
            end

            local cb_char = is_checked and "◆" or "◇"
            local cb_start = line:find(cb_char, 1, true)
            if cb_start then
                vim.api.nvim_buf_add_highlight(buf, state.ns_popup, hl, row, cb_start - 1, cb_start - 1 + #cb_char)
            end

            local sign_char = c.bookmark_sign
            local sign_start = line:find(sign_char, 1, true)
            if sign_start then
                vim.api.nvim_buf_add_highlight(
                    buf,
                    state.ns_popup,
                    "WaymarkPopupSign",
                    row,
                    sign_start - 1,
                    sign_start - 1 + #sign_char
                )
            end

            local pipe_start = line:find("│", 1, true)
            if pipe_start then
                vim.api.nvim_buf_add_highlight(buf, state.ns_popup, "WaymarkPopupPreview", row, pipe_start - 1, -1)
            end
        end
    end
end

local function refresh_content()
    if not state.popup_buf or not vim.api.nvim_buf_is_valid(state.popup_buf) then
        return
    end

    state.popup_preview_cache = {}

    vim.bo[state.popup_buf].modifiable = true
    local new_lines = create_display_lines()
    vim.api.nvim_buf_set_lines(state.popup_buf, 0, -1, false, new_lines)
    apply_highlights(state.popup_buf, new_lines)
    vim.bo[state.popup_buf].modifiable = false

    if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
        local current_line = vim.api.nvim_win_get_cursor(state.popup_win)[1]
        local max_bookmark_line = #state.bookmarks + 1
        local safe_line = math.max(2, math.min(current_line, max_bookmark_line))
        pcall(vim.api.nvim_win_set_cursor, state.popup_win, { safe_line, 0 })
    end
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

local function toggle_selection()
    if #state.bookmarks == 0 then
        return
    end
    if not state.popup_win or not vim.api.nvim_win_is_valid(state.popup_win) then
        return
    end

    local current_line = vim.api.nvim_win_get_cursor(state.popup_win)[1]
    local idx = current_line - 1

    if idx >= 1 and idx <= #state.bookmarks then
        local bid = state.bookmarks[idx].id
        if state.popup_selected[bid] then
            state.popup_selected[bid] = nil
        else
            state.popup_selected[bid] = true
        end
        refresh_content()
    end
end

local function move_up()
    if #state.bookmarks < 2 then
        return
    end
    if not state.popup_win or not vim.api.nvim_win_is_valid(state.popup_win) then
        return
    end

    local current_line = vim.api.nvim_win_get_cursor(state.popup_win)[1]
    local idx = current_line - 1

    if idx > 1 and idx <= #state.bookmarks then
        state.bookmarks[idx], state.bookmarks[idx - 1] = state.bookmarks[idx - 1], state.bookmarks[idx]

        if state.bookmarks_idx == idx then
            state.bookmarks_idx = idx - 1
        elseif state.bookmarks_idx == idx - 1 then
            state.bookmarks_idx = idx
        end

        bookmark.save()
        refresh_content()
        pcall(vim.api.nvim_win_set_cursor, state.popup_win, { current_line - 1, 0 })
    end
end

local function move_down()
    if #state.bookmarks < 2 then
        return
    end
    if not state.popup_win or not vim.api.nvim_win_is_valid(state.popup_win) then
        return
    end

    local current_line = vim.api.nvim_win_get_cursor(state.popup_win)[1]
    local idx = current_line - 1

    if idx > 0 and idx < #state.bookmarks then
        state.bookmarks[idx], state.bookmarks[idx + 1] = state.bookmarks[idx + 1], state.bookmarks[idx]

        if state.bookmarks_idx == idx then
            state.bookmarks_idx = idx + 1
        elseif state.bookmarks_idx == idx + 1 then
            state.bookmarks_idx = idx
        end

        bookmark.save()
        refresh_content()
        pcall(vim.api.nvim_win_set_cursor, state.popup_win, { current_line + 1, 0 })
    end
end

local function delete_selected()
    local selected = get_selected()

    if #selected == 0 then
        if not state.popup_win or not vim.api.nvim_win_is_valid(state.popup_win) then
            return
        end
        local current_line = vim.api.nvim_win_get_cursor(state.popup_win)[1]
        local idx = current_line - 1

        if idx > 0 and idx <= #state.bookmarks then
            state.popup_selected[state.bookmarks[idx].id] = nil
            extmarks.remove(state.bookmarks[idx], state.ns_bookmark)
            table.remove(state.bookmarks, idx)
            state.bookmarks_idx = state.adjust_index_after_removal(state.bookmarks_idx, idx, #state.bookmarks)
            bookmark.save()
            state.merged_last_mark = nil
        end
    else
        local indices = {}
        for i, b in ipairs(state.bookmarks) do
            if state.popup_selected[b.id] then
                table.insert(indices, i)
            end
        end

        table.sort(indices, function(a, b)
            return a > b
        end)

        for _, idx in ipairs(indices) do
            state.popup_selected[state.bookmarks[idx].id] = nil
            extmarks.remove(state.bookmarks[idx], state.ns_bookmark)
            table.remove(state.bookmarks, idx)
        end

        state.bookmarks_idx = -1
        state.merged_last_mark = nil
        bookmark.save()
    end

    refresh_content()
end

local function jump_to_selected()
    local selected = get_selected()

    if #selected > 5 then
        vim.notify(
            string.format("Too many bookmarks selected (%d/5). Please reduce selection to 5 or fewer.", #selected),
            vim.log.levels.WARN
        )
        return
    end

    if #selected == 0 then
        if not state.popup_win or not vim.api.nvim_win_is_valid(state.popup_win) then
            return
        end
        local current_line = vim.api.nvim_win_get_cursor(state.popup_win)[1]
        local idx = current_line - 1

        if idx > 0 and idx <= #state.bookmarks then
            vim.api.nvim_win_close(state.popup_win, true)
            bookmark.jump_to_index(idx)
        end
    elseif #selected == 1 then
        vim.api.nvim_win_close(state.popup_win, true)
        local i = util.find_mark_index_by_id(state.bookmarks, selected[1].id)
        if i then
            bookmark.jump_to_index(i)
        end
    else
        vim.api.nvim_win_close(state.popup_win, true)

        state.begin_navigation_with_fallback()

        local first_ok = false
        local first_i = util.find_mark_index_by_id(state.bookmarks, selected[1].id)
        if first_i then
            local b = state.bookmarks[first_i]
            first_ok = util.jump_to_position(b.fname, b.row, b.col)
            if first_ok then
                state.bookmarks_idx = first_i
            end
        end

        if not first_ok then
            vim.notify("Could not open first bookmark", vim.log.levels.WARN)
            state.end_navigation()
            return
        end

        local opened_wins = {}
        for j = 2, #selected do
            vim.cmd("vsplit")
            local new_win = vim.api.nvim_get_current_win()
            table.insert(opened_wins, new_win)

            local ok = false
            local bi = util.find_mark_index_by_id(state.bookmarks, selected[j].id)
            if bi then
                local b = state.bookmarks[bi]
                ok = util.jump_to_position(b.fname, b.row, b.col)
                if ok then
                    state.bookmarks_idx = bi
                end
            end

            if not ok then
                for _, w in ipairs(opened_wins) do
                    if vim.api.nvim_win_is_valid(w) then
                        pcall(vim.api.nvim_win_close, w, true)
                    end
                end
                vim.notify("Failed to open some bookmarks — cleaned up splits", vim.log.levels.WARN)
                state.end_navigation()
                return
            end
        end

        state.end_navigation()
    end
end

-- ---------------------------------------------------------------------------
-- Popup dimensions
-- ---------------------------------------------------------------------------

local function calc_dimensions(content_lines)
    local min_width = 40
    local max_width = math.min(120, math.floor(vim.o.columns * 0.8))
    local width = min_width
    for _, line in ipairs(content_lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line) + 4)
    end
    width = math.min(width, max_width)
    local height = math.min(#content_lines, math.floor(vim.o.lines * 0.8))
    return width, height
end

-- ---------------------------------------------------------------------------
-- Show
-- ---------------------------------------------------------------------------

function M.show()
    state.warn_if_no_setup()

    if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
        vim.api.nvim_win_close(state.popup_win, true)
    end
    if state.popup_buf and vim.api.nvim_buf_is_valid(state.popup_buf) then
        vim.api.nvim_buf_delete(state.popup_buf, { force = true })
    end

    state.popup_selected = {}
    state.popup_preview_cache = {}

    local lines = create_display_lines()

    state.popup_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(state.popup_buf, 0, -1, false, lines)
    apply_highlights(state.popup_buf, lines)
    vim.bo[state.popup_buf].modifiable = false

    local width, height = calc_dimensions(lines)

    state.popup_win = vim.api.nvim_open_win(state.popup_buf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = (vim.o.columns - width) / 2,
        row = (vim.o.lines - height) / 2,
        style = "minimal",
        border = "rounded",
        title = " Bookmarks ",
        title_pos = "center",
    })

    vim.wo[state.popup_win].winfixbuf = true
    vim.wo[state.popup_win].cursorline = true

    local this_popup_win = state.popup_win
    local this_popup_buf = state.popup_buf

    -- Cleanup autocmd
    vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(this_popup_win),
        once = true,
        callback = function()
            if state.popup_buf == this_popup_buf and vim.api.nvim_buf_is_valid(this_popup_buf) then
                pcall(vim.api.nvim_buf_delete, this_popup_buf, { force = true })
            end
            pcall(vim.api.nvim_del_augroup_by_name, "waymark_popup_resize_" .. this_popup_buf)
            pcall(vim.api.nvim_del_augroup_by_name, "waymark_popup_cursor_" .. this_popup_buf)
            pcall(vim.api.nvim_del_augroup_by_name, "waymark_popup_refresh_" .. this_popup_buf)
            pcall(vim.api.nvim_del_augroup_by_name, "waymark_popup_leave_" .. this_popup_buf)
            if state.popup_win == this_popup_win then
                state.popup_win = nil
            end
            if state.popup_buf == this_popup_buf then
                state.popup_buf = nil
                state.popup_selected = {}
                state.popup_preview_cache = {}
            end
        end,
    })

    -- Auto-close on focus loss
    vim.api.nvim_create_autocmd("WinLeave", {
        group = vim.api.nvim_create_augroup("waymark_popup_leave_" .. this_popup_buf, { clear = true }),
        buffer = this_popup_buf,
        callback = function()
            if this_popup_win and vim.api.nvim_win_is_valid(this_popup_win) then
                vim.api.nvim_win_close(this_popup_win, true)
            end
        end,
    })

    if #state.bookmarks > 0 then
        pcall(vim.api.nvim_win_set_cursor, state.popup_win, { 2, 0 })
    end

    -- Refresh on external writes
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("waymark_popup_refresh_" .. this_popup_buf, { clear = true }),
        callback = function(ev)
            if ev.buf == this_popup_buf then
                return
            end
            if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
                refresh_content()
            end
        end,
    })

    -- Resize on terminal resize
    vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("waymark_popup_resize_" .. state.popup_buf, { clear = true }),
        callback = function()
            if not state.popup_win or not vim.api.nvim_win_is_valid(state.popup_win) then
                return
            end
            if not state.popup_buf or not vim.api.nvim_buf_is_valid(state.popup_buf) then
                return
            end

            local cur_lines = vim.api.nvim_buf_get_lines(state.popup_buf, 0, -1, false)
            local new_width, new_height = calc_dimensions(cur_lines)

            pcall(vim.api.nvim_win_set_config, state.popup_win, {
                relative = "editor",
                width = new_width,
                height = new_height,
                col = (vim.o.columns - new_width) / 2,
                row = (vim.o.lines - new_height) / 2,
            })
        end,
    })

    local opts = { buffer = state.popup_buf, nowait = true, silent = true }

    -- Clamp cursor to bookmark lines
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = vim.api.nvim_create_augroup("waymark_popup_cursor_" .. state.popup_buf, { clear = true }),
        buffer = state.popup_buf,
        callback = function()
            if not state.popup_win or not vim.api.nvim_win_is_valid(state.popup_win) then
                return
            end
            local cur = vim.api.nvim_win_get_cursor(state.popup_win)[1]
            local min_line = 2
            local max_line = math.max(2, #state.bookmarks + 1)
            if cur < min_line then
                vim.api.nvim_win_set_cursor(state.popup_win, { min_line, 0 })
            elseif cur > max_line then
                vim.api.nvim_win_set_cursor(state.popup_win, { max_line, 0 })
            end
        end,
    })

    -- Keybindings
    local function close_popup()
        if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
            vim.api.nvim_win_close(state.popup_win, true)
        end
    end
    vim.keymap.set("n", "q", close_popup, opts)
    vim.keymap.set("n", "<Esc>", close_popup, opts)
    vim.keymap.set("n", "<Space>", toggle_selection, opts)
    vim.keymap.set("n", "v", toggle_selection, opts)
    vim.keymap.set("n", "<CR>", jump_to_selected, opts)
    vim.keymap.set("n", "d", delete_selected, opts)
    vim.keymap.set("n", "K", move_up, opts)
    vim.keymap.set("n", "J", move_down, opts)

    -- Block keys that would trigger E21
    local nop = "<Nop>"
    for _, key in ipairs({
        "V",
        "<C-v>",
        "i",
        "I",
        "a",
        "A",
        "o",
        "O",
        "c",
        "C",
        "s",
        "S",
        "R",
        "x",
        "X",
        "r",
        "p",
        "P",
    }) do
        vim.keymap.set("n", key, nop, opts)
    end
end

return M
