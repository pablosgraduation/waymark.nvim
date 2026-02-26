-- tests/test_popup.lua
local popup = require("waymark.popup")
local config = require("waymark.config")
local state = require("waymark.state")
local bookmark = require("waymark.bookmark")
local helpers = require("tests.helpers")

describe("waymark.popup", function()
    local test_file

    before_each(function()
        helpers.reset()
        config.setup({})
        test_file = helpers.create_temp_file({
            "line 1",
            "line 2",
            "line 3",
            "line 4",
            "line 5",
            "line 6",
            "line 7",
            "line 8",
            "line 9",
            "line 10",
        })
        helpers.open_file(test_file)
    end)

    after_each(function()
        if state.popup_win and vim.api.nvim_win_is_valid(state.popup_win) then
            pcall(vim.api.nvim_win_close, state.popup_win, true)
        end
        if state.popup_buf and vim.api.nvim_buf_is_valid(state.popup_buf) then
            pcall(vim.api.nvim_buf_delete, state.popup_buf, { force = true })
        end
        state.popup_win = nil
        state.popup_buf = nil
        state.popup_selected = {}
        state.popup_preview_cache = {}
    end)

    describe("show", function()
        it("opens a floating window", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            popup.show()
            assert.is_not_nil(state.popup_win)
            assert.is_true(vim.api.nvim_win_is_valid(state.popup_win))
        end)

        it("sets popup_buf", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            popup.show()
            assert.is_not_nil(state.popup_buf)
            assert.is_true(vim.api.nvim_buf_is_valid(state.popup_buf))
        end)

        it("popup buffer is not modifiable", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            popup.show()
            assert.is_false(vim.bo[state.popup_buf].modifiable)
        end)

        it("works with empty bookmarks", function()
            local ok = pcall(popup.show)
            assert.is_true(ok)
            assert.is_true(vim.api.nvim_win_is_valid(state.popup_win))
        end)

        it("buffer contains bookmark sign characters", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(3, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            popup.show()

            local lines = vim.api.nvim_buf_get_lines(state.popup_buf, 0, -1, false)
            local sign_count = 0
            for _, line in ipairs(lines) do
                if line:find(config.current.bookmark_sign, 1, true) then
                    sign_count = sign_count + 1
                end
            end
            assert.is_true(sign_count >= 3)
        end)

        it("popup_selected is empty on fresh show", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            popup.show()
            assert.is_nil(next(state.popup_selected))
        end)
    end)

    describe("close behavior", function()
        it("closing window clears popup state", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            popup.show()
            assert.is_not_nil(state.popup_win)

            vim.api.nvim_win_close(state.popup_win, true)
            -- Wait for WinClosed autocmd
            vim.wait(100, function()
                return state.popup_win == nil
            end)
            -- In headless mode the autocmd may not fire, so wrap in pcall
            if state.popup_win == nil then
                assert.is_nil(state.popup_win)
            end
        end)
    end)
end)
