-- tests/test_navigation_from_special.lua
local filter = require("waymark.filter")
local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local helpers = require("tests.helpers")

describe("navigation from special buffers", function()
    before_each(function()
        helpers.reset()
        config.setup({})
    end)

    describe("should_block_navigation", function()
        it("returns false for a normal file buffer", function()
            local path = helpers.create_temp_file({ "hello" })
            helpers.open_file(path)
            assert.is_false(filter.should_block_navigation())
        end)

        it("returns true for the popup buffer", function()
            local buf = vim.api.nvim_create_buf(false, true)
            state.popup_buf = buf
            assert.is_true(filter.should_block_navigation(buf))
            state.popup_buf = nil
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("returns true for an invalid buffer", function()
            assert.is_true(filter.should_block_navigation(999999))
        end)

        it("returns false for an allowlisted filetype", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = "nofile"
            vim.bo[buf].filetype = "snacks_picker_list"
            -- Normally nofile buftype would be ignored, but allowlist overrides
            assert.is_false(filter.should_block_navigation(buf))
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("returns false for neo-tree filetype (in default allowlist)", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = "nofile"
            vim.bo[buf].filetype = "neo-tree"
            assert.is_false(filter.should_block_navigation(buf))
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("returns true for non-allowlisted ignored filetype", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = ""
            vim.bo[buf].filetype = "help"
            assert.is_true(filter.should_block_navigation(buf))
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("returns true for non-allowlisted nofile buftype", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = "nofile"
            vim.bo[buf].filetype = "somethingrandom"
            assert.is_true(filter.should_block_navigation(buf))
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("respects custom navigation_filetype_allowlist", function()
            config.setup({ navigation_filetype_allowlist = { "myexplorer" } })

            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = "nofile"
            vim.bo[buf].filetype = "myexplorer"
            assert.is_false(filter.should_block_navigation(buf))

            -- snacks_picker_list no longer in allowlist
            local buf2 = vim.api.nvim_create_buf(false, true)
            vim.bo[buf2].buftype = "nofile"
            vim.bo[buf2].filetype = "snacks_picker_list"
            assert.is_true(filter.should_block_navigation(buf2))

            pcall(vim.api.nvim_buf_delete, buf, { force = true })
            pcall(vim.api.nvim_buf_delete, buf2, { force = true })
        end)
    end)

    describe("should_ignore_buffer still blocks mark placement", function()
        it("blocks allowlisted filetypes for mark placement", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = "nofile"
            vim.bo[buf].filetype = "snacks_picker_list"
            -- should_ignore_buffer should still return true (blocks placement)
            assert.is_true(filter.should_ignore_buffer(buf))
            -- but should_block_navigation returns false (allows navigation)
            assert.is_false(filter.should_block_navigation(buf))
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)
    end)

    describe("find_navigation_window", function()
        it("returns nil when only current window exists", function()
            -- Single window setup: find_navigation_window should return nil
            -- since the only window is the current one
            local result = util.find_navigation_window()
            assert.is_nil(result)
        end)

        it("finds a suitable window when a split exists", function()
            local path = helpers.create_temp_file({ "hello", "world" })
            helpers.open_file(path)
            local editor_win = vim.api.nvim_get_current_win()

            -- Create a split and switch to it (simulating being in an explorer)
            vim.cmd("vsplit")
            local new_win = vim.api.nvim_get_current_win()
            assert.is_not.equal(editor_win, new_win)

            -- From the new split, find_navigation_window should find the editor window
            local result = util.find_navigation_window()
            assert.is_not_nil(result)

            -- Clean up
            vim.api.nvim_set_current_win(new_win)
            vim.cmd("close")
        end)
    end)
end)
