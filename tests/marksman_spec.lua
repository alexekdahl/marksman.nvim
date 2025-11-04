-- luacheck: globals describe it before_each after_each assert
local assert = require("luassert")

-- Helper to setup buffer with file
local function setup_buffer_with_file(filepath, content)
	vim.fn.writefile(content or { "test content" }, filepath)
	vim.cmd("edit " .. vim.fn.fnameescape(filepath))
	-- Ensure buffer is properly associated with file
	vim.api.nvim_buf_set_name(0, filepath)
	return filepath
end

-- Helper to clear all marks between tests
local function clear_marks()
	local storage = require("marksman.storage")
	storage.clear_all_marks()
end

describe("marksman.nvim", function()
	-- Global cleanup between all tests
	before_each(function()
		clear_marks()
	end)

	after_each(function()
		clear_marks()
	end)

	describe("setup", function()
		it("loads without errors", function()
			local marksman = require("marksman")
			assert.is_not_nil(marksman)
			assert.is_function(marksman.setup)
		end)

		it("has all required functions", function()
			local marksman = require("marksman")
			local required_functions = {
				"add_mark",
				"goto_mark",
				"delete_mark",
				"rename_mark",
				"show_marks",
				"search_marks",
				"get_marks",
				"get_marks_count",
			}

			for _, func_name in ipairs(required_functions) do
				assert.is_function(marksman[func_name], func_name .. " should be a function")
			end
		end)
	end)

	describe("mark operations", function()
		local marksman = require("marksman")
		local test_file
		local test_file2

		before_each(function()
			clear_marks()
			local test_dir = vim.env.MARKSMAN_TEST_DIR or vim.fn.tempname()
			test_file = test_dir .. "/test.lua"
			test_file2 = test_dir .. "/test2.lua"

			setup_buffer_with_file(test_file, {
				"local function test()",
				"  local value = false",
				"  if value then",
				"    return true",
				"  end",
				"  return false",
			})

			setup_buffer_with_file(test_file2, {
				"local function test2()",
				"  return false",
				"end",
			})
		end)

		it("adds a mark successfully", function()
			vim.cmd("edit " .. test_file)
			vim.fn.cursor(1, 1)

			local result = marksman.add_mark("test_mark")
			assert.is_true(result.success)
			assert.equals(1, marksman.get_marks_count())
		end)

		it("prevents duplicate mark names", function()
			vim.cmd("edit " .. test_file)
			vim.fn.cursor(1, 1)

			marksman.add_mark("duplicate")
			local result = marksman.add_mark("duplicate")

			assert.is_false(result.success)
			assert.matches("already exists", result.message)
		end)

		it("auto-generates mark names", function()
			vim.cmd("edit " .. test_file)
			vim.fn.cursor(1, 1)

			local result = marksman.add_mark()
			assert.is_true(result.success)
			assert.is_string(result.mark_name)
			assert.is_not_nil(result.mark_name:match("%w+"))
		end)

		it("validates mark names", function()
			vim.cmd("edit " .. test_file)

			local invalid_names = { "", "   ", string.rep("a", 60), "name/with\\invalid*chars" }

			for _, name in ipairs(invalid_names) do
				local result = marksman.add_mark(name)
				assert.is_false(result.success, "Should reject invalid name: " .. name)
			end
		end)

		it("jumps to marks correctly", function()
			vim.cmd("edit " .. test_file)
			vim.fn.cursor(2, 3)

			marksman.add_mark("jump_test")

			-- Move cursor away
			vim.fn.cursor(1, 1)

			local result = marksman.goto_mark("jump_test")
			assert.is_true(result.success)
			assert.equals(2, vim.fn.line("."))
			assert.equals(3, vim.fn.col("."))
		end)

		it("jumps to next mark with wrap-around", function()
			-- open the test file and place marks on lines 1, 2, and 3
			vim.cmd("edit " .. test_file)

			vim.fn.cursor(1, 1)
			marksman.add_mark("m1")

			vim.fn.cursor(2, 1)
			marksman.add_mark("m2")

			vim.fn.cursor(3, 1)
			marksman.add_mark("m3")

			-- start at m1
			vim.fn.cursor(1, 1)
			local result = marksman.goto_next()
			assert.is_true(result.success)
			assert.equals(2, vim.fn.line("."), "Should jump from m1 to m2")

			-- now at m2 -> next should be m3
			result = marksman.goto_next()
			assert.is_true(result.success)
			assert.equals(3, vim.fn.line("."), "Should jump from m2 to m3")

			-- now at m3 -> next should wrap back to m1
			result = marksman.goto_next()
			assert.is_true(result.success)
			assert.equals(1, vim.fn.line("."), "Should wrap from m3 to m1")
		end)

		it("jumps to next mark when cursor is between marks", function()
			vim.cmd("edit " .. test_file)

			vim.fn.cursor(1, 1)
			marksman.add_mark("m1")

			vim.fn.cursor(4, 1)
			marksman.add_mark("m2")

			vim.fn.cursor(5, 1)
			marksman.add_mark("m3")

			-- cursor on line 3 → distance to m1 = 2, m2 = 1 → choose m2 as current index
			vim.fn.cursor(3, 1)

			local result = marksman.goto_next()
			assert.is_true(result.success)
			assert.equals(5, vim.fn.line("."), "Should jump from m2 to m3")
		end)

		it("jumps to next in another file", function()
			-- file A
			vim.cmd("edit " .. test_file)
			vim.fn.cursor(1, 1)
			marksman.add_mark("a1")

			-- file B
			vim.cmd("edit " .. test_file2)
			vim.fn.cursor(1, 1)
			marksman.add_mark("b1")
			vim.fn.cursor(3, 1)
			marksman.add_mark("b2")

			vim.cmd("edit " .. test_file)
			vim.fn.cursor(1, 1) -- at a1
			local result = marksman.goto_next()

			assert.is_true(result.success)
			assert.equals(test_file2, vim.fn.expand("%:p"), "Should move to next mark in file2")
			assert.equals(1, vim.fn.line("."), "Should move to b1")
		end)

		it("jumps to second mark when current file has no marks", function()
			-- file A with marks
			vim.cmd("edit " .. test_file)
			vim.fn.cursor(1, 1)
			marksman.add_mark("m1")
			vim.fn.cursor(2, 1)
			marksman.add_mark("m2")

			-- file B with zero marks
			vim.cmd("edit " .. test_file2)
			vim.fn.cursor(1, 1)

			local result = marksman.goto_next()
			assert.is_true(result.success)

			-- Should jump to second mark because fallback picks first index
			assert.equals(test_file, vim.fn.expand("%:p"))
			assert.equals(2, vim.fn.line("."), "Should move to m2")
		end)

		it("jumps to first mark when only 1 mark exists", function()
			-- file A with marks
			vim.cmd("edit " .. test_file)
			vim.fn.cursor(1, 1)
			marksman.add_mark("m1")

			-- file B with zero marks
			vim.cmd("edit " .. test_file2)
			vim.fn.cursor(1, 1)

			local result = marksman.goto_next()
			assert.is_true(result.success)

			assert.equals(test_file, vim.fn.expand("%:p"))
			assert.equals(1, vim.fn.line("."), "Should move to m1")
		end)

		it("returns error when no marks exist", function()
			local result = marksman.goto_next()
			assert.is_false(result.success)
			assert.is_string(result.message)
		end)

		it("jumps to previous mark with wrap-around", function()
			vim.cmd("edit " .. test_file)

			vim.fn.cursor(1, 1)
			marksman.add_mark("m1")

			vim.fn.cursor(2, 1)
			marksman.add_mark("m2")

			vim.fn.cursor(3, 1)
			marksman.add_mark("m3")

			-- start at m1 -> previous should wrap to m3
			vim.fn.cursor(1, 1)
			local result = marksman.goto_previous()
			assert.is_true(result.success)
			assert.equals(3, vim.fn.line("."), "Should wrap from m1 to m3")

			-- now at m3 -> previous should be m2
			result = marksman.goto_previous()
			assert.is_true(result.success)
			assert.equals(2, vim.fn.line("."), "Should jump from m3 to m2")

			-- now at m2 -> previous should be m1
			result = marksman.goto_previous()
			assert.is_true(result.success)
			assert.equals(1, vim.fn.line("."), "Should jump from m2 to m1")
		end)

		it("deletes marks", function()
			vim.cmd("edit " .. test_file)
			marksman.add_mark("delete_me")

			assert.equals(1, marksman.get_marks_count())

			local result = marksman.delete_mark("delete_me")
			assert.is_true(result.success)
			assert.equals(0, marksman.get_marks_count())
		end)

		it("renames marks", function()
			vim.cmd("edit " .. test_file)
			marksman.add_mark("old_name")

			local result = marksman.rename_mark("old_name", "new_name")
			assert.is_true(result.success)

			local marks = marksman.get_marks()
			assert.is_nil(marks["old_name"])
			assert.is_not_nil(marks["new_name"])
		end)

		it("handles non-existent marks gracefully", function()
			local result = marksman.goto_mark("nonexistent")
			assert.is_false(result.success)

			result = marksman.delete_mark("nonexistent")
			assert.is_false(result.success)
		end)

		-- Test case for the clear all marks bug fix
		-- This ensures that clearing all marks through the UI properly persists the changes
		it("clears all marks and persists changes", function()
			vim.cmd("edit " .. test_file)

			-- Add multiple marks at different positions
			marksman.add_mark("mark1")
			vim.fn.cursor(2, 1)
			marksman.add_mark("mark2")
			vim.fn.cursor(3, 1)
			marksman.add_mark("mark3")

			-- Verify marks were added
			assert.equals(3, marksman.get_marks_count())

			-- Mock vim.ui.select to automatically confirm the clear action
			local original_select = vim.ui.select
			vim.ui.select = function(choices, opts, callback)
				if opts.prompt == "Clear all marks in this project?" then
					callback("Yes") -- Simulate user selecting "Yes"
				end
			end

			-- Clear all marks (this should trigger the save mechanism)
			marksman.clear_all_marks()

			-- Restore original function
			vim.ui.select = original_select

			-- Verify marks were cleared immediately
			assert.equals(0, marksman.get_marks_count())

			-- Wait for any debounced save operations to complete
			vim.wait(200)

			-- Verify marks remain cleared after save delay
			assert.equals(0, marksman.get_marks_count(), "Marks should remain cleared after debounced save")
		end)
	end)

	describe("mark search and filtering", function()
		local marksman = require("marksman")

		it("searches marks by name", function()
			-- Create a single test file and mark
			local test_dir = vim.env.MARKSMAN_TEST_DIR or vim.fn.tempname()
			local filepath = test_dir .. "/search_test.lua"
			vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")

			setup_buffer_with_file(filepath, { "function search_test()", "  return true", "end" })
			vim.fn.cursor(1, 1)

			local result = marksman.add_mark("search_mark")
			assert.is_true(result.success, "Failed to add search mark: " .. (result.message or "unknown"))

			local results = marksman.search_marks("search")
			assert.equals(1, vim.tbl_count(results))
			assert.is_not_nil(results["search_mark"])
		end)

		it("searches marks by file content", function()
			local test_dir = vim.env.MARKSMAN_TEST_DIR or vim.fn.tempname()
			local filepath = test_dir .. "/content_test.lua"
			vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")

			setup_buffer_with_file(filepath, { "function content_function()", "  return data", "end" })
			vim.fn.cursor(1, 1)

			local result = marksman.add_mark("content_mark")
			assert.is_true(result.success, "Failed to add content mark: " .. (result.message or "unknown"))

			local results = marksman.search_marks("function")
			assert.is_true(vim.tbl_count(results) >= 1)
		end)

		it("returns empty for no matches", function()
			local results = marksman.search_marks("nonexistent_term")
			assert.equals(0, vim.tbl_count(results))
		end)
	end)

	describe("storage and persistence", function()
		local storage = require("marksman.storage")

		it("maintains mark order", function()
			local marksman = require("marksman")
			local test_dir = vim.env.MARKSMAN_TEST_DIR or vim.fn.tempname()
			local test_file = test_dir .. "/order_test.lua"
			vim.fn.mkdir(vim.fn.fnamemodify(test_file, ":h"), "p")

			setup_buffer_with_file(test_file, { "test content" })

			marksman.add_mark("first")
			marksman.add_mark("second")
			marksman.add_mark("third")

			local names = storage.get_mark_names()
			assert.equals("first", names[1])
			assert.equals("second", names[2])
			assert.equals("third", names[3])
		end)

		it("moves marks up and down", function()
			local marksman = require("marksman")
			local test_dir = vim.env.MARKSMAN_TEST_DIR or vim.fn.tempname()
			local test_file = test_dir .. "/move_test.lua"
			vim.fn.mkdir(vim.fn.fnamemodify(test_file, ":h"), "p")

			setup_buffer_with_file(test_file, { "test content" })

			marksman.add_mark("first")
			marksman.add_mark("second")

			local result = marksman.move_mark("second", "up")
			assert.is_true(result.success)

			local names = storage.get_mark_names()
			assert.equals("second", names[1])
			assert.equals("first", names[2])
		end)

		it("respects max marks limit", function()
			local marksman = require("marksman")
			marksman.setup({ max_marks = 2, silent = true })

			local test_dir = vim.env.MARKSMAN_TEST_DIR or vim.fn.tempname()
			local test_file = test_dir .. "/limit_test.lua"
			vim.fn.mkdir(vim.fn.fnamemodify(test_file, ":h"), "p")

			setup_buffer_with_file(test_file, { "test content" })

			marksman.add_mark("mark1")
			marksman.add_mark("mark2")

			local result = marksman.add_mark("mark3")
			assert.is_false(result.success)
			assert.matches("Maximum marks limit", result.message)
		end)
	end)

	describe("utils", function()
		local utils = require("marksman.utils")

		it("validates mark names correctly", function()
			local valid_names = { "test", "mark_1", "function_name", "a" }
			local invalid_names = { "", "   ", string.rep("a", 60), "bad/name", "bad\\name" }

			for _, name in ipairs(valid_names) do
				local valid, _ = utils.validate_mark_name(name)
				assert.is_true(valid, "Should accept valid name: " .. name)
			end

			for _, name in ipairs(invalid_names) do
				local valid, _ = utils.validate_mark_name(name)
				assert.is_false(valid, "Should reject invalid name: " .. name)
			end
		end)

		it("generates smart mark names", function()
			-- Mock vim.fn.getline to simulate different code contexts
			local original_getline = vim.fn.getline

			local test_cases = {
				{ line = "function test_func()", expected_pattern = "fn:" },
				{ line = "class TestClass {", expected_pattern = "class:" },
				{ line = "const myVar = 5;", expected_pattern = "var:" },
			}

			for _, case in ipairs(test_cases) do
				vim.fn.getline = function()
					return case.line
				end

				local name = utils.generate_mark_name("test.js", 1)
				assert.matches(case.expected_pattern, name)
			end

			vim.fn.getline = original_getline
		end)

		it("filters marks correctly", function()
			local marks = {
				api_func = { file = "/api.lua", line = 1, col = 1, text = "api function" },
				user_model = { file = "/user.lua", line = 2, col = 1, text = "user model" },
				helper_util = { file = "/helper.js", line = 3, col = 1, text = "helper utility" },
			}

			-- Test single term search
			local filtered = utils.filter_marks(marks, "api")
			assert.equals(1, vim.tbl_count(filtered))
			assert.is_not_nil(filtered["api_func"])

			-- Test individual terms
			filtered = utils.filter_marks(marks, "user")
			assert.equals(1, vim.tbl_count(filtered))
			assert.is_not_nil(filtered["user_model"])

			filtered = utils.filter_marks(marks, "helper")
			assert.equals(1, vim.tbl_count(filtered))
			assert.is_not_nil(filtered["helper_util"])
		end)
	end)
end)
