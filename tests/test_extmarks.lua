-- tests/test_extmarks.lua
local extmarks = require("waymark.extmarks")
local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")
local helpers = require("tests.helpers")

describe("waymark.extmarks", function()
    local test_file
    local bufnr

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
        bufnr = helpers.open_file(test_file)
    end)

    describe("place", function()
        it("places an extmark and stores the ID on the mark", function()
            local mark = { fname = util.normalize_path(test_file), row = 3, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            assert.is_not_nil(mark.extmark_id)
            assert.is_not_nil(mark.bufnr)
        end)

        it("places extmark at correct 0-indexed line", function()
            local mark = { fname = util.normalize_path(test_file), row = 5, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            local ext_list = vim.api.nvim_buf_get_extmarks(mark.bufnr, state.ns_bookmark, 0, -1, {})
            local found = false
            for _, ext in ipairs(ext_list) do
                if ext[1] == mark.extmark_id then
                    assert.equals(4, ext[2]) -- 0-indexed
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)

        it("clamps row to buffer line count when past end", function()
            local mark = { fname = util.normalize_path(test_file), row = 50, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            assert.is_true(mark.row <= 10)
        end)

        it("clamps row to 1 when row is 0", function()
            local mark = { fname = util.normalize_path(test_file), row = 0, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            assert.equals(1, mark.row)
        end)

        it("clamps row to 1 when row is negative", function()
            local mark = { fname = util.normalize_path(test_file), row = -5, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            assert.equals(1, mark.row)
        end)

        it("sets extmark_id to nil for unloaded buffer", function()
            local mark = { fname = "/nonexistent/file.lua", row = 1, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            assert.is_nil(mark.extmark_id)
            assert.is_nil(mark.bufnr)
        end)
    end)

    describe("remove", function()
        it("removes extmark and clears references", function()
            local mark = { fname = util.normalize_path(test_file), row = 3, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            assert.is_not_nil(mark.extmark_id)

            extmarks.remove(mark, state.ns_bookmark)
            assert.is_nil(mark.extmark_id)
            assert.is_nil(mark.bufnr)
        end)

        it("is idempotent", function()
            local mark = { fname = util.normalize_path(test_file), row = 3, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            extmarks.remove(mark, state.ns_bookmark)
            assert.has_no.errors(function()
                extmarks.remove(mark, state.ns_bookmark)
            end)
        end)

        it("handles mark with no extmark_id", function()
            local mark = { fname = util.normalize_path(test_file), row = 3, col = 0 }
            assert.has_no.errors(function()
                extmarks.remove(mark, state.ns_bookmark)
            end)
        end)
    end)

    describe("sync_from_extmark", function()
        it("updates row after line insertion above", function()
            local mark = { fname = util.normalize_path(test_file), row = 3, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")

            vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "inserted" })
            extmarks.sync_from_extmark(mark, state.ns_bookmark)
            assert.equals(4, mark.row)
        end)

        it("does nothing for mark without extmark_id", function()
            local mark = { fname = util.normalize_path(test_file), row = 5, col = 0 }
            extmarks.sync_from_extmark(mark, state.ns_bookmark)
            assert.equals(5, mark.row)
        end)
    end)

    describe("restore_for_buffer", function()
        it("places extmarks for marks matching the buffer file", function()
            local fname = util.normalize_path(test_file)
            state.bookmarks = {
                { id = 1, fname = fname, row = 2, col = 0 },
                { id = 2, fname = fname, row = 7, col = 0 },
            }

            extmarks.restore_for_buffer(
                bufnr,
                state.bookmarks,
                state.ns_bookmark,
                "※",
                "WaymarkBookmarkSign",
                "WaymarkBookmarkNum"
            )

            assert.is_not_nil(state.bookmarks[1].extmark_id)
            assert.is_not_nil(state.bookmarks[2].extmark_id)
        end)

        it("skips marks that already have extmark_id", function()
            local fname = util.normalize_path(test_file)
            local mark = { id = 1, fname = fname, row = 3, col = 0 }
            extmarks.place(mark, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            local original_id = mark.extmark_id

            state.bookmarks = { mark }
            extmarks.restore_for_buffer(
                bufnr,
                state.bookmarks,
                state.ns_bookmark,
                "※",
                "WaymarkBookmarkSign",
                "WaymarkBookmarkNum"
            )

            assert.equals(original_id, mark.extmark_id)
        end)

        it("skips marks for different files", function()
            local mark = { id = 1, fname = "/other/file.lua", row = 3, col = 0 }
            state.bookmarks = { mark }
            extmarks.restore_for_buffer(
                bufnr,
                state.bookmarks,
                state.ns_bookmark,
                "※",
                "WaymarkBookmarkSign",
                "WaymarkBookmarkNum"
            )
            assert.is_nil(mark.extmark_id)
        end)

        it("does nothing for empty buffer name", function()
            local scratch = vim.api.nvim_create_buf(false, true)
            local mark = { id = 1, fname = "", row = 1, col = 0 }
            state.bookmarks = { mark }
            assert.has_no.errors(function()
                extmarks.restore_for_buffer(
                    scratch,
                    state.bookmarks,
                    state.ns_bookmark,
                    "※",
                    "WaymarkBookmarkSign",
                    "WaymarkBookmarkNum"
                )
            end)
            assert.is_nil(mark.extmark_id)
            pcall(vim.api.nvim_buf_delete, scratch, { force = true })
        end)
    end)

    describe("sync_buffer_positions", function()
        it("clears extmark refs for marks in buffer", function()
            local fname = util.normalize_path(test_file)
            local mark1 = { id = 1, fname = fname, row = 2, col = 0 }
            local mark2 = { id = 2, fname = fname, row = 7, col = 0 }
            extmarks.place(mark1, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            extmarks.place(mark2, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            state.bookmarks = { mark1, mark2 }

            extmarks.sync_buffer_positions(bufnr, state.bookmarks, state.ns_bookmark)

            assert.is_nil(mark1.extmark_id)
            assert.is_nil(mark1.bufnr)
            assert.is_nil(mark2.extmark_id)
            assert.is_nil(mark2.bufnr)
        end)

        it("does not touch marks in other buffers", function()
            local fname = util.normalize_path(test_file)
            local mark1 = { id = 1, fname = fname, row = 2, col = 0 }
            extmarks.place(mark1, state.ns_bookmark, "※", "WaymarkBookmarkSign", "WaymarkBookmarkNum")
            local fake_mark = { id = 2, fname = "/other.lua", row = 1, col = 0, bufnr = 99999, extmark_id = 42 }
            state.bookmarks = { mark1, fake_mark }

            extmarks.sync_buffer_positions(bufnr, state.bookmarks, state.ns_bookmark)

            assert.equals(99999, fake_mark.bufnr)
        end)
    end)

    describe("deduplicate_bookmarks", function()
        it("merges two bookmarks on the same line", function()
            local fname = util.normalize_path(test_file)
            state.bookmarks = {
                { id = 1, fname = fname, row = 5, col = 0 },
                { id = 2, fname = fname, row = 5, col = 0 },
            }
            state.bookmarks_idx = -1

            extmarks.deduplicate_bookmarks()
            assert.equals(1, #state.bookmarks)
        end)

        it("does nothing when no duplicates", function()
            local fname = util.normalize_path(test_file)
            state.bookmarks = {
                { id = 1, fname = fname, row = 3, col = 0 },
                { id = 2, fname = fname, row = 7, col = 0 },
            }
            extmarks.deduplicate_bookmarks()
            assert.equals(2, #state.bookmarks)
        end)

        it("adjusts bookmarks_idx when duplicate is removed below it", function()
            local fname = util.normalize_path(test_file)
            state.bookmarks = {
                { id = 1, fname = fname, row = 5, col = 0 },
                { id = 2, fname = fname, row = 5, col = 0 },
                { id = 3, fname = fname, row = 9, col = 0 },
            }
            state.bookmarks_idx = 3
            extmarks.deduplicate_bookmarks()
            -- Duplicate at index 2 removed. idx 3 > 2, so idx becomes 2.
            -- List now has 2 items, 2 <= 2, so no further reset.
            assert.equals(2, state.bookmarks_idx)
        end)

        it("adjusts bookmarks_idx when earlier entry is removed", function()
            local fname = util.normalize_path(test_file)
            state.bookmarks = {
                { id = 1, fname = fname, row = 1, col = 0 },
                { id = 2, fname = fname, row = 1, col = 0 },
                { id = 3, fname = fname, row = 5, col = 0 },
            }
            state.bookmarks_idx = 3
            extmarks.deduplicate_bookmarks()
            -- Duplicate at index 2 is removed. idx 3 > 2, so idx becomes 2.
            assert.equals(2, state.bookmarks_idx)
        end)
    end)
end)
