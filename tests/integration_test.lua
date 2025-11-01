-- Set up runtime path for the plugin
vim.opt.runtimepath:prepend(".")
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

local abs_path = vim.fn.getcwd() .. "/lua"
package.path = package.path .. ";" .. abs_path .. "/?.lua;" .. abs_path .. "/?/init.lua"

local test_count = 0
local pass_count = 0

local function test(name, func)
	test_count = test_count + 1
	local ok, err = pcall(func)
	if ok then
		pass_count = pass_count + 1
		print("✓ " .. name)
	else
		print("✗ " .. name .. ": " .. tostring(err))
	end
end

local function assert_eq(actual, expected, msg)
	if actual ~= expected then
		error(msg or string.format("Expected %s, got %s", tostring(expected), tostring(actual)))
	end
end

local function assert_true(condition, msg)
	if not condition then
		error(msg or "Expected true")
	end
end

-- Set up isolated test environment
local function setup_test()
	local temp_dir = vim.fn.tempname() .. "_test"
	vim.fn.mkdir(temp_dir, "p")
	vim.fn.mkdir(temp_dir .. "/.git", "p")

	local original_cwd = vim.fn.getcwd()
	vim.cmd("cd " .. temp_dir)

	-- Clear module cache
	for name, _ in pairs(package.loaded) do
		if name:match("^marksman") then
			package.loaded[name] = nil
		end
	end

	return temp_dir, original_cwd
end

local function cleanup_test(temp_dir, original_cwd)
	vim.cmd("cd " .. original_cwd)
	vim.fn.delete(temp_dir, "rf")
end

-- Core functionality tests
print("Running Marksman.nvim tests...")

-- Storage tests
local temp_dir, original_cwd = setup_test()

test("storage basic operations", function()
	local storage = require("marksman.storage")
	storage.setup({ auto_save = true, silent = true })

	-- Should start empty
	assert_eq(storage.get_marks_count(), 0, "Should start with 0 marks")

	-- Add mark
	local mark = { file = temp_dir .. "/test.lua", line = 10, col = 5, text = "test" }
	assert_true(storage.add_mark("test", mark), "Should add mark")
	assert_eq(storage.get_marks_count(), 1, "Should have 1 mark")

	-- Get marks
	local marks = storage.get_marks()
	assert_true(marks["test"] ~= nil, "Mark should exist")
	assert_eq(marks["test"].line, 10, "Line should match")
end)

test("storage delete and rename", function()
	-- Force fresh storage instance
	package.loaded["marksman.storage"] = nil
	local storage = require("marksman.storage")
	storage.setup({ auto_save = true, silent = true })

	-- Ensure clean state
	storage.clear_all_marks()

	local mark = { file = temp_dir .. "/test.lua", line = 5, col = 1, text = "test" }
	storage.add_mark("delete_me", mark)

	assert_eq(storage.get_marks_count(), 1, "Should have 1 mark before delete")
	assert_true(storage.delete_mark("delete_me"), "Should delete mark")
	assert_eq(storage.get_marks_count(), 0, "Should be empty after delete")

	storage.add_mark("old_name", mark)
	assert_true(storage.rename_mark("old_name", "new_name"), "Should rename mark")

	local marks = storage.get_marks()
	assert_true(marks["new_name"] ~= nil, "New name should exist")
	assert_true(marks["old_name"] == nil, "Old name should not exist")
end)

cleanup_test(temp_dir, original_cwd)

-- Utils tests
test("utils mark name generation", function()
	local utils = require("marksman.utils")

	-- Mock vim functions
	local orig_getline = vim.fn.getline
	local orig_fnamemodify = vim.fn.fnamemodify

	vim.fn.getline = function()
		return "function test_func()"
	end
	vim.fn.fnamemodify = function(path, mod)
		if mod == ":t:r" then
			return "testfile"
		end
		if mod == ":e" then
			return "lua"
		end
		return path
	end

	local name = utils.generate_mark_name("/test.lua", 10)
	assert_true(name:match("fn:test_func") or name:match("testfile"), "Should generate appropriate name")

	vim.fn.getline = orig_getline
	vim.fn.fnamemodify = orig_fnamemodify
end)

test("utils mark filtering", function()
	local utils = require("marksman.utils")

	local marks = {
		api_func = { file = "/api.lua", line = 1, col = 1, text = "api function" },
		user_model = { file = "/user.lua", line = 2, col = 1, text = "user model" },
	}

	local filtered = utils.filter_marks(marks, "api")
	assert_eq(vim.tbl_count(filtered), 1, "Should find 1 mark")
	assert_true(filtered["api_func"] ~= nil, "Should find api_func")
end)

-- Main module tests
temp_dir, original_cwd = setup_test()

test("marksman basic workflow", function()
	local marksman = require("marksman")
	marksman.setup({ auto_save = true, silent = true })

	-- Create test file
	local test_file = temp_dir .. "/test.lua"
	vim.fn.writefile({ "local function test()", "  return true", "end" }, test_file)

	vim.cmd("edit " .. test_file)
	vim.fn.cursor(1, 1)

	assert_true(marksman.add_mark("test_mark"), "Should add mark")
	assert_eq(marksman.get_marks_count(), 1, "Should have 1 mark")

	assert_true(marksman.goto_mark("test_mark"), "Should go to mark")
	assert_eq(vim.fn.line("."), 1, "Should be on correct line")

	assert_true(marksman.delete_mark("test_mark"), "Should delete mark")
	assert_eq(marksman.get_marks_count(), 0, "Should be empty")
end)

cleanup_test(temp_dir, original_cwd)

-- Ensure we're back in the original directory
vim.cmd("cd " .. vim.fn.expand("~"))

-- Report results
print(string.format("\nResults: %d/%d tests passed", pass_count, test_count))
if pass_count == test_count then
	print("All tests passed!")
else
	print(string.format("%d tests failed", test_count - pass_count))
	os.exit(1)
end
