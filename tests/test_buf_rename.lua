-- tests/test_buf_rename.lua
local bookmark = require("waymark.bookmark")
local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local filter = require("waymark.filter")
local helpers = require("tests.helpers")

describe("BufFilePost rename handling", function()
    before_each(function()
        helpers.reset()
        config.setup({})
        -- Set up the filter autocmds which include the BufFilePost handler
        filter.setup()
    end)

    it("updates automark filenames when buffer is renamed", function()
        local automark = require("waymark.automark")
        local file1 = helpers.create_temp_file({ "line 1", "line 2", "line 3" })
        local bufnr = helpers.open_file(file1)

        local norm_file1 = util.normalize_path(file1)
        automark.add(2, 0, norm_file1, true)
        assert.equals(1, #state.automarks)
        assert.equals(norm_file1, state.automarks[1].fname)

        -- Simulate :file new_name (buffer rename)
        local new_name = vim.fn.tempname() .. "/renamed_file.lua"
        vim.fn.mkdir(vim.fn.fnamemodify(new_name, ":h"), "p")
        vim.api.nvim_buf_set_name(bufnr, new_name)

        -- Fire the BufFilePost autocmd (Neovim fires this on buf_set_name)
        vim.api.nvim_exec_autocmds("BufFilePost", { buffer = bufnr })

        local norm_new = util.normalize_path(new_name)
        assert.equals(norm_new, state.automarks[1].fname)
    end)

    it("updates bookmark filenames when buffer is renamed", function()
        local file1 = helpers.create_temp_file({
            "line 1",
            "line 2",
            "line 3",
            "line 4",
            "line 5",
        })
        local bufnr = helpers.open_file(file1)

        helpers.set_cursor(3, 0)
        bookmark.add()
        local norm_file1 = util.normalize_path(file1)
        assert.equals(norm_file1, state.bookmarks[1].fname)

        -- Rename the buffer
        local new_name = vim.fn.tempname() .. "/renamed_bookmark_file.lua"
        vim.fn.mkdir(vim.fn.fnamemodify(new_name, ":h"), "p")
        vim.api.nvim_buf_set_name(bufnr, new_name)
        vim.api.nvim_exec_autocmds("BufFilePost", { buffer = bufnr })

        local norm_new = util.normalize_path(new_name)
        assert.equals(norm_new, state.bookmarks[1].fname)
    end)

    it("does nothing when buffer name hasn't actually changed", function()
        local file1 = helpers.create_temp_file({ "line 1", "line 2" })
        local bufnr = helpers.open_file(file1)
        local norm_file1 = util.normalize_path(file1)

        local automark = require("waymark.automark")
        automark.add(1, 0, norm_file1, true)

        -- Fire BufFilePost without actually changing the name
        vim.api.nvim_exec_autocmds("BufFilePost", { buffer = bufnr })

        assert.equals(norm_file1, state.automarks[1].fname)
    end)

    it("triggers bookmark save after rename", function()
        local file1 = helpers.create_temp_file({
            "line 1",
            "line 2",
            "line 3",
            "line 4",
            "line 5",
        })
        local bufnr = helpers.open_file(file1)

        helpers.set_cursor(3, 0)
        bookmark.add()
        bookmark.save(true) -- flush initial state

        -- Rename
        local new_name = vim.fn.tempname() .. "/saved_after_rename.lua"
        vim.fn.mkdir(vim.fn.fnamemodify(new_name, ":h"), "p")
        vim.api.nvim_buf_set_name(bufnr, new_name)
        vim.api.nvim_exec_autocmds("BufFilePost", { buffer = bufnr })

        -- Flush any pending async save
        bookmark.save(true)

        -- Reload from disk and verify the new filename persisted
        state.clear_list(state.bookmarks)
        bookmark.load()
        assert.equals(1, #state.bookmarks)
        assert.equals(util.normalize_path(new_name), state.bookmarks[1].fname)
    end)
end)
