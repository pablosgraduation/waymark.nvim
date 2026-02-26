-- ============================================================================
-- waymark.highlights — Highlight group definitions.
-- ============================================================================

local config = require("waymark.config")

local M = {}

--- Define (or redefine) all highlight groups used by the plugin.
--- Called during setup() and again on ColorScheme changes, since many
--- colorschemes clear all custom highlight groups when they load.
function M.apply()
    local c = config.current

    -- Gutter signs
    vim.api.nvim_set_hl(0, "WaymarkAutomarkSign", { fg = c.automark_sign_color, bg = "NONE" })
    vim.api.nvim_set_hl(0, "WaymarkAutomarkNum", { fg = c.automark_sign_color, bg = "NONE" })
    vim.api.nvim_set_hl(0, "WaymarkBookmarkSign", { fg = c.bookmark_sign_color, bg = "NONE" })
    vim.api.nvim_set_hl(0, "WaymarkBookmarkNum", { fg = c.bookmark_sign_color, bg = "NONE" })

    -- Jump flash (full-line background highlight)
    vim.api.nvim_set_hl(0, "WaymarkFlash", { bg = c.jump_flash_color })

    -- Bookmarks popup
    vim.api.nvim_set_hl(0, "WaymarkPopupCheck", { fg = c.popup_check_color })
    vim.api.nvim_set_hl(0, "WaymarkPopupUncheck", { fg = c.popup_uncheck_color })
    vim.api.nvim_set_hl(0, "WaymarkPopupSign", { fg = c.bookmark_sign_color })
    vim.api.nvim_set_hl(0, "WaymarkPopupPreview", { fg = c.popup_preview_color, italic = true })
    vim.api.nvim_set_hl(0, "WaymarkPopupHelp", { fg = c.popup_help_color })
end

--- Register the ColorScheme autocmd to reapply highlights when themes change.
function M.setup()
    M.apply()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("waymark_highlights", { clear = true }),
        callback = M.apply,
    })
end

-- Apply once at load time (so signs render even without setup())
M.apply()

return M
