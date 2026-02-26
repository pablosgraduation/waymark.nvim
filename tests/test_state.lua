-- tests/test_state.lua
local state = require("waymark.state")

describe("waymark.state", function()
    before_each(function()
        state.mark_id_counter = 0
    end)

    describe("next_mark_id", function()
        it("returns monotonically increasing IDs", function()
            local id1 = state.next_mark_id()
            local id2 = state.next_mark_id()
            local id3 = state.next_mark_id()
            assert.equals(1, id1)
            assert.equals(2, id2)
            assert.equals(3, id3)
        end)
    end)

    describe("sync_mark_id_counter", function()
        it("syncs counter above existing bookmark IDs", function()
            state.mark_id_counter = 0
            state.bookmarks = { { id = 42 }, { id = 7 } }
            state.automarks = {}
            state.sync_mark_id_counter()
            assert.equals(42, state.mark_id_counter)
            -- Next ID should be 43
            assert.equals(43, state.next_mark_id())
        end)

        it("syncs counter above existing automark IDs", function()
            state.mark_id_counter = 0
            state.bookmarks = {}
            state.automarks = { { id = 100 } }
            state.sync_mark_id_counter()
            assert.equals(100, state.mark_id_counter)
        end)
    end)

    describe("adjust_index_after_removal", function()
        it("resets to -1 when the current element is removed", function()
            assert.equals(-1, state.adjust_index_after_removal(3, 3, 5))
        end)

        it("decrements when a lower element is removed", function()
            assert.equals(4, state.adjust_index_after_removal(5, 2, 6))
        end)

        it("stays the same when a higher element is removed", function()
            assert.equals(2, state.adjust_index_after_removal(2, 5, 6))
        end)

        it("resets to -1 when index exceeds new list length", function()
            assert.equals(-1, state.adjust_index_after_removal(5, 3, 3))
        end)

        it("handles staging index (-1) unchanged", function()
            assert.equals(-1, state.adjust_index_after_removal(-1, 3, 5))
        end)
    end)

    describe("clear_list", function()
        it("empties a table while preserving identity", function()
            local t = { 1, 2, 3, 4, 5 }
            local ref = t
            state.clear_list(t)
            assert.equals(0, #t)
            assert.equals(ref, t) -- same table reference
        end)
    end)

    describe("navigation helpers", function()
        it("begin_navigation sets navigating flag", function()
            state.navigating = false
            state.begin_navigation()
            assert.is_true(state.navigating)
        end)

        it("end_navigation clears navigating flag", function()
            state.navigating = true
            state.end_navigation()
            assert.is_false(state.navigating)
        end)

        it("begin_navigation increments generation", function()
            local gen = state.nav_generation
            state.begin_navigation()
            assert.equals(gen + 1, state.nav_generation)
        end)
    end)

    describe("warn_if_no_setup", function()
        it("does not warn when setup_done is true", function()
            state.setup_done = true
            state.setup_warned = false
            state.warn_if_no_setup()
            assert.is_false(state.setup_warned)
        end)

        it("warns once when setup_done is false", function()
            state.setup_done = false
            state.setup_warned = false
            state.warn_if_no_setup()
            assert.is_true(state.setup_warned)
        end)

        it("only warns once", function()
            state.setup_done = false
            state.setup_warned = false
            state.warn_if_no_setup()
            assert.is_true(state.setup_warned)
            -- Second call should not crash or change anything
            state.warn_if_no_setup()
            assert.is_true(state.setup_warned)
        end)
    end)

    describe("close_timer", function()
        it("does not error on a fresh timer", function()
            local uv = vim.uv or vim.loop
            local timer = uv.new_timer()
            assert.has_no.errors(function()
                state.close_timer(timer)
            end)
        end)

        it("does not error when called twice", function()
            local uv = vim.uv or vim.loop
            local timer = uv.new_timer()
            state.close_timer(timer)
            assert.has_no.errors(function()
                state.close_timer(timer)
            end)
        end)
    end)

    describe("begin_navigation_with_fallback", function()
        it("sets navigating to true", function()
            state.navigating = false
            state.begin_navigation_with_fallback()
            assert.is_true(state.navigating)
        end)

        it("increments generation", function()
            local gen = state.nav_generation
            state.begin_navigation_with_fallback()
            assert.equals(gen + 1, state.nav_generation)
        end)
    end)
end)
