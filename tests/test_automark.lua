-- tests/test_automark.lua
local automark = require("waymark.automark")
local config = require("waymark.config")
local state = require("waymark.state")
local helpers = require("tests.helpers")

describe("waymark.automark", function()
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
            "line 16",
            "line 17",
            "line 18",
            "line 19",
            "line 20",
        })
    end)

    describe("should_track_position", function()
        it("tracks when switching files", function()
            state.last_position = { fname = "/tmp/a.lua", row = 1, time = 0 }
            assert.is_true(automark.should_track_position(1, "/tmp/b.lua", false))
        end)

        it("tracks when line distance exceeds threshold", function()
            state.last_position = { fname = test_file, row = 1, time = 0 }
            assert.is_true(automark.should_track_position(10, test_file, false))
        end)

        it("skips when line distance is below threshold", function()
            local uv = vim.uv or vim.loop
            state.last_position = { fname = test_file, row = 1, time = uv.now() }
            assert.is_false(automark.should_track_position(2, test_file, false))
        end)

        it("always tracks when forced (different position)", function()
            state.last_position = { fname = test_file, row = 1, time = 0 }
            assert.is_true(automark.should_track_position(2, test_file, true))
        end)

        it("skips exact same position even when forced", function()
            state.last_position = { fname = test_file, row = 5, time = 0 }
            assert.is_false(automark.should_track_position(5, test_file, true))
        end)
    end)

    describe("add", function()
        it("creates an automark", function()
            automark.add(1, 1, test_file, true)
            assert.equals(1, #state.automarks)
            assert.equals(test_file, state.automarks[1].fname)
            assert.equals(1, state.automarks[1].row)
        end)

        it("assigns unique IDs", function()
            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)
            assert.is_not.equals(state.automarks[1].id, state.automarks[2].id)
        end)

        it("resets automarks_idx to staging after add", function()
            state.automarks_idx = 3
            automark.add(1, 1, test_file, true)
            assert.equals(-1, state.automarks_idx)
        end)

        it("does not add during navigation", function()
            state.navigating = true
            automark.add(1, 1, test_file, true)
            assert.equals(0, #state.automarks)
            state.navigating = false
        end)

        it("skips empty filename", function()
            automark.add(1, 1, "", true)
            assert.equals(0, #state.automarks)
        end)

        it("removes near-duplicates within 2 lines", function()
            automark.add(10, 1, test_file, true)
            assert.equals(1, #state.automarks)
            -- Add another within 2 lines (should replace)
            automark.add(11, 1, test_file, true)
            assert.equals(1, #state.automarks)
            assert.equals(11, state.automarks[1].row)
        end)

        it("does not place automark on bookmark line", function()
            local bookmark = require("waymark.bookmark")
            helpers.open_file(test_file)
            helpers.set_cursor(5, 0)
            bookmark.add()

            -- Try to add automark at same line
            automark.add(5, 1, test_file, true)
            -- Should still have 0 automarks (bookmark takes priority)
            assert.equals(0, #state.automarks)
        end)
    end)

    describe("cleanup", function()
        it("preserves marks outside cleanup radius", function()
            config.setup({ automark_cleanup_lines = 5 })
            helpers.open_file(test_file)

            automark.add(1, 1, test_file, true)
            -- Make the first mark "old" by setting timestamp to 0
            state.automarks[1].timestamp = 0

            automark.add(20, 1, test_file, true)
            -- Line 1 and line 20 are 19 lines apart (> cleanup radius of 5)
            assert.equals(2, #state.automarks)
        end)
    end)

    describe("eviction", function()
        it("evicts oldest mark when over limit", function()
            config.setup({ automark_limit = 3 })

            -- Force marks at widely spaced lines to pass heuristics
            automark.add(1, 1, test_file, true)
            automark.add(5, 1, test_file, true)
            automark.add(10, 1, test_file, true)
            assert.equals(3, #state.automarks)

            -- Adding a 4th should evict the oldest (row=1)
            automark.add(15, 1, test_file, true)
            assert.equals(3, #state.automarks)
            assert.equals(5, state.automarks[1].row) -- oldest surviving
            assert.equals(15, state.automarks[3].row) -- newest
        end)

        it("resets automarks_idx to staging after eviction", function()
            config.setup({ automark_limit = 3 })
            helpers.open_file(test_file)

            automark.add(1, 1, test_file, true)
            automark.add(5, 1, test_file, true)
            automark.add(10, 1, test_file, true)

            -- Navigate to set a non-staging idx
            automark.prev()
            assert.is_true(state.automarks_idx ~= -1)

            -- Add a 4th triggers eviction; add() resets idx to -1 first
            automark.add(15, 1, test_file, true)
            assert.equals(-1, state.automarks_idx)
            assert.equals(3, #state.automarks)
        end)
    end)

    describe("navigation", function()
        it("prev cycles through automarks", function()
            helpers.open_file(test_file)

            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)
            automark.add(20, 1, test_file, true)

            -- prev from staging should go to newest (idx 3)
            automark.prev()
            assert.equals(3, state.automarks_idx)

            -- prev again should go to idx 2
            automark.prev()
            assert.equals(2, state.automarks_idx)
        end)

        it("next cycles through automarks", function()
            helpers.open_file(test_file)

            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)

            -- next from staging should go to oldest (idx 1)
            automark.next()
            assert.equals(1, state.automarks_idx)

            automark.next()
            assert.equals(2, state.automarks_idx)
        end)

        it("prev wraps from oldest to newest", function()
            helpers.open_file(test_file)

            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)

            automark.prev() -- idx 2 (newest)
            automark.prev() -- idx 1 (oldest)
            automark.prev() -- should wrap to idx 2
            assert.equals(2, state.automarks_idx)
        end)

        it("next wraps from newest to oldest", function()
            helpers.open_file(test_file)

            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)

            automark.next() -- idx 1 (oldest)
            automark.next() -- idx 2 (newest)
            automark.next() -- should wrap to idx 1
            assert.equals(1, state.automarks_idx)
        end)

        it("prev with count skips multiple", function()
            helpers.open_file(test_file)

            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)
            automark.add(20, 1, test_file, true)

            automark.prev(2) -- from staging: 3 then 2
            assert.equals(2, state.automarks_idx)
        end)

        it("does nothing with empty automark list", function()
            helpers.open_file(test_file)
            automark.prev()
            assert.equals(-1, state.automarks_idx)
            automark.next()
            assert.equals(-1, state.automarks_idx)
        end)
    end)

    describe("purge", function()
        it("removes automarks for deleted files", function()
            helpers.open_file(test_file)
            automark.add(1, 1, test_file, true)

            -- Add an automark for a nonexistent file
            local fake_dir = vim.fn.tempname()
            vim.fn.mkdir(fake_dir, "p")
            local fake_path = fake_dir .. "/deleted.lua"
            table.insert(state.automarks, {
                id = state.next_mark_id(),
                fname = fake_path,
                row = 1,
                col = 1,
                timestamp = 0,
            })
            assert.equals(2, #state.automarks)

            automark.purge()
            assert.equals(1, #state.automarks)
            assert.equals(test_file, state.automarks[1].fname)
        end)

        it("keeps all marks when all files exist", function()
            helpers.open_file(test_file)
            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)
            assert.equals(2, #state.automarks)

            automark.purge()
            assert.equals(2, #state.automarks)
        end)

        it("adjusts automarks_idx when purging before current", function()
            helpers.open_file(test_file)
            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)

            -- Insert a dead mark at position 1 by shifting things
            local fake_dir = vim.fn.tempname()
            vim.fn.mkdir(fake_dir, "p")
            table.insert(state.automarks, 1, {
                id = state.next_mark_id(),
                fname = fake_dir .. "/gone.lua",
                row = 1,
                col = 1,
                timestamp = 0,
            })
            -- Set idx to 3 (the second real mark, now shifted)
            state.automarks_idx = 3

            automark.purge()
            -- Dead mark at idx 1 removed; idx should shift from 3 to 2
            assert.equals(2, state.automarks_idx)
        end)
    end)

    describe("show", function()
        it("does not error with automarks", function()
            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)
            assert.has_no.errors(function()
                automark.show()
            end)
        end)

        it("does not error with no automarks", function()
            assert.has_no.errors(function()
                automark.show()
            end)
        end)
    end)

    describe("clear", function()
        it("removes all automarks", function()
            automark.add(1, 1, test_file, true)
            automark.add(10, 1, test_file, true)
            assert.equals(2, #state.automarks)

            automark.clear()
            assert.equals(0, #state.automarks)
            assert.equals(-1, state.automarks_idx)
        end)
    end)

    describe("get", function()
        it("returns a deep copy", function()
            automark.add(1, 1, test_file, true)
            local copy = automark.get()
            assert.equals(1, #copy)
            assert.is_not.equals(state.automarks, copy) -- different table
            assert.equals(state.automarks[1].fname, copy[1].fname) -- same content
        end)
    end)
end)
