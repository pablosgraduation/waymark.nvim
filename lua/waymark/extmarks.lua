-- ============================================================================
-- waymark.extmarks — Extmark CRUD, sync/restore cycle, and lifecycle autocmds.
-- ============================================================================

local config = require("waymark.config")
local state = require("waymark.state")
local util = require("waymark.util")

local M = {}

-- ---------------------------------------------------------------------------
-- Core extmark operations
-- ---------------------------------------------------------------------------

--- Place a sign extmark for a mark in its buffer.
---@param mark table     Mark struct with .fname, .row, .col fields
---@param ns integer     Extmark namespace
---@param sign_text string  Character to display in the sign column
---@param text_hl string    Highlight group for the sign
---@param num_hl string     Highlight group for the line number
function M.place(mark, ns, sign_text, text_hl, num_hl)
    local bufnr = vim.fn.bufnr(mark.fname)
    if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
        mark.extmark_id = nil
        mark.bufnr = nil
        return
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local row = math.min(mark.row, line_count)
    if row < 1 then
        row = 1
    end
    mark.row = row

    local ok, ext_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row - 1, 0, {
        sign_text = sign_text,
        sign_hl_group = text_hl,
        number_hl_group = num_hl,
        priority = 1,
    })

    if ok then
        mark.extmark_id = ext_id
        mark.bufnr = bufnr
    else
        mark.extmark_id = nil
        mark.bufnr = nil
    end
end

--- Remove a mark's extmark from its buffer and clear the reference.
---@param mark table     Mark struct
---@param ns integer     Extmark namespace
function M.remove(mark, ns)
    if mark.extmark_id and mark.bufnr then
        if vim.api.nvim_buf_is_valid(mark.bufnr) then
            pcall(vim.api.nvim_buf_del_extmark, mark.bufnr, ns, mark.extmark_id)
        end
        mark.extmark_id = nil
        mark.bufnr = nil
    end
end

--- Read the current position of a mark's extmark and update mark.row.
---@param mark table     Mark struct
---@param ns integer     Extmark namespace
function M.sync_from_extmark(mark, ns)
    if mark.extmark_id and mark.bufnr and vim.api.nvim_buf_is_valid(mark.bufnr) then
        local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, mark.bufnr, ns, mark.extmark_id, {})
        if ok and pos and #pos >= 2 then
            mark.row = pos[1] + 1
        end
    end
end

--- Restore extmarks for all marks belonging to a given buffer.
---@param bufnr integer    Buffer number
---@param marks table      Mark list (automarks or bookmarks)
---@param ns integer       Extmark namespace
---@param sign_text string Sign character
---@param text_hl string   Sign highlight group
---@param num_hl string    Line number highlight group
function M.restore_for_buffer(bufnr, marks, ns, sign_text, text_hl, num_hl)
    local fname = util.normalize_path(vim.api.nvim_buf_get_name(bufnr))
    if fname == "" then
        return
    end

    for _, mark in ipairs(marks) do
        if mark.fname == fname and not mark.extmark_id then
            M.place(mark, ns, sign_text, text_hl, num_hl)
        end
    end
end

--- Sync positions from extmarks for all marks in a buffer, then clear refs.
---@param bufnr integer  Buffer number
---@param marks table    Mark list
---@param ns integer     Extmark namespace
function M.sync_buffer_positions(bufnr, marks, ns)
    for _, mark in ipairs(marks) do
        if mark.bufnr == bufnr then
            M.sync_from_extmark(mark, ns)
            mark.extmark_id = nil
            mark.bufnr = nil
        end
    end
end

--- Remove duplicate bookmarks on the same line after buffer edits.
function M.deduplicate_bookmarks()
    local seen = {}
    local to_remove = {}
    for i = 1, #state.bookmarks do
        local key = util.mark_key(state.bookmarks[i].fname, state.bookmarks[i].row)
        if seen[key] then
            table.insert(to_remove, i)
        else
            seen[key] = i
        end
    end

    if #to_remove == 0 then
        return
    end

    for j = #to_remove, 1, -1 do
        local i = to_remove[j]
        local key = util.mark_key(state.bookmarks[i].fname, state.bookmarks[i].row)
        M.remove(state.bookmarks[i], state.ns_bookmark)
        table.remove(state.bookmarks, i)
        if state.bookmarks_idx > i then
            state.bookmarks_idx = state.bookmarks_idx - 1
        elseif state.bookmarks_idx == i then
            state.bookmarks_idx = seen[key]
        end
    end

    if state.bookmarks_idx > #state.bookmarks then
        state.bookmarks_idx = -1
    end
    require("waymark.bookmark").save()
