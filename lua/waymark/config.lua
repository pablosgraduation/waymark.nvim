-- ============================================================================
-- waymark.config — Default configuration, validation, and merge logic.
-- ============================================================================

local M = {}

---@class WaymarkMappings
---@field add_bookmark string|false
---@field delete_bookmark string|false
---@field show_bookmarks string|false
---@field prev_bookmark string|false
---@field next_bookmark string|false
---@field toggle_bookmark string|false
---@field goto_bookmark_1 string|false
---@field goto_bookmark_2 string|false
---@field goto_bookmark_3 string|false
---@field goto_bookmark_4 string|false
---@field goto_bookmark_5 string|false
---@field goto_bookmark_6 string|false
---@field goto_bookmark_7 string|false
---@field goto_bookmark_8 string|false
---@field goto_bookmark_9 string|false
---@field show_automarks string|false
---@field purge_automarks string|false
---@field prev_allmark string|false
---@field next_allmark string|false
---@field prev_automark string|false
---@field next_automark string|false

---@class WaymarkConfig
---@field automark_limit integer
---@field automark_idle_ms number
---@field automark_min_lines integer
---@field automark_min_interval_ms number
---@field automark_cleanup_lines integer
---@field automark_recent_ms number
---@field jump_flash_ms number
---@field jump_flash_color string
---@field automark_sign string
---@field bookmark_sign string
---@field automark_sign_color string
---@field bookmark_sign_color string
---@field popup_check_color string
---@field popup_uncheck_color string
---@field popup_preview_color string
---@field popup_help_color string
---@field ignored_filetypes string[]
---@field ignored_patterns string[]
---@field mappings WaymarkMappings|false
---@field _ignored_ft_set table<string, boolean>  Internal: built by setup()

---@type WaymarkConfig
M.defaults = {
    -- Maximum number of automarks kept (oldest evicted when exceeded)
    automark_limit = 15,
    -- Idle duration (ms) before placing an automark at the cursor
    automark_idle_ms = 3000,
    -- Minimum line distance to create a new automark (prevents micro-movement clutter)
    automark_min_lines = 5,
    -- Time gate (ms) for small movements below automark_min_lines (0 = no gate)
    automark_min_interval_ms = 2000,

    -- Context cleanup: remove older nearby automarks in the same window/tab
    automark_cleanup_lines = 10,
    -- Age threshold (ms): protect recent marks from context cleanup (0 to disable)
    automark_recent_ms = 30000,

    -- Jump flash: briefly highlight the target line after jumping (0 to disable)
    jump_flash_ms = 200,
    jump_flash_color = "#4a4a4a",

    -- Gutter sign characters
    automark_sign = "¤",
    bookmark_sign = "※",

    -- Sign and line-number highlight colors
    automark_sign_color = "#757575",
    bookmark_sign_color = "#FFD700",

    -- Bookmarks popup highlight colors
    popup_check_color = "#E08070",
    popup_uncheck_color = "#555555",
    popup_preview_color = "#666666",
    popup_help_color = "#555555",

    -- Buffer filtering: filetypes and filename patterns to ignore.
    ignored_filetypes = {
        "neo-tree",
        "diffview",
        "spectre",
        "telescope",
        "help",
        "qf",
        "fugitive",
        "git",
        "toggleterm",
        "",
        "netrw",
    },
    ignored_patterns = {
        "neo%-tree",
        "diffview://",
        "spectre_panel",
        "Telescope",
        "^term://",
        "^fugitive://",
        "COMMIT_EDITMSG",
        "^oil://",
        "%.local/share/nvim/scratch/.*Scratch",
    },

    -- Keymaps: set to `false` to disable all, or override individual keys.
    mappings = {
        add_bookmark = "<leader>bb",
        delete_bookmark = "<leader>bd",
        show_bookmarks = "<leader>bl",
        prev_bookmark = "<leader>bp",
        next_bookmark = "<leader>bn",
        toggle_bookmark = "<S-N>",
        goto_bookmark_1 = "<leader>b1",
        goto_bookmark_2 = "<leader>b2",
        goto_bookmark_3 = "<leader>b3",
        goto_bookmark_4 = "<leader>b4",
        goto_bookmark_5 = "<leader>b5",
        goto_bookmark_6 = "<leader>b6",
        goto_bookmark_7 = "<leader>b7",
        goto_bookmark_8 = "<leader>b8",
        goto_bookmark_9 = "<leader>b9",
        show_automarks = "<leader>bal",
        purge_automarks = "<leader>bac",
        prev_allmark = "<C-b>",
        next_allmark = false,
        prev_automark = "[a",
        next_automark = "]a",
    },
}

