# Contributing to waymark.nvim

Thanks for your interest in contributing. This document covers what you need to
know to submit a useful pull request.

## Requirements

- Neovim ≥ 0.10 (for development)
- [stylua](https://github.com/JohnnyMorganz/StyLua) (formatting)
- [luacheck](https://github.com/mpeterv/luacheck) (linting)

## Quick start

```sh
git clone https://github.com/pablosgraduation/waymark.nvim.git
cd waymark.nvim

# Run the full test suite
./scripts/test.sh

# Run a single test file
./scripts/test.sh test_bookmark

# Lint
./scripts/lint.sh

# Format (check mode)
./scripts/format.sh --check

# Format (fix mode)
./scripts/format.sh
```

Plenary.nvim is auto-bootstrapped on first test run — no manual install needed.

## Architecture rules

Waymark uses a **hub-and-spoke architecture**. These rules exist to prevent
circular dependencies and keep the codebase navigable:

1. **`state.lua` is the only shared mutable state.** Modules communicate by
   reading/writing `state`, never by requiring each other's tables directly.
2. **No cross-module requires** except through the module's public API
   (e.g. `bookmark.lua` may call `extmarks.remove()`, but never reads
   `extmarks` internal locals).
3. **`extmarks.lua` is the single authority** for all Neovim extmark
   operations. No other module calls `nvim_buf_set_extmark` or
   `nvim_buf_del_extmark` directly.
4. **`filter.lua` is the single authority** for buffer ignore decisions. If you
   need to check whether a buffer should be tracked, call
   `filter.should_ignore_buffer(bufnr)`.

## Code style

- **Formatter**: stylua (config in `.stylua.toml`). Run before every commit.
- **Linter**: luacheck (config in `.luacheckrc`). Zero warnings required.
- **Line length**: 120 columns (stylua), 140 columns (luacheck max).
- **No padded alignment**: use `local x = ...`, not `local x    = ...`.
- **Multi-line calls**: one argument per line when wrapping.
- **Naming**: `snake_case` for everything. Module-local helpers are `local function`.

## Pull request checklist

Before opening a PR:

- [ ] Tests pass: `./scripts/test.sh` exits 0
- [ ] Lint passes: `luacheck lua/ tests/` shows 0 warnings
- [ ] Format passes: `stylua --check lua/ tests/ plugin/` exits 0
- [ ] New behavior has tests (in the appropriate `tests/test_*.lua` file)
- [ ] If you added a user command or mapping, update `doc/waymark.txt`
- [ ] If you changed config options, update both `doc/waymark.txt` and
  `README.md` (the "All options" block)

## Writing tests

Tests use plenary.nvim's busted runner. Each module has a corresponding test
file in `tests/`. Follow the existing patterns:

- Call `helpers.reset()` and `config.setup({})` in `before_each`
- Use real temp files and real buffers (no mocks)
- One behavior per `it` block, named as a verb phrase
- Use `assert.equals(expected, actual)` (expected first)

Run a single file while developing:

```sh
./scripts/test.sh test_filter
```

## Commit messages

Use short imperative messages. Examples:

- `fix: prevent duplicate automark on bookmark line`
- `feat: add telescope integration example`
- `test: add extmark deduplication edge cases`
- `docs: expand troubleshooting FAQ`

## Reporting bugs

Please use the bug report template. Include `:checkhealth waymark` and
`:WaymarkDebug` output — it saves a round-trip.
