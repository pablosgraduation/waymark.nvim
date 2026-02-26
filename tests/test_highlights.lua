-- tests/test_highlights.lua
local highlights = require("waymark.highlights")
local config = require("waymark.config")
local helpers = require("tests.helpers")

describe("waymark.highlights", function()
    before_each(function()
        helpers.reset()
        config.setup({})
    end)

    it("creates all 10 expected highlight groups", function()
        highlights.setup()
        local groups = {
            "WaymarkAutomarkSign",
            "WaymarkAutomarkNum",
            "WaymarkBookmarkSign",
            "WaymarkBookmarkNum",
            "WaymarkFlash",
            "WaymarkPopupCheck",
            "WaymarkPopupUncheck",
            "WaymarkPopupSign",
            "WaymarkPopupPreview",
            "WaymarkPopupHelp",
        }
        for _, name in ipairs(groups) do
            local hl = vim.api.nvim_get_hl(0, { name = name })
            assert.is_not_nil(next(hl), name .. " should be defined")
        end
    end)

    it("uses configured sign colors", function()
        config.setup({
            automark_sign_color = "#FF0000",
            bookmark_sign_color = "#00FF00",
        })
        highlights.apply()
        local auto_hl = vim.api.nvim_get_hl(0, { name = "WaymarkAutomarkSign" })
        assert.equals(0xFF0000, auto_hl.fg)
        local book_hl = vim.api.nvim_get_hl(0, { name = "WaymarkBookmarkSign" })
        assert.equals(0x00FF00, book_hl.fg)
    end)

    it("uses configured popup colors", function()
        config.setup({
            popup_check_color = "#AABBCC",
        })
        highlights.apply()
        local hl = vim.api.nvim_get_hl(0, { name = "WaymarkPopupCheck" })
        assert.equals(0xAABBCC, hl.fg)
    end)

    it("uses configured flash color as background", function()
        config.setup({
            jump_flash_color = "#112233",
        })
        highlights.apply()
        local hl = vim.api.nvim_get_hl(0, { name = "WaymarkFlash" })
        assert.equals(0x112233, hl.bg)
    end)

    it("is idempotent", function()
        highlights.setup()
        highlights.setup()
        local hl = vim.api.nvim_get_hl(0, { name = "WaymarkFlash" })
        assert.is_not_nil(next(hl))
    end)
end)
