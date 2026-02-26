-- tests/minimal_init.lua
-- Minimal Neovim configuration for running tests in a headless instance.
-- Used by scripts/test.sh: nvim --headless -u tests/minimal_init.lua
--
-- This bootstraps plenary.nvim (downloading it if needed) and adds
-- the plugin under test to the runtimepath.

local uv = vim.uv or vim.loop

-- Where to store test dependencies
local test_deps = vim.fn.stdpath("data") .. "/waymark-test-deps"

-- Bootstrap plenary.nvim if not already present
local plenary_path = test_deps .. "/plenary.nvim"
if not uv.fs_stat(plenary_path) then
    print("Bootstrapping plenary.nvim...")
    vim.fn.system({
        "git",
        "clone",
        "--depth",
        "1",
        "https://github.com/nvim-lua/plenary.nvim.git",
        plenary_path,
    })
end

-- Add plenary and the plugin under test to the runtimepath
vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(vim.fn.getcwd())

-- Sensible test defaults
vim.o.swapfile = false
vim.o.backup = false
vim.o.writebackup = false
vim.o.undofile = false

-- Don't load default plugins (faster startup)
vim.g.loaded_matchit = 1
vim.g.loaded_matchparen = 1
vim.g.loaded_netrwPlugin = 1

vim.cmd("runtime plugin/plenary.vim")
