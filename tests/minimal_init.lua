-- Minimal init file for testing
-- This sets up the minimal environment needed to test the plugin

-- Add current directory to runtimepath
vim.opt.rtp:prepend(".")

-- Add plenary.nvim for testing framework
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
	vim.opt.rtp:prepend(plenary_path)
else
	error("plenary.nvim not found at " .. plenary_path)
end

-- Basic vim settings needed for testing
vim.o.swapfile = false
vim.o.backup = false

-- Disable some features that might interfere with testing
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Set up a temporary directory for test files
local temp_dir = vim.fn.tempname() .. "_marksman_test"
vim.fn.mkdir(temp_dir, "p")
vim.env.MARKSMAN_TEST_DIR = temp_dir

-- Initialize the plugin
require("marksman").setup({
	auto_save = false, -- Disable auto-save for tests
	silent = true, -- Suppress notifications during tests
	max_marks = 100,
	debounce_ms = 100, -- Minimum allowed value
})
