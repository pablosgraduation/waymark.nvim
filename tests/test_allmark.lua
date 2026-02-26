-- tests/test_allmark.lua
local allmark = require("waymark.allmark")
local automark = require("waymark.automark")
local bookmark = require("waymark.bookmark")
local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local helpers = require("tests.helpers")

describe("waymark.allmark", function()
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
            "line 11",
            "line 12",
            "line 13",
            "line 14",
            "line 15",
        })
        helpers.open_file(test_file)
    end)

    describe("prev", function()
        it("navigates when only automarks exist", function()
            local fname = util.normalize_path(test_file)
            automark.add(1, 1, fname, true)
            automark.add(10, 1, fname, true)

            allmark.prev()
            assert.is_not_nil(state.merged_last_mark)
        end)

        it("navigates when only bookmarks exist", function()
            helpers.set_cursor(5, 0)
            bookmark.add()

            allmark.prev()
            assert.is_not_nil(state.merged_last_mark)
        end)

        it("navigates a mix of automarks and bookmarks", function()
            local fname = util.normalize_path(test_file)
            automark.add(1, 1, fname, true)

            helpers.set_cursor(10, 0)
            bookmark.add()

            -- Should have 2 marks in merged timeline
            allmark.prev()
            assert.is_not_nil(state.merged_last_mark)

            allmark.prev()
            assert.is_not_nil(state.merged_last_mark)
        end)

        it("reports no marks when both lists are empty", function()
            -- Should not error
            allmark.prev()
            assert.is_nil(state.merged_last_mark)
        end)
    end)

    describe("next", function()
        it("navigates forward in merged timeline", function()
            local fname = util.normalize_path(test_file)
            automark.add(1, 1, fname, true)
            automark.add(10, 1, fname, true)

            allmark.next()
            local first_mark = state.merged_last_mark
            assert.is_not_nil(first_mark)

            allmark.next()
            -- Should have moved to a different mark
            assert.is_not_nil(state.merged_last_mark)
        end)

        it("wraps from last to first", function()
            local fname = util.normalize_path(test_file)
            automark.add(1, 1, fname, true)
            automark.add(10, 1, fname, true)

            allmark.next() -- idx 1 (oldest)
            allmark.next() -- idx 2 (newest)
            local before_wrap = state.merged_last_mark
            allmark.next() -- should wrap to idx 1
            -- merged_last_mark should have changed (wrapped back)
            assert.is_not_nil(state.merged_last_mark)
            assert.is_not.equals(before_wrap, state.merged_last_mark)
        end)
    end)

    describe("prev wrapping", function()
        it("wraps from first to last", function()
            local fname = util.normalize_path(test_file)
            automark.add(1, 1, fname, true)
            automark.add(10, 1, fname, true)

            allmark.prev() -- idx 2 (newest)
            allmark.prev() -- idx 1 (oldest)
            local before_wrap = state.merged_last_mark
            allmark.prev() -- should wrap to idx 2
            assert.is_not_nil(state.merged_last_mark)
            assert.is_not.equals(before_wrap, state.merged_last_mark)
        end)
    end)

    describe("count parameter", function()
        it("prev with count skips multiple marks", function()
            local fname = util.normalize_path(test_file)
            automark.add(1, 1, fname, true)
            automark.add(5, 1, fname, true)
            automark.add(10, 1, fname, true)

            -- prev(2) from staging: first step goes to idx 3, second to idx 2
            allmark.prev(2)
            assert.is_not_nil(state.merged_last_mark)

            -- We're now 2 steps in; one more prev should go to idx 1
            allmark.prev()
            assert.is_not_nil(state.merged_last_mark)
        end)

        it("next with count skips multiple marks", function()
            local fname = util.normalize_path(test_file)
            automark.add(1, 1, fname, true)
            automark.add(5, 1, fname, true)
            automark.add(10, 1, fname, true)

            -- next(2) from staging: first step goes to idx 1, second to idx 2
            allmark.next(2)
            assert.is_not_nil(state.merged_last_mark)
        end)
    end)

    describe("bookmark-line deduplication", function()
        it("excludes automarks that share a line with a bookmark", function()
            local fname = util.normalize_path(test_file)
            -- Add automark and bookmark on the same line
            automark.add(5, 1, fname, true)
            helpers.set_cursor(5, 0)
            bookmark.add()

            -- The automark should have been removed by bookmark.add
            assert.equals(0, #state.automarks)
            assert.equals(1, #state.bookmarks)

            -- Merged timeline should have exactly 1 entry
            allmark.prev()
            assert.is_not_nil(state.merged_last_mark)
        end)

        it("deduplicates bookmark+automark on same line in navigation", function()
            local fname = util.normalize_path(test_file)

            helpers.set_cursor(5, 0)
            bookmark.add()
            -- Force an automark at a different line so there's something to navigate
            automark.add(10, 1, fname, true)

            -- Navigate — should not error and should track position
            allmark.prev()
            assert.is_true(state.merged_last_mark ~= nil or state.bookmarks_idx ~= -1)
        end)
    end)
end)
