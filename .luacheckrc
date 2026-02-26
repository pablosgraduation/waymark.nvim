-- luacheck configuration for waymark.nvim
-- See: https://luacheck.readthedocs.io/en/stable/config.html

-- Rerun: luacheck lua/ tests/

std = "luajit"

-- Neovim globals
read_globals = {
    vim = {
        fields = {
            g = { other_fields = true, read_only = false },
            o = { other_fields = true, read_only = false },
            bo = { other_fields = true, read_only = false },
            wo = { other_fields = true, read_only = false },
            env = { other_fields = true, read_only = false },
        },
        other_fields = true,
    },
}

-- Allow globals we define intentionally
globals = {
    "_G._waymark_state",
}

-- Don't complain about unused arguments prefixed with _
unused_args = false

-- Max line length (matches .stylua.toml column_width)
max_line_length = 140

-- Allow globals we define intentionally and test framework globals
files["tests/**/*.lua"] = {
    read_globals = {
        "describe",
        "it",
        "before_each",
        "after_each",
        "assert",
        "pending",
    },
    max_line_length = 160,
}

-- Ignore some noisy warnings:
--   212 = unused argument
ignore = {
    "212/self",
}
