-- ============================================================================
-- waymark.util — Shared utility functions.
-- ============================================================================

local config = require("waymark.config")
local state = require("waymark.state")

local M = {}

-- ---------------------------------------------------------------------------
-- Path normalization (two-generation cache)
-- ---------------------------------------------------------------------------
-- vim.fn.fnamemodify does a Vimscript round-trip on each call, so results
-- are memoized. A simple unbounded cache would grow without limit in long
-- sessions, so we use a two-generation scheme: when the active generation
-- is full (500 entries), it becomes the "previous" generation and a new
-- empty one starts. Lookups check both generations; hits in the previous
-- generation are promoted to the active one. This bounds memory to ~1000
-- entries while still keeping the working set warm.
local normalize_path_prev = {}
local normalize_path_curr = {}
local normalize_path_curr_size = 0
local normalize_path_max = 500

--- Normalize a filename to its absolute path, with two-generation caching.
---@param fname string|nil  Raw filename from nvim_buf_get_name() or similar
---@return string           Absolute path, or "" if input is nil/empty
function M.normalize_path(fname)
    if not fname or fname == "" then
        return ""
    end

    local cached = normalize_path_curr[fname]
    if cached then
        return cached
    end

    cached = normalize_path_prev[fname]
    if cached then
        normalize_path_curr[fname] = cached
        normalize_path_curr_size = normalize_path_curr_size + 1
        normalize_path_prev[fname] = nil
        return cached
    end

    local result = vim.fn.fnamemodify(fname, ":p")

    if normalize_path_curr_size >= normalize_path_max then
        normalize_path_prev = normalize_path_curr
        normalize_path_curr = {}
        normalize_path_curr_size = 0
    end

    normalize_path_curr[fname] = result
    normalize_path_curr_size = normalize_path_curr_size + 1
    return result
end

--- Invalidate a specific path from the cache.
---@param fname string
function M.invalidate_path_cache(fname)
    if normalize_path_curr[fname] then
        normalize_path_curr[fname] = nil
        normalize_path_curr_size = normalize_path_curr_size - 1
    end
    normalize_path_prev[fname] = nil
end

-- ---------------------------------------------------------------------------
-- Cursor & buffer helpers
-- ---------------------------------------------------------------------------

--- Get the cursor position in the current buffer, returning nil if the buffer
--- should be ignored or has no associated file.
---@return WaymarkCursorPosition|nil
function M.get_cursor_position()
    local filter = require("waymark.filter")
    if filter.should_ignore_buffer() then
        return nil
    end

    local cursor = vim.api.nvim_win_get_cursor(0)
    local fname = M.normalize_path(vim.api.nvim_buf_get_name(0))
    if fname == "" then
        return nil
    end

    return { row = cursor[1], col = cursor[2] + 1, fname = fname }
end

--- Format a filename for display: project-relative if possible, otherwise ~/.
---@param fname string  Absolute path
---@return string       Shortened display path
function M.format_path(fname)
    return vim.fn.fnamemodify(fname, ":~:.")
end

--- Show an ephemeral notification in the command line.
---@param msg string  Message to display
function M.echo_ephemeral(msg)
    vim.api.nvim_echo({ { msg } }, false, {})
end

--- Build a deduplication key from a filename and row number.
---@param fname string   Absolute file path
---@param row integer    1-indexed line number
---@return string
function M.mark_key(fname, row)
    return fname .. "\0" .. row
end

--- Find the index of a mark with the given ID in a list.
---@param list (WaymarkAutomark|WaymarkBookmark|WaymarkMergedMark)[]
---@param id integer     Mark ID to search for
---@return integer|nil   1-based index, or nil if not found
function M.find_mark_index_by_id(list, id)
    for i, m in ipairs(list) do
        if m.id == id then
            return i
        end
    end
    return nil
end

--- Ensure the parent directory of a path exists.
---@param path string  File path whose parent directory should exist
function M.ensure_parent_dir(path)
    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
    end
end

-- ---------------------------------------------------------------------------
-- Line preview
-- ---------------------------------------------------------------------------

