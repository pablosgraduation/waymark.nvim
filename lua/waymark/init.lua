-- ============================================================================
-- WAYMARK — Position-Tracking & Navigation Plugin for Neovim
-- ============================================================================
--
-- Waymark provides three complementary navigation subsystems that work
-- alongside (not replacing) Neovim's built-in jumplist and named marks:
--
--   Automark    Automatic breadcrumbs recorded on idle, InsertLeave,
--               BufLeave, and LSP jumps. Session-only, never persisted.
--
--   Bookmark    User-placed persistent marks. Survive across sessions
--               (saved as JSON) with an interactive popup for management.
--
--   Allmark     A merged chronological timeline of both automarks and
--               bookmarks for unified navigation.
--
-- Quick start:
--
--   require("waymark").setup()                -- use all defaults
--   require("waymark").setup({ ... })         -- override specific options
--   require("waymark").setup({ mappings = false })  -- disable all keymaps
--
-- ============================================================================

local M = {}

--- Initialize the plugin. Merges user options into defaults, validates config,
--- applies highlights, registers keymaps, and starts tracking.
---
--- Can be called multiple times (e.g. to change config at runtime).
---
---@param opts table|nil  Partial config overrides. See config.lua for all options.
function M.setup(opts)
    local cfg = require("waymark.config")
    local state = require("waymark.state")
    local highlights = require("waymark.highlights")
    local filter = require("waymark.filter")
    local extmarks = require("waymark.extmarks")
    local automark = require("waymark.automark")
    local bookmark = require("waymark.bookmark")
    local commands = require("waymark.commands")

    -- Steps are ordered by dependency: config must be validated first (everything
    -- reads it), highlights before commands (sign placement references groups),
    -- filter before extmarks (extmarks setup uses filter), automark before bookmark
    -- (bookmark.setup's VimEnter handler needs automark's namespace to exist).

    -- 1. Merge & validate config
    cfg.setup(opts)

    -- 2. Flush the buffer-ignore cache
    state.ignore_cache = {}

    -- 3. Apply highlight groups (and register ColorScheme autocmd)
    highlights.setup()

    -- 4. Register user commands (idempotent — safe to call multiple times)
    commands.register_commands()

    -- 5. Register keymaps
    commands.register_keymaps()

    -- 6. Register buffer filtering autocmds
    filter.setup()

    -- 7. Register extmark lifecycle autocmds
    extmarks.setup()

    -- 8. Register automark tracking (on_key, InsertLeave, BufLeave, LSP)
    automark.setup()

    -- 9. Register bookmark startup/shutdown autocmds (VimEnter, VimLeavePre)
    bookmark.setup()

    -- 10. If VimEnter already fired (lazy-loaded plugin), bootstrap immediately
    if vim.v.vim_did_enter == 1 then
        bookmark.load()
        state.sync_mark_id_counter()
        bookmark.cleanup()
        vim.defer_fn(function()
            local bufnr = vim.api.nvim_get_current_buf()
            if vim.api.nvim_buf_is_valid(bufnr) then
                extmarks.restore_for_buffer(
                    bufnr,
                    state.bookmarks,
                    state.ns_bookmark,
                    cfg.current.bookmark_sign,
                    "WaymarkBookmarkSign",
                    "WaymarkBookmarkNum"
                )
            end
        end, 100)
    end

    state.setup_done = true
end

-- ============================================================================
-- Public API
-- ============================================================================

-- Bookmarks
function M.add_bookmark()
    require("waymark.bookmark").add()
end
function M.delete_bookmark()
    require("waymark.bookmark").delete()
end
function M.toggle_bookmark()
    require("waymark.bookmark").toggle()
end
function M.show_bookmarks()
    require("waymark.popup").show()
end
function M.clear_bookmarks()
    require("waymark.bookmark").clear()
end
function M.get_bookmarks()
    return require("waymark.bookmark").get()
end
function M.prev_bookmark(n)
    require("waymark.bookmark").prev(n)
end
function M.next_bookmark(n)
    require("waymark.bookmark").next(n)
end

---@param index integer  1-based bookmark index
function M.goto_bookmark(index)
    require("waymark.bookmark").goto_bookmark(index)
end

-- Automarks
function M.prev_automark(n)
    require("waymark.automark").prev(n)
end
function M.next_automark(n)
    require("waymark.automark").next(n)
end
function M.show_automarks()
    require("waymark.automark").show()
end
function M.purge_automarks()
    require("waymark.automark").purge()
end
function M.clear_automarks()
    require("waymark.automark").clear()
end
function M.get_automarks()
    return require("waymark.automark").get()
end

-- Allmarks (merged timeline)
function M.prev_allmark(n)
    require("waymark.allmark").prev(n)
end
function M.next_allmark(n)
    require("waymark.allmark").next(n)
end

return M
