-- ============================================================================
-- waymark.health — :checkhealth waymark
-- ============================================================================

local M = {}

function M.check()
    vim.health.start("waymark")

    -- Neovim version check
    if vim.fn.has("nvim-0.10") == 1 then
        vim.health.ok("Neovim >= 0.10")
    elseif vim.fn.has("nvim-0.9") == 1 then
        vim.health.warn("Neovim 0.9 detected; some features may be degraded (vim.uv)")
    else
        vim.health.error("Neovim >= 0.9 is required")
    end

    -- Setup check
    local state = require("waymark.state")
    if state.setup_done then
        vim.health.ok("setup() has been called")
    else
        vim.health.warn("setup() has not been called yet — keymaps and bookmark persistence are inactive")
    end

    -- Bookmark file
    local bookmarks_file = state.bookmarks_file
    local dir = vim.fn.fnamemodify(bookmarks_file, ":h")
    if vim.fn.isdirectory(dir) == 1 then
        vim.health.ok("Data directory exists: " .. dir)
    else
        vim.health.info("Data directory will be created on first save: " .. dir)
    end

    if vim.fn.filereadable(bookmarks_file) == 1 then
        vim.health.ok("Bookmark file found: " .. bookmarks_file .. " (" .. #state.bookmarks .. " bookmarks)")
    else
        vim.health.info("No bookmark file yet (will be created on first bookmark)")
    end

    -- JSON capability check
    local json_encode = vim.json and vim.json.encode or vim.fn.json_encode
    local json_decode = vim.json and vim.json.decode or vim.fn.json_decode
    local json_ok = pcall(function()
        local encoded = json_encode({ test = true })
        json_decode(encoded)
    end)
    if json_ok then
        vim.health.ok("JSON encode/decode working")
    else
        vim.health.error("JSON encode/decode failed — bookmark persistence will not work")
    end

    -- State summary
    vim.health.ok(
        string.format("Automarks: %d (limit: %d)", #state.automarks, require("waymark.config").current.automark_limit)
    )
    vim.health.ok(string.format("Bookmarks: %d", #state.bookmarks))
end

return M