--- Active configuration (deep-copied from defaults, merged with user opts in setup()).
---@type WaymarkConfig
M.current = vim.deepcopy(M.defaults)

-- Pre-build the filetype lookup set so should_ignore_buffer() works before setup().
M.current._ignored_ft_set = {}
for _, ft in ipairs(M.current.ignored_filetypes) do
    M.current._ignored_ft_set[ft] = true
end

-- ---------------------------------------------------------------------------
-- Validation helpers
-- ---------------------------------------------------------------------------

--- Validate that config[name] is a number >= 0; reset to default if not.
local function check_non_negative(name)
    local v = M.current[name]
    if type(v) ~= "number" or v < 0 then
        vim.notify(
            string.format("waymark: %s must be a non-negative number (got %s), using default", name, tostring(v)),
            vim.log.levels.WARN
        )
        M.current[name] = M.defaults[name]
    end
end

--- Validate that config[name] is a positive integer (>= 1); reset to default if not.
local function check_positive_int(name)
    local v = M.current[name]
    if type(v) ~= "number" or v < 1 or v ~= math.floor(v) then
        vim.notify(
            string.format("waymark: %s must be a positive integer (got %s), using default", name, tostring(v)),
            vim.log.levels.WARN
        )
        M.current[name] = M.defaults[name]
    end
end

--- Validate that config[name] is a string; reset to default if not.
local function check_string(name)
    if type(M.current[name]) ~= "string" then
        vim.notify(
            string.format("waymark: %s must be a string (got %s), using default", name, type(M.current[name])),
            vim.log.levels.WARN
        )
        M.current[name] = M.defaults[name]
    end
end

--- Merge user options into defaults and validate all values.
---@param opts WaymarkConfig|nil  Partial config overrides
function M.setup(opts)
    M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})

    -- `tbl_deep_extend` merges tables, so `mappings = false` (a boolean) gets
    -- overwritten by the default table. Restore the user's intent explicitly.
    if opts and opts.mappings == false then
        M.current.mappings = false
    end

    check_positive_int("automark_limit")

    check_non_negative("automark_idle_ms")
    if M.current.automark_idle_ms < 100 then
        vim.notify(
            "waymark: automark_idle_ms must be >= 100 (got " .. M.current.automark_idle_ms .. "), using 100",
            vim.log.levels.WARN
        )
        M.current.automark_idle_ms = 100
    end

    check_positive_int("automark_min_lines")
    check_non_negative("automark_min_interval_ms")
    check_positive_int("automark_cleanup_lines")
    check_non_negative("automark_recent_ms")

    check_non_negative("jump_flash_ms")
    check_string("jump_flash_color")
    check_string("automark_sign")
    check_string("bookmark_sign")
    check_string("automark_sign_color")
    check_string("bookmark_sign_color")
    check_string("popup_check_color")
    check_string("popup_uncheck_color")
    check_string("popup_preview_color")
    check_string("popup_help_color")

    if type(M.current.ignored_filetypes) ~= "table" then
        vim.notify("waymark: ignored_filetypes must be a table, using default", vim.log.levels.WARN)
        M.current.ignored_filetypes = M.defaults.ignored_filetypes
    end
    if type(M.current.ignored_patterns) ~= "table" then
        vim.notify("waymark: ignored_patterns must be a table, using default", vim.log.levels.WARN)
        M.current.ignored_patterns = M.defaults.ignored_patterns
    end

    -- Build O(1) filetype lookup set
    M.current._ignored_ft_set = {}
    for _, ft in ipairs(M.current.ignored_filetypes) do
        M.current._ignored_ft_set[ft] = true
    end
end

return M