--- Read and truncate a single line from a file for preview display.
---@param fname string    Absolute file path
---@param row integer     1-indexed line number
---@param max_len integer|nil  Maximum display character length (default 50)
---@return string|nil     Trimmed line content, or nil if unavailable
function M.get_line_preview(fname, row, max_len)
    max_len = max_len or 50

    local function truncate(line)
        line = vim.trim(line)
        if vim.fn.strchars(line) > max_len then
            return vim.fn.strcharpart(line, 0, max_len) .. "…"
        end
        if #line > 0 then
            return line
        end
        return nil
    end

    local bufnr = vim.fn.bufnr(fname)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, row - 1, row, false)
        if ok and #lines > 0 then
            return truncate(lines[1])
        end
    end

    if vim.fn.filereadable(fname) == 1 then
        local f = io.open(fname, "r")
        if f then
            for _ = 1, row - 1 do
                if not f:read("*l") then
                    f:close()
                    return nil
                end
            end
            local line = f:read("*l")
            f:close()
            if line then
                return truncate(line)
            end
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Jump flash
-- ---------------------------------------------------------------------------

--- Briefly highlight the current line after a jump.
function M.flash_line()
    local c = config.current
    if c.jump_flash_ms <= 0 then
        return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local ok, ext_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, state.ns_flash, row, 0, {
        line_hl_group = "WaymarkFlash",
    })
    if ok then
        vim.defer_fn(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
                pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_flash, ext_id)
            end
        end, c.jump_flash_ms)
    end
end

-- ---------------------------------------------------------------------------
-- Navigation jump
-- ---------------------------------------------------------------------------

--- Open a file, set the cursor, center the view, and flash the landing line.
---@param fname string           Absolute file path
---@param row integer            1-indexed target line
---@param col integer|nil        1-indexed target column (defaults to 1)
---@param tab_id integer|nil     Tab page handle to restore
---@param window_id integer|nil  Window handle to restore
---@return boolean               true if the jump succeeded
function M.jump_to_position(fname, row, col, tab_id, window_id)
    if vim.wo.winfixbuf then
        return false
    end

    if tab_id and vim.api.nvim_tabpage_is_valid(tab_id) then
        vim.api.nvim_set_current_tabpage(tab_id)
        if window_id and vim.api.nvim_win_is_valid(window_id) then
            local win_buf = vim.api.nvim_win_get_buf(window_id)
            local win_fname = M.normalize_path(vim.api.nvim_buf_get_name(win_buf))
            if win_fname == M.normalize_path(fname) then
                vim.api.nvim_set_current_win(window_id)
            end
        end
    end

    local safe_col = math.max(0, (col or 1) - 1)
    local norm_fname = M.normalize_path(fname)

    local cur_buf_name = M.normalize_path(vim.api.nvim_buf_get_name(0))
    if cur_buf_name ~= norm_fname then
        local target_buf = vim.fn.bufnr(norm_fname)
        if target_buf ~= -1 and vim.api.nvim_buf_is_loaded(target_buf) then
            local ok, err = pcall(vim.api.nvim_set_current_buf, target_buf)
            if not ok then
                vim.notify("Could not switch buffer: " .. tostring(err), vim.log.levels.WARN)
                return false
            end
        else
            local ok, err = pcall(function()
                vim.cmd.edit({ args = { norm_fname }, mods = { silent = true } })
            end)
            if not ok then
                vim.notify("Could not open file: " .. tostring(err), vim.log.levels.WARN)
                return false
            end
        end
    end

    local line_count = vim.api.nvim_buf_line_count(0)
    local safe_row = math.max(1, math.min(row, line_count))
    local success = pcall(vim.api.nvim_win_set_cursor, 0, { safe_row, safe_col })

    if not success then
        success = pcall(vim.api.nvim_win_set_cursor, 0, { safe_row, 0 })
    end

    if success then
        pcall(vim.cmd, "normal! zz")
        M.flash_line()
    end

    return success
end

return M