end

-- ---------------------------------------------------------------------------
-- Lifecycle autocmds
-- ---------------------------------------------------------------------------

--- Register BufEnter / BufUnload / BufDelete / BufWritePost autocmds.
function M.setup()
    local filter = require("waymark.filter")

    -- BufEnter: restore extmarks for marks in this buffer
    vim.api.nvim_create_autocmd("BufEnter", {
        desc = "Restore extmarks for marks in this buffer",
        group = vim.api.nvim_create_augroup("waymark_buf_enter", { clear = true }),
        callback = function(args)
            local bufnr = args.buf
            if not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end
            vim.defer_fn(function()
                if not vim.api.nvim_buf_is_valid(bufnr) then
                    return
                end
                local cc = config.current
                M.restore_for_buffer(
                    bufnr,
                    state.automarks,
                    state.ns_automark,
                    cc.automark_sign,
                    "WaymarkAutomarkSign",
                    "WaymarkAutomarkNum"
                )
                M.restore_for_buffer(
                    bufnr,
                    state.bookmarks,
                    state.ns_bookmark,
                    cc.bookmark_sign,
                    "WaymarkBookmarkSign",
                    "WaymarkBookmarkNum"
                )
            end, 50)
        end,
    })

    -- BufUnload: sync extmark positions before buffer unloads
    local function on_buf_unload(bufnr)
        if not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end
        M.sync_buffer_positions(bufnr, state.automarks, state.ns_automark)
        M.sync_buffer_positions(bufnr, state.bookmarks, state.ns_bookmark)
    end

    vim.api.nvim_create_autocmd("BufUnload", {
        desc = "Sync extmark positions before buffer unloads",
        group = vim.api.nvim_create_augroup("waymark_buf_unload", { clear = true }),
        callback = function(args)
            on_buf_unload(args.buf)
        end,
    })

    -- Belt-and-suspenders: BufDelete fires on :bdelete/:bwipeout, while
    -- BufUnload fires when a buffer is unloaded but may not fire in all wipe
    -- scenarios. Registering both ensures extmark positions are synced
    -- regardless of how the buffer disappears. The handler is idempotent
    -- (syncing an already-synced buffer is a no-op) so double-firing is harmless.
    vim.api.nvim_create_autocmd("BufDelete", {
        desc = "Sync extmark positions before buffer is deleted/wiped",
        group = vim.api.nvim_create_augroup("waymark_buf_delete", { clear = true }),
        callback = function(args)
            on_buf_unload(args.buf)
        end,
    })

    -- BufWritePost: full sync → dedup → restore cycle.
    -- Format-on-save (conform.nvim, null-ls, LSP formatting) can move lines,
    -- causing extmarks to shift. Two bookmarks on adjacent lines may end up
    -- on the same line after formatting. The cycle syncs positions from the
    -- (possibly moved) extmarks, removes duplicates, then re-places extmarks
    -- at the canonical positions.
    vim.api.nvim_create_autocmd("BufWritePost", {
        desc = "Re-sync extmarks after buffer write (handles format-on-save)",
        group = vim.api.nvim_create_augroup("waymark_buf_write", { clear = true }),
        callback = function(args)
            local bufnr = args.buf
            if not vim.api.nvim_buf_is_valid(bufnr) then
                return
            end
            if filter.should_ignore_buffer(bufnr) then
                return
            end

            M.sync_buffer_positions(bufnr, state.automarks, state.ns_automark)
            M.sync_buffer_positions(bufnr, state.bookmarks, state.ns_bookmark)
            M.deduplicate_bookmarks()

            local cc = config.current
            M.restore_for_buffer(
                bufnr,
                state.automarks,
                state.ns_automark,
                cc.automark_sign,
                "WaymarkAutomarkSign",
                "WaymarkAutomarkNum"
            )
            M.restore_for_buffer(
                bufnr,
                state.bookmarks,
                state.ns_bookmark,
                cc.bookmark_sign,
                "WaymarkBookmarkSign",
                "WaymarkBookmarkNum"
            )
        end,
    })
end

return M
