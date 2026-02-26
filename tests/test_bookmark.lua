-- tests/test_bookmark.lua
local bookmark = require("waymark.bookmark")
local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local helpers = require("tests.helpers")

describe("waymark.bookmark", function()
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
        })
        helpers.open_file(test_file)
    end)

    describe("add", function()
        it("creates a bookmark at cursor position", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            assert.equals(1, #state.bookmarks)
            assert.equals(3, state.bookmarks[1].row)
        end)

        it("inserts at index 1 (newest-first)", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            helpers.set_cursor(7, 0)
            bookmark.add()
            assert.equals(2, #state.bookmarks)
            assert.equals(7, state.bookmarks[1].row) -- newest
            assert.equals(3, state.bookmarks[2].row) -- older
        end)

        it("prevents duplicate on same line", function()
            helpers.set_cursor(5, 0)
            bookmark.add()
            bookmark.add() -- same line
            assert.equals(1, #state.bookmarks)
        end)

        it("assigns unique IDs", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            assert.is_not.equals(state.bookmarks[1].id, state.bookmarks[2].id)
        end)

        it("resets bookmarks_idx to staging", function()
            state.bookmarks_idx = 1
            helpers.set_cursor(3, 0)
            bookmark.add()
            assert.equals(-1, state.bookmarks_idx)
        end)

        it("removes automark on same line when adding bookmark", function()
            local automark = require("waymark.automark")
            automark.add(5, 1, util.normalize_path(test_file), true)
            assert.equals(1, #state.automarks)

            helpers.set_cursor(5, 0)
            bookmark.add()
            assert.equals(0, #state.automarks)
            assert.equals(1, #state.bookmarks)
        end)
    end)

    describe("delete_at_cursor", function()
        it("removes bookmark at cursor position", function()
            helpers.set_cursor(5, 0)
            bookmark.add()
            assert.equals(1, #state.bookmarks)

            helpers.set_cursor(5, 0)
            bookmark.delete_at_cursor()
            assert.equals(0, #state.bookmarks)
        end)

        it("does nothing when no bookmark at cursor", function()
            helpers.set_cursor(5, 0)
            bookmark.add()
            helpers.set_cursor(3, 0)
            bookmark.delete_at_cursor()
            assert.equals(1, #state.bookmarks) -- unchanged
        end)

        it("adjusts bookmarks_idx when deleting before current", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            helpers.set_cursor(9, 0)
            bookmark.add()
            -- order: [9, 5, 1]

            -- Navigate to idx 3 (row 1)
            bookmark.prev()
            bookmark.prev()
            bookmark.prev()
            assert.equals(3, state.bookmarks_idx)

            -- Delete bookmark at row 9 (idx 1), which is before current idx 3
            helpers.set_cursor(9, 0)
            bookmark.delete_at_cursor()
            -- idx should shift from 3 to 2
            assert.equals(2, state.bookmarks_idx)
        end)

        it("resets bookmarks_idx when deleting current", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            -- order: [5, 1]

            bookmark.prev() -- idx 1 (row 5)
            assert.equals(1, state.bookmarks_idx)

            helpers.set_cursor(5, 0)
            bookmark.delete_at_cursor()
            assert.equals(-1, state.bookmarks_idx)
        end)
    end)

    describe("navigation", function()
        it("prev walks toward older bookmarks", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            helpers.set_cursor(9, 0)
            bookmark.add()
            -- bookmarks order: [9, 5, 1] (newest-first)

            -- prev from staging -> idx 1 (newest, row 9)
            bookmark.prev()
            assert.equals(1, state.bookmarks_idx)

            -- prev again -> idx 2 (row 5)
            bookmark.prev()
            assert.equals(2, state.bookmarks_idx)
        end)

        it("next walks toward newer bookmarks", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            -- bookmarks order: [5, 1]

            -- next from staging -> idx 2 (oldest, row 1)
            bookmark.next()
            assert.equals(2, state.bookmarks_idx)

            -- next again -> idx 1 (newest, row 5)
            bookmark.next()
            assert.equals(1, state.bookmarks_idx)
        end)

        it("prev wraps from oldest to newest", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            -- order: [5, 1]

            bookmark.prev() -- idx 1
            bookmark.prev() -- idx 2
            bookmark.prev() -- should wrap to idx 1
            assert.equals(1, state.bookmarks_idx)
        end)

        it("next wraps from newest to oldest", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            -- order: [5, 1]

            bookmark.next() -- idx 2 (oldest)
            bookmark.next() -- idx 1 (newest)
            bookmark.next() -- should wrap to idx 2
            assert.equals(2, state.bookmarks_idx)
        end)

        it("prev with count skips multiple", function()
            helpers.set_cursor(1, 0)
            bookmark.add()
            helpers.set_cursor(3, 0)
            bookmark.add()
            helpers.set_cursor(5, 0)
            bookmark.add()
            -- order: [5, 3, 1]

            bookmark.prev(2) -- from staging, should advance 2 steps
            assert.equals(2, state.bookmarks_idx)
        end)

        it("does nothing with empty bookmark list", function()
            bookmark.prev()
            assert.equals(-1, state.bookmarks_idx)
            bookmark.next()
            assert.equals(-1, state.bookmarks_idx)
        end)
    end)

    describe("jump_to_index", function()
        it("jumps to the correct bookmark", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            helpers.set_cursor(8, 0)
            bookmark.add()

            helpers.set_cursor(1, 0) -- move away
            bookmark.jump_to_index(2) -- jump to older bookmark (row 3)

            local cursor = vim.api.nvim_win_get_cursor(0)
            assert.equals(3, cursor[1])
        end)

        it("rejects invalid index", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            -- Should not crash on out-of-range index
            bookmark.jump_to_index(99)
            bookmark.jump_to_index(0)
        end)
    end)

    describe("toggle", function()
        it("adds bookmark when none exists on line", function()
            helpers.set_cursor(5, 0)
            bookmark.toggle()
            assert.equals(1, #state.bookmarks)
        end)

        it("removes bookmark when one exists on line", function()
            helpers.set_cursor(5, 0)
            bookmark.add()
            assert.equals(1, #state.bookmarks)

            helpers.set_cursor(5, 0)
            bookmark.toggle()
            assert.equals(0, #state.bookmarks)
        end)

        it("removes automarks on the same line too", function()
            local automark = require("waymark.automark")
            local fname = util.normalize_path(test_file)
            automark.add(5, 1, fname, true)
            assert.equals(1, #state.automarks)

            helpers.set_cursor(5, 0)
            bookmark.toggle()
            assert.equals(0, #state.automarks)
        end)

        it("is a true round-trip: toggle on then off restores empty state", function()
            assert.equals(0, #state.bookmarks)
            helpers.set_cursor(5, 0)
            bookmark.toggle()
            assert.equals(1, #state.bookmarks)
            helpers.set_cursor(5, 0)
            bookmark.toggle()
            assert.equals(0, #state.bookmarks)
        end)
    end)

    describe("cross-file navigation", function()
        it("jumps to a bookmark in a different file", function()
            local other_file = helpers.create_temp_file({
                "other 1",
                "other 2",
                "other 3",
                "other 4",
                "other 5",
            })
            helpers.open_file(other_file)
            helpers.set_cursor(3, 0)
            bookmark.add()

            -- Switch back to original file
            helpers.open_file(test_file)
            helpers.set_cursor(1, 0)

            -- Jump to the bookmark in the other file
            bookmark.jump_to_index(1)
            local cursor = vim.api.nvim_win_get_cursor(0)
            assert.equals(3, cursor[1])
            local current_name = util.normalize_path(vim.api.nvim_buf_get_name(0))
            assert.equals(util.normalize_path(other_file), current_name)
        end)
    end)

    describe("persistence", function()
        it("save and load roundtrips correctly", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            helpers.set_cursor(7, 0)
            bookmark.add()

            local saved_count = #state.bookmarks
            local saved_rows = {}
            for _, b in ipairs(state.bookmarks) do
                table.insert(saved_rows, b.row)
            end

            -- Sync save
            bookmark.save(true)

            -- Clear and reload
            state.clear_list(state.bookmarks)
            assert.equals(0, #state.bookmarks)

            bookmark.load()
            assert.equals(saved_count, #state.bookmarks)

            local loaded_rows = {}
            for _, b in ipairs(state.bookmarks) do
                table.insert(loaded_rows, b.row)
            end
            assert.same(saved_rows, loaded_rows)
        end)

        it("handles missing bookmark file gracefully", function()
            pcall(os.remove, state.bookmarks_file)
            bookmark.load()
            assert.equals(0, #state.bookmarks)
        end)

        it("handles corrupt JSON gracefully", function()
            util.ensure_parent_dir(state.bookmarks_file)
            vim.fn.writefile({ "this is not json {{{" }, state.bookmarks_file)
            bookmark.load()
            assert.equals(0, #state.bookmarks)
        end)

        it("handles empty file gracefully", function()
            util.ensure_parent_dir(state.bookmarks_file)
            vim.fn.writefile({}, state.bookmarks_file)
            bookmark.load()
            assert.equals(0, #state.bookmarks)
        end)

        it("handles JSON with missing bookmarks key", function()
            util.ensure_parent_dir(state.bookmarks_file)
            vim.fn.writefile({ '{"saved_at": 12345}' }, state.bookmarks_file)
            bookmark.load()
            assert.equals(0, #state.bookmarks)
        end)

        it("preserves all mark fields on roundtrip", function()
            helpers.set_cursor(5, 0)
            bookmark.add()

            local original = state.bookmarks[1]
            local orig_id = original.id
            local orig_col = original.col
            local orig_timestamp = original.timestamp

            bookmark.save(true)
            state.clear_list(state.bookmarks)
            bookmark.load()

            assert.equals(1, #state.bookmarks)
            assert.equals(orig_id, state.bookmarks[1].id)
            assert.equals(5, state.bookmarks[1].row)
            assert.equals(orig_col, state.bookmarks[1].col)
            assert.equals(orig_timestamp, state.bookmarks[1].timestamp)
        end)

        it("loads legacy array-format bookmarks", function()
            local fname = util.normalize_path(test_file)
            local json = vim.json and vim.json.encode or vim.fn.json_encode
            local data = json({
                bookmarks = {
                    { fname, 3, 1, 1000 },
                },
                saved_at = os.time(),
            })
            util.ensure_parent_dir(state.bookmarks_file)
            vim.fn.writefile({ data }, state.bookmarks_file)

            bookmark.load()
            assert.equals(1, #state.bookmarks)
            assert.equals(fname, state.bookmarks[1].fname)
            assert.equals(3, state.bookmarks[1].row)
        end)
    end)

    describe("cleanup", function()
        it("removes bookmarks for deleted files", function()
            helpers.set_cursor(3, 0)
            bookmark.add()

            -- Manually add a bookmark for a nonexistent file
            local fake_dir = vim.fn.tempname()
            vim.fn.mkdir(fake_dir, "p")
            table.insert(state.bookmarks, {
                id = state.next_mark_id(),
                fname = fake_dir .. "/deleted.lua",
                row = 1,
                col = 1,
                timestamp = 0,
            })
            assert.equals(2, #state.bookmarks)

            bookmark.cleanup()
            assert.equals(1, #state.bookmarks)
            assert.equals(test_file, util.normalize_path(state.bookmarks[1].fname))
        end)
    end)

    describe("clear", function()
        it("removes all bookmarks", function()
            helpers.set_cursor(3, 0)
            bookmark.add()
            helpers.set_cursor(7, 0)
            bookmark.add()
            assert.equals(2, #state.bookmarks)

            bookmark.clear()
            assert.equals(0, #state.bookmarks)
            assert.equals(-1, state.bookmarks_idx)
        end)
    end)

    describe("get", function()
        it("returns a deep copy", function()
            helpers.set_cursor(5, 0)
            bookmark.add()
            local copy = bookmark.get()
            assert.equals(1, #copy)
            assert.is_not.equals(state.bookmarks, copy)
        end)
    end)
end)
