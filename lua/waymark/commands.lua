-- ============================================================================
-- waymark.commands — User command and keymap registration.
-- ============================================================================

local config = require("waymark.config")
local state = require("waymark.state")
local filter = require("waymark.filter")
local automark = require("waymark.automark")
local bookmark = require("waymark.bookmark")
local allmark = require("waymark.allmark")
local popup = require("waymark.popup")

local M = {}

--- Register all :Waymark* user commands.
function M.register_commands()
    -- Bookmarks
    vim.api.nvim_create_user_command("WaymarkAddBookmark", function()
        if filter.should_ignore_buffer() then
            return
        end
        bookmark.add()
    end, { desc = "Add bookmark at cursor" })

    vim.api.nvim_create_user_command("WaymarkDeleteBookmark", function()
        bookmark.delete()
    end, { desc = "Delete bookmark at cursor" })

    vim.api.nvim_create_user_command("WaymarkToggleBookmark", function()
        bookmark.toggle()
    end, { desc = "Toggle bookmark at current line" })

    vim.api.nvim_create_user_command("WaymarkShowBookmarks", function()
        popup.show()
    end, { desc = "Show bookmarks popup" })

    vim.api.nvim_create_user_command("WaymarkPrevBookmark", function(opts)
        local n = opts.count > 0 and opts.count or vim.v.count1
        bookmark.prev(n)
    end, { count = true, desc = "Go to previous bookmark (toward older, cycles)" })

    vim.api.nvim_create_user_command("WaymarkNextBookmark", function(opts)
        local n = opts.count > 0 and opts.count or vim.v.count1
        bookmark.next(n)
    end, { count = true, desc = "Go to next bookmark (toward newer, cycles)" })

    vim.api.nvim_create_user_command("WaymarkJumpBookmark", function(opts)
        state.warn_if_no_setup()
        if filter.should_ignore_buffer() then
            return
        end
        local index = tonumber(opts.args)
        if index then
            bookmark.jump_to_index(index)
        else
            vim.notify("Usage: :WaymarkJumpBookmark <index>")
        end
    end, {
        desc = "Jump to bookmark by index",
        nargs = 1,
        complete = function()
            local items = {}
            for i = 1, #state.bookmarks do
                items[i] = tostring(i)
            end
            return items
        end,
    })

    vim.api.nvim_create_user_command("WaymarkClearBookmarks", function()
        bookmark.clear()
    end, { desc = "Remove all bookmarks" })

    -- Automarks
    vim.api.nvim_create_user_command("WaymarkPrevAutomark", function(opts)
        local n = opts.count > 0 and opts.count or vim.v.count1
        automark.prev(n)
    end, { count = true, desc = "Go to previous automark (cycles)" })

    vim.api.nvim_create_user_command("WaymarkNextAutomark", function(opts)
        local n = opts.count > 0 and opts.count or vim.v.count1
        automark.next(n)
    end, { count = true, desc = "Go to next automark (cycles)" })

    vim.api.nvim_create_user_command("WaymarkShowAutomarks", function()
        automark.show()
    end, { desc = "Show all saved automarks" })

    vim.api.nvim_create_user_command("WaymarkPurgeAutomarks", function()
        automark.purge()
    end, { desc = "Clean up automarks from deleted files" })

    vim.api.nvim_create_user_command("WaymarkClearAutomarks", function()
        automark.clear()
    end, { desc = "Remove all automarks" })

    -- Allmarks (merged timeline)
    vim.api.nvim_create_user_command("WaymarkPrevAllmark", function(opts)
        local n = opts.count > 0 and opts.count or vim.v.count1
        allmark.prev(n)
    end, { count = true, desc = "Go to previous mark in merged timeline (cycles)" })

    vim.api.nvim_create_user_command("WaymarkNextAllmark", function(opts)
        local n = opts.count > 0 and opts.count or vim.v.count1
        allmark.next(n)
    end, { count = true, desc = "Go to next mark in merged timeline (cycles)" })

    -- Debug
    vim.api.nvim_create_user_command("WaymarkDebug", function()
        local lines = {
            "Bookmarks: " .. #state.bookmarks .. " (idx=" .. state.bookmarks_idx .. ")",
            "Automarks: " .. #state.automarks .. " (idx=" .. state.automarks_idx .. ")",
        }
        for i, a in ipairs(state.automarks) do
            local ext = a.extmark_id and ("ext=" .. a.extmark_id) or "no-ext"
            table.insert(
                lines,
                string.format("  auto %d: %s:%d [%s]", i, vim.fn.fnamemodify(a.fname, ":t"), a.row, ext)
            )
        end
        for i, b in ipairs(state.bookmarks) do
            local ext = b.extmark_id and ("ext=" .. b.extmark_id) or "no-ext"
            table.insert(
                lines,
                string.format("  book %d: %s:%d [%s]", i, vim.fn.fnamemodify(b.fname, ":t"), b.row, ext)
            )
        end
        vim.notify(table.concat(lines, "\n"))
    end, { desc = "Debug marks state" })
end

--- Register keymaps based on config.mappings. Cleans up previous keymaps first.
function M.register_keymaps()
    -- Remove keymaps from a previous setup() call
    for _, key in ipairs(state.active_keymaps) do
        pcall(vim.keymap.del, "n", key)
    end
    state.active_keymaps = {}

    if config.current.mappings == false then
        return
    end

    local m = config.current.mappings

    local function map(key, cmd, desc)
        if key then
            vim.keymap.set("n", key, cmd, { desc = desc, silent = true })
            table.insert(state.active_keymaps, key)
        end
    end

    -- Bookmark management
    map(m.add_bookmark, "<Cmd>WaymarkAddBookmark<CR>", "Add bookmark at cursor")
    map(m.delete_bookmark, "<Cmd>WaymarkDeleteBookmark<CR>", "Delete bookmark at cursor")
    map(m.show_bookmarks, "<Cmd>WaymarkShowBookmarks<CR>", "Show bookmarks popup")

    -- Bookmark navigation
    map(m.prev_bookmark, "<Cmd>WaymarkPrevBookmark<CR>", "Previous bookmark")
    map(m.next_bookmark, "<Cmd>WaymarkNextBookmark<CR>", "Next bookmark")

    -- Toggle
    map(m.toggle_bookmark, "<Cmd>WaymarkToggleBookmark<CR>", "Toggle bookmark at current line")

    -- Quick bookmark jumps 1-9
    for i = 1, 9 do
        local key = m["goto_bookmark_" .. i]
        if type(key) == "string" and key ~= "" then
            vim.keymap.set(
                "n",
                key,
                "<Cmd>WaymarkJumpBookmark " .. i .. "<CR>",
                { desc = "Jump to bookmark " .. i, silent = true }
            )
            table.insert(state.active_keymaps, key)
        end
    end

    -- Automark management
    map(m.show_automarks, "<Cmd>WaymarkShowAutomarks<CR>", "Show automarks")
    map(m.purge_automarks, "<Cmd>WaymarkPurgeAutomarks<CR>", "Clean invalid automarks")

    -- Merged timeline
    map(m.prev_allmark, "<Cmd>WaymarkPrevAllmark<CR>", "Previous allmark (merged timeline)")
    map(m.next_allmark, "<Cmd>WaymarkNextAllmark<CR>", "Next allmark (merged timeline)")

    -- Automark navigation
    map(m.prev_automark, "<Cmd>WaymarkPrevAutomark<CR>", "Previous automark")
    map(m.next_automark, "<Cmd>WaymarkNextAutomark<CR>", "Next automark")
end

return M
