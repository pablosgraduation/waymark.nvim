-- tests/helpers.lua
-- Shared utilities for waymark test files.

local M = {}

--- Create a temporary file with content and return its absolute path.
---@param lines string[]  Lines to write
---@param name string|nil  Optional filename (default: random)
---@return string path     Absolute path to the created file
function M.create_temp_file(lines, name)
    local tmp_dir = vim.fn.tempname()
    vim.fn.mkdir(tmp_dir, "p")
    local fname = tmp_dir .. "/" .. (name or "test_file.lua")
    vim.fn.writefile(lines, fname)
    return fname
end

--- Open a file in the current buffer and return the buffer number.
---@param path string  Absolute file path
---@return integer bufnr
function M.open_file(path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    return vim.api.nvim_get_current_buf()
end

--- Reset all waymark state between tests. Call in before_each.
function M.reset()
    local state = require("waymark.state")
    local extmarks = require("waymark.extmarks")

    -- Clear automarks
    for _, mark in ipairs(state.automarks) do
        extmarks.remove(mark, state.ns_automark)
    end
    state.clear_list(state.automarks)
    state.automarks_idx = -1

    -- Clear bookmarks
    for _, mark in ipairs(state.bookmarks) do
        extmarks.remove(mark, state.ns_bookmark)
    end
    state.clear_list(state.bookmarks)
    state.bookmarks_idx = -1

    -- Reset counters and state
    state.mark_id_counter = 0
    state.merged_last_mark = nil
    state.last_position = { fname = "", row = 0, time = 0 }
    state.navigating = false
    state.nav_generation = 0
    state.setup_done = true
    state.setup_warned = false
    state.ignore_cache = {}

    -- Remove the bookmarks file if it exists
    pcall(os.remove, state.bookmarks_file)
end

--- Set the cursor to a specific position in the current buffer.
---@param row integer  1-indexed line
---@param col integer  0-indexed column
function M.set_cursor(row, col)
    vim.api.nvim_win_set_cursor(0, { row, col or 0 })
end

--- Clean up all temp buffers.
function M.cleanup_buffers()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
end

return M
