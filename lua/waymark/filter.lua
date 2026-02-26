-- ============================================================================
-- waymark.filter — Buffer filtering and ignore logic.
-- ============================================================================

local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")

local M = {}

--- Determine whether a buffer should be excluded from automark tracking.
---@param bufnr integer|nil  Buffer number (defaults to current buffer)
---@return boolean           true if the buffer should be ignored
function M.should_ignore_buffer(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    -- Always ignore the bookmarks popup buffer
    if state.popup_buf and bufnr == state.popup_buf then
        return true
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
        return true
    end

    local cached = state.ignore_cache[bufnr]
    if cached ~= nil then
        return cached
    end

    local buftype = vim.bo[bufnr].buftype
    -- Non-empty buftype means terminal, quickfix, help, prompt, etc. — not regular files.
    if buftype ~= "" then
        state.ignore_cache[bufnr] = true
        return true
    end

    local fname = vim.api.nvim_buf_get_name(bufnr)
    local filetype = vim.bo[bufnr].filetype
    local c = config.current

    if c._ignored_ft_set and c._ignored_ft_set[filetype] then
        state.ignore_cache[bufnr] = true
        return true
    end

    for _, pattern in ipairs(c.ignored_patterns) do
        if fname:match(pattern) then
            state.ignore_cache[bufnr] = true
            return true
        end
    end

    state.ignore_cache[bufnr] = false
    return false
end

--- Register autocmds for cache invalidation and buffer rename handling.
function M.setup()
    -- Invalidate cache when buffer conditions change
    vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter", "BufDelete" }, {
        group = vim.api.nvim_create_augroup("waymark_ignore_cache", { clear = true }),
        callback = function(args)
            state.ignore_cache[args.buf] = nil
        end,
    })

    -- Handle buffer renames (:saveas, :file)
    vim.api.nvim_create_autocmd("BufFilePost", {
        group = vim.api.nvim_create_augroup("waymark_path_cache", { clear = true }),
        callback = function(args)
            local bufnr = args.buf
            local new_fname = util.normalize_path(vim.api.nvim_buf_get_name(bufnr))

            local old_fname = nil
            for _, mark in ipairs(state.automarks) do
                if mark.bufnr == bufnr and mark.fname ~= new_fname then
                    old_fname = mark.fname
                    break
                end
            end
            if not old_fname then
                for _, mark in ipairs(state.bookmarks) do
                    if mark.bufnr == bufnr and mark.fname ~= new_fname then
                        old_fname = mark.fname
                        break
                    end
                end
            end

            if old_fname and new_fname ~= "" then
                local bookmarks_changed = false
                for _, mark in ipairs(state.automarks) do
                    if mark.fname == old_fname then
                        mark.fname = new_fname
                    end
                end
                for _, mark in ipairs(state.bookmarks) do
                    if mark.fname == old_fname then
                        mark.fname = new_fname
                        bookmarks_changed = true
                    end
                end
                if bookmarks_changed then
                    require("waymark.bookmark").save()
                end
            end

            if old_fname then
                util.invalidate_path_cache(old_fname)
            end
            local raw_name = vim.api.nvim_buf_get_name(bufnr)
            if raw_name ~= old_fname then
                util.invalidate_path_cache(raw_name)
            end
        end,
    })
end

return M
