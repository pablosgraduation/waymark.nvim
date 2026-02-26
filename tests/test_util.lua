-- tests/test_util.lua
local util = require("waymark.util")
local helpers = require("tests.helpers")

describe("waymark.util", function()
    describe("normalize_path", function()
        it("returns empty string for nil input", function()
            assert.equals("", util.normalize_path(nil))
        end)

        it("returns empty string for empty input", function()
            assert.equals("", util.normalize_path(""))
        end)

        it("returns absolute path for relative input", function()
            local result = util.normalize_path("foo.lua")
            assert.is_true(result:sub(1, 1) == "/")
        end)

        it("caches results (second call returns same value)", function()
            local path = "/tmp/waymark_test_normalize.lua"
            local r1 = util.normalize_path(path)
            local r2 = util.normalize_path(path)
            assert.equals(r1, r2)
        end)
    end)

    describe("mark_key", function()
        it("creates a unique key from fname and row", function()
            local key = util.mark_key("/tmp/foo.lua", 42)
            assert.is_string(key)
            assert.is_true(key:find("42") ~= nil)
        end)

        it("produces different keys for different rows", function()
            local k1 = util.mark_key("/tmp/foo.lua", 1)
            local k2 = util.mark_key("/tmp/foo.lua", 2)
            assert.is_not.equals(k1, k2)
        end)

        it("produces different keys for different files", function()
            local k1 = util.mark_key("/tmp/a.lua", 1)
            local k2 = util.mark_key("/tmp/b.lua", 1)
            assert.is_not.equals(k1, k2)
        end)
    end)

    describe("find_mark_index_by_id", function()
        it("finds the correct index", function()
            local list = { { id = 10 }, { id = 20 }, { id = 30 } }
            assert.equals(2, util.find_mark_index_by_id(list, 20))
        end)

        it("returns nil for missing ID", function()
            local list = { { id = 10 }, { id = 20 } }
            assert.is_nil(util.find_mark_index_by_id(list, 99))
        end)

        it("returns nil for empty list", function()
            assert.is_nil(util.find_mark_index_by_id({}, 1))
        end)
    end)

    describe("format_path", function()
        it("returns a string", function()
            assert.is_string(util.format_path("/tmp/foo.lua"))
        end)
    end)

    describe("get_line_preview", function()
        it("reads a line from an existing file", function()
            local path = helpers.create_temp_file({ "first line", "second line", "third line" })
            local preview = util.get_line_preview(path, 2, 50)
            assert.equals("second line", preview)
        end)

        it("truncates long lines", function()
            local long = string.rep("x", 100)
            local path = helpers.create_temp_file({ long })
            local preview = util.get_line_preview(path, 1, 10)
            -- Should be 10 chars + ellipsis
            assert.is_true(#preview <= 15)
            assert.is_true(preview:find("…") ~= nil)
        end)

        it("returns nil for non-existent file", function()
            assert.is_nil(util.get_line_preview("/nonexistent/file.lua", 1))
        end)

        it("returns nil for out-of-range row", function()
            local path = helpers.create_temp_file({ "only line" })
            assert.is_nil(util.get_line_preview(path, 999))
        end)

        it("trims whitespace", function()
            local path = helpers.create_temp_file({ "    indented    " })
            local preview = util.get_line_preview(path, 1, 50)
            assert.equals("indented", preview)
        end)
    end)

    describe("ensure_parent_dir", function()
        it("creates parent directory if missing", function()
            local dir = vim.fn.tempname() .. "/deep/nested"
            local path = dir .. "/file.txt"
            util.ensure_parent_dir(path)
            assert.equals(1, vim.fn.isdirectory(dir))
        end)
    end)

    describe("get_cursor_position", function()
        before_each(function()
            helpers.reset()
            local config = require("waymark.config")
            config.setup({})
        end)

        it("returns position for a normal file buffer", function()
            local path = helpers.create_temp_file({ "line 1", "line 2", "line 3" })
            helpers.open_file(path)
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            local pos = util.get_cursor_position()
            assert.is_not_nil(pos)
            assert.equals(2, pos.row)
            assert.is_string(pos.fname)
            assert.is_true(pos.fname ~= "")
        end)

        it("returns nil for a scratch buffer", function()
            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_set_current_buf(buf)

            local pos = util.get_cursor_position()
            -- scratch buf has buftype nofile, so filter ignores it
            assert.is_nil(pos)
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end)
    end)

    describe("invalidate_path_cache", function()
        it("clears cached entry for a path", function()
            local path = "/tmp/test_invalidate.lua"
            -- Populate cache
            util.normalize_path(path)
            -- Invalidate
            util.invalidate_path_cache(path)
            -- Next call should re-resolve (verify it doesn't error)
            local result = util.normalize_path(path)
            assert.is_string(result)
        end)

        it("does not error for path not in cache", function()
            assert.has_no.errors(function()
                util.invalidate_path_cache("/never/cached/path.lua")
            end)
        end)
    end)
end)
