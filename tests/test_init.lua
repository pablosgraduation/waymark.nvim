-- tests/test_init.lua
local waymark = require("waymark")
local state = require("waymark.state")
local config = require("waymark.config")
local helpers = require("tests.helpers")

describe("waymark.init", function()
    before_each(function()
        helpers.reset()
        config.setup({})
    end)

    describe("setup", function()
        it("does not error with no args", function()
            assert.has_no.errors(function()
                waymark.setup()
            end)
        end)

        it("does not error with empty table", function()
            assert.has_no.errors(function()
                waymark.setup({})
            end)
        end)

        it("sets setup_done to true", function()
            state.setup_done = false
            waymark.setup()
            assert.is_true(state.setup_done)
        end)

        it("is safe to call twice", function()
            assert.has_no.errors(function()
                waymark.setup()
                waymark.setup()
            end)
        end)

        it("flushes ignore cache", function()
            state.ignore_cache[42] = true
            waymark.setup()
            assert.is_nil(state.ignore_cache[42])
        end)
    end)

    describe("public API", function()
        it("all API functions exist and are functions", function()
            local api = {
                "add_bookmark",
                "delete_bookmark",
                "toggle_bookmark",
                "show_bookmarks",
                "clear_bookmarks",
                "get_bookmarks",
                "prev_bookmark",
                "next_bookmark",
                "goto_bookmark",
                "prev_automark",
                "next_automark",
                "show_automarks",
                "purge_automarks",
                "clear_automarks",
                "get_automarks",
                "prev_allmark",
                "next_allmark",
                "setup",
            }
            for _, name in ipairs(api) do
                assert.equals("function", type(waymark[name]), name .. " should be a function")
            end
        end)

        it("get_bookmarks returns a deep copy", function()
            waymark.setup()
            local test_file = helpers.create_temp_file({ "line 1", "line 2", "line 3" })
            helpers.open_file(test_file)
            helpers.set_cursor(3, 0)
            waymark.add_bookmark()
            local copy = waymark.get_bookmarks()
            copy[1].row = 999
            assert.is_not.equals(999, state.bookmarks[1].row)
        end)

        it("get_automarks returns a deep copy", function()
            waymark.setup()
            local test_file = helpers.create_temp_file({ "line 1", "line 2", "line 3", "line 4", "line 5" })
            helpers.open_file(test_file)
            local util = require("waymark.util")
            local automark = require("waymark.automark")
            automark.add(5, 1, util.normalize_path(test_file), true)
            local copy = waymark.get_automarks()
            copy[1].row = 999
            assert.is_not.equals(999, state.automarks[1].row)
        end)
    end)
end)
