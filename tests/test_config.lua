-- tests/test_config.lua
local config = require("waymark.config")

describe("waymark.config", function()
    before_each(function()
        -- Reset to defaults before each test
        config.current = vim.deepcopy(config.defaults)
        config.current._ignored_ft_set = {}
        for _, ft in ipairs(config.current.ignored_filetypes) do
            config.current._ignored_ft_set[ft] = true
        end
    end)

    describe("defaults", function()
        it("has sane default values", function()
            assert.equals(15, config.defaults.automark_limit)
            assert.equals(3000, config.defaults.automark_idle_ms)
            assert.equals(5, config.defaults.automark_min_lines)
            assert.equals(200, config.defaults.jump_flash_ms)
            assert.equals("¤", config.defaults.automark_sign)
            assert.equals("※", config.defaults.bookmark_sign)
        end)

        it("has mappings table with expected keys", function()
            assert.is_table(config.defaults.mappings)
            assert.equals("<leader>bb", config.defaults.mappings.add_bookmark)
            assert.equals("[a", config.defaults.mappings.prev_automark)
            assert.equals(false, config.defaults.mappings.next_allmark)
        end)
    end)

    describe("setup", function()
        it("merges user options over defaults", function()
            config.setup({ automark_limit = 30 })
            assert.equals(30, config.current.automark_limit)
            -- Other values should remain default
            assert.equals(3000, config.current.automark_idle_ms)
        end)

        it("respects mappings = false", function()
            config.setup({ mappings = false })
            assert.equals(false, config.current.mappings)
        end)

        it("merges partial mappings", function()
            config.setup({ mappings = { add_bookmark = "<leader>m" } })
            assert.equals("<leader>m", config.current.mappings.add_bookmark)
            -- Other mappings should remain default
            assert.equals("[a", config.current.mappings.prev_automark)
        end)

        it("validates automark_limit is positive integer", function()
            config.setup({ automark_limit = -5 })
            assert.equals(config.defaults.automark_limit, config.current.automark_limit)
        end)

        it("validates automark_idle_ms minimum of 100", function()
            config.setup({ automark_idle_ms = 50 })
            assert.equals(100, config.current.automark_idle_ms)
        end)

        it("validates string options", function()
            config.setup({ automark_sign = 123 })
            assert.equals(config.defaults.automark_sign, config.current.automark_sign)
        end)

        it("validates table options", function()
            config.setup({ ignored_filetypes = "not a table" })
            assert.same(config.defaults.ignored_filetypes, config.current.ignored_filetypes)
        end)

        it("builds _ignored_ft_set from ignored_filetypes", function()
            config.setup({ ignored_filetypes = { "foo", "bar" } })
            assert.is_true(config.current._ignored_ft_set["foo"])
            assert.is_true(config.current._ignored_ft_set["bar"])
            assert.is_nil(config.current._ignored_ft_set["neo-tree"])
        end)

        it("handles empty opts gracefully", function()
            config.setup({})
            assert.equals(config.defaults.automark_limit, config.current.automark_limit)
        end)

        it("handles nil opts gracefully", function()
            config.setup(nil)
            assert.equals(config.defaults.automark_limit, config.current.automark_limit)
        end)

        it("validates non-negative number options", function()
            config.setup({ automark_min_lines = -1 })
            assert.equals(config.defaults.automark_min_lines, config.current.automark_min_lines)
        end)

        it("validates automark_cleanup_lines", function()
            config.setup({ automark_cleanup_lines = "not a number" })
            assert.equals(config.defaults.automark_cleanup_lines, config.current.automark_cleanup_lines)
        end)

        it("validates table options reject non-tables", function()
            config.setup({ ignored_patterns = 42 })
            assert.same(config.defaults.ignored_patterns, config.current.ignored_patterns)
        end)

        it("validates hex color strings", function()
            config.setup({ automark_sign_color = 12345 })
            assert.equals(config.defaults.automark_sign_color, config.current.automark_sign_color)
        end)
    end)
end)
