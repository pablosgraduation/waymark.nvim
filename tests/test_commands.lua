-- tests/test_commands.lua
local commands = require("waymark.commands")
local config = require("waymark.config")
local state = require("waymark.state")
local helpers = require("tests.helpers")

describe("waymark.commands", function()
    before_each(function()
        helpers.reset()
        config.setup({})
    end)

    describe("register_commands", function()
        it("registers all expected user commands", function()
            commands.register_commands()
            local expected = {
                "WaymarkAddBookmark",
                "WaymarkDeleteBookmark",
                "WaymarkToggleBookmark",
                "WaymarkShowBookmarks",
                "WaymarkPrevBookmark",
                "WaymarkNextBookmark",
                "WaymarkJumpBookmark",
                "WaymarkClearBookmarks",
                "WaymarkPrevAutomark",
                "WaymarkNextAutomark",
                "WaymarkShowAutomarks",
                "WaymarkPurgeAutomarks",
                "WaymarkClearAutomarks",
                "WaymarkPrevAllmark",
                "WaymarkNextAllmark",
                "WaymarkDebug",
            }
            for _, name in ipairs(expected) do
                assert.equals(2, vim.fn.exists(":" .. name), name .. " should be registered")
            end
        end)

        it("is idempotent", function()
            commands.register_commands()
            commands.register_commands()
            local ok = pcall(vim.cmd, "WaymarkDebug")
            assert.is_true(ok)
        end)
    end)

    describe("register_keymaps", function()
        it("registers default keymaps", function()
            commands.register_commands()
            commands.register_keymaps()

            -- Count non-false entries in config.defaults.mappings
            -- next_allmark is false, so 20 active keymaps
            assert.equals(20, #state.active_keymaps)
        end)

        it("registers no keymaps when mappings is false", function()
            config.setup({ mappings = false })
            commands.register_keymaps()
            assert.equals(0, #state.active_keymaps)
        end)

        it("skips individual mapping set to false", function()
            config.setup({ mappings = { next_allmark = false } })
            commands.register_commands()
            commands.register_keymaps()

            local function has_keymap(key)
                for _, k in ipairs(state.active_keymaps) do
                    if k == key then
                        return true
                    end
                end
                return false
            end

            assert.is_true(has_keymap(config.current.mappings.add_bookmark))
            -- next_allmark is false, should not be in active_keymaps
            assert.is_false(has_keymap(false))
        end)

        it("cleans up old keymaps on re-register", function()
            commands.register_commands()
            commands.register_keymaps()
            local count1 = #state.active_keymaps

            commands.register_keymaps()
            assert.equals(count1, #state.active_keymaps)
        end)

        it("cleans up all keymaps when switching to false", function()
            commands.register_commands()
            commands.register_keymaps()
            assert.is_true(#state.active_keymaps > 0)

            config.setup({ mappings = false })
            commands.register_keymaps()
            assert.equals(0, #state.active_keymaps)
        end)
    end)

    describe("WaymarkDebug", function()
        it("runs without error with marks", function()
            commands.register_commands()
            local test_file = helpers.create_temp_file({ "line 1", "line 2", "line 3", "line 4", "line 5" })
            helpers.open_file(test_file)

            local bookmark = require("waymark.bookmark")
            local automark = require("waymark.automark")
            local util = require("waymark.util")
            helpers.set_cursor(3, 0)
            bookmark.add()
            automark.add(1, 1, util.normalize_path(test_file), true)

            local ok = pcall(vim.cmd, "WaymarkDebug")
            assert.is_true(ok)
        end)

        it("runs without error with no marks", function()
            commands.register_commands()
            local ok = pcall(vim.cmd, "WaymarkDebug")
            assert.is_true(ok)
        end)
    end)
end)
