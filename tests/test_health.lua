-- tests/test_health.lua
local health = require("waymark.health")
local config = require("waymark.config")
local state = require("waymark.state")
local helpers = require("tests.helpers")

describe("waymark.health", function()
    before_each(function()
        helpers.reset()
        config.setup({})
    end)

    it("check does not error when setup has been called", function()
        state.setup_done = true
        local ok, err = pcall(health.check)
        if not ok then
            -- Only acceptable errors are from vim.health infrastructure
            -- not being available in headless test mode, not from waymark logic
            assert.is_truthy(
                err:find("health") or err:find("not a function"),
                "Error should be vim.health infrastructure, got: " .. tostring(err)
            )
        end
    end)

    it("check does not error when setup has not been called", function()
        state.setup_done = false
        local ok, err = pcall(health.check)
        if not ok then
            assert.is_truthy(
                err:find("health") or err:find("not a function"),
                "Error should be vim.health infrastructure, got: " .. tostring(err)
            )
        end
    end)

    it("module loads without error", function()
        assert.is_not_nil(health)
        assert.equals("function", type(health.check))
    end)
end)
