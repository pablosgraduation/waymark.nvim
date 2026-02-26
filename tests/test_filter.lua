-- tests/test_filter.lua
local filter = require("waymark.filter")
local config = require("waymark.config")
local state = require("waymark.state")
local helpers = require("tests.helpers")

describe("waymark.filter", function()
    before_each(function()
        helpers.reset()
        config.setup({})
    end)

    describe("should_ignore_buffer", function()
        it("returns false for a normal file buffer", function()
            local path = helpers.create_temp_file({ "hello" })
            helpers.open_file(path)
            assert.is_false(filter.should_ignore_buffer())
        end)

        it("returns false for a buffer not in any ignore list", function()
            local path = helpers.create_temp_file({ "print('hello')" }, "test.py")
            helpers.open_file(path)
            assert.is_false(filter.should_ignore_buffer())
        end)

        it("returns true for buftype nofile", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = "nofile"
            assert.is_true(filter.should_ignore_buffer(buf))
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("returns true for buftype prompt", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = "prompt"
            assert.is_true(filter.should_ignore_buffer(buf))
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("returns true for ignored filetype", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = ""
            vim.bo[buf].filetype = "help"
            assert.is_true(filter.should_ignore_buffer(buf))
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("returns true for buffer matching ignored pattern", function()
            local path = helpers.create_temp_file({ "commit message" }, "COMMIT_EDITMSG")
            helpers.open_file(path)
            assert.is_true(filter.should_ignore_buffer())
        end)

        it("returns true for invalid buffer number", function()
            assert.is_true(filter.should_ignore_buffer(999999))
        end)

        it("returns true for popup buffer", function()
            local buf = vim.api.nvim_create_buf(false, true)
            state.popup_buf = buf
            assert.is_true(filter.should_ignore_buffer(buf))
            state.popup_buf = nil
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)

        it("caches result after first call", function()
            local path = helpers.create_temp_file({ "hello" })
            local bufnr = helpers.open_file(path)
            state.ignore_cache[bufnr] = nil
            assert.is_false(filter.should_ignore_buffer(bufnr))
            assert.equals(false, state.ignore_cache[bufnr])
        end)

        it("respects custom ignored_filetypes from config", function()
            config.setup({ ignored_filetypes = { "python" } })

            local buf1 = vim.api.nvim_create_buf(false, true)
            vim.bo[buf1].buftype = ""
            vim.bo[buf1].filetype = "python"
            assert.is_true(filter.should_ignore_buffer(buf1))

            local buf2 = vim.api.nvim_create_buf(false, true)
            vim.bo[buf2].buftype = ""
            vim.bo[buf2].filetype = "help"
            -- help is no longer in the custom list
            assert.is_false(filter.should_ignore_buffer(buf2))

            pcall(vim.api.nvim_buf_delete, buf1, { force = true })
            pcall(vim.api.nvim_buf_delete, buf2, { force = true })
        end)

        it("respects custom ignored_patterns from config", function()
            config.setup({ ignored_patterns = { "myproject_" } })

            local path1 = helpers.create_temp_file({ "x" }, "myproject_foo.lua")
            local bufnr1 = helpers.open_file(path1)
            assert.is_true(filter.should_ignore_buffer(bufnr1))

            local path2 = helpers.create_temp_file({ "y" }, "normal.lua")
            local bufnr2 = helpers.open_file(path2)
            assert.is_false(filter.should_ignore_buffer(bufnr2))
        end)
    end)
end)
