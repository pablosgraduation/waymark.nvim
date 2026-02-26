-- ============================================================================
-- plugin/waymark.lua — Neovim plugin entrypoint (loaded at startup).
-- ============================================================================
-- This file is intentionally minimal. It exists so that plugin managers and
-- Neovim's built-in package loader recognise waymark as a plugin. All heavy
-- lifting is deferred until require("waymark").setup() is called.
--
-- If you use a lazy-loading plugin manager (lazy.nvim, packer, etc.), this
-- file ensures :Waymark* commands exist immediately so that mappings and
-- command-line completions work even before setup() runs.
-- ============================================================================

if vim.g.loaded_waymark then
    return
end
vim.g.loaded_waymark = true
