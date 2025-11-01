-- luacheck: globals vim
local M = {}

local config = {}
local current_window = nil
local current_buffer = nil

-- Helper function for conditional notifications
local function notify(message, level)
	if not config.silent then
		vim.notify(message, level)
	end
end

local function setup_highlights()
	for name, attrs in pairs(config.highlights) do
		vim.api.nvim_set_hl(0, name, attrs)
	end
end

local function get_icon_for_file(filename)
	local extension = vim.fn.fnamemodify(filename, ":e")
	local icons = {
		lua = "",
		py = "",
		js = "",
		ts = "",
		jsx = "",
		tsx = "",
		vue = "﵂",
		go = "",
		rs = "",
		c = "",
		cpp = "",
		h = "",
		hpp = "",
		java = "",
		kt = "󱈙",
		cs = "󰌛",
		rb = "",
		php = "",
		html = "",
		css = "",
		scss = "",
		json = "",
		yaml = "",
		yml = "",
		toml = "",
		xml = "󰗀",
		md = "",
		txt = "",
		vim = "",
		sh = "",
		fish = "󰈺",
		zsh = "",
		bash = "",
	}
	return icons[extension] or ""
end

local function close_window()
	if current_window and vim.api.nvim_win_is_valid(current_window) then
		vim.api.nvim_win_close(current_window, true)
		current_window = nil
		current_buffer = nil
	end
end

local function get_relative_path_display(filepath)
	-- Show relative path from current working directory
	local rel_path = vim.fn.fnamemodify(filepath, ":~:.")
	-- If the path is still too long, show parent directory + filename
	if #rel_path > 50 then
		local parent = vim.fn.fnamemodify(filepath, ":h:t")
		local filename = vim.fn.fnamemodify(filepath, ":t")
		return parent .. "/" .. filename
	end
	return rel_path
end

local function create_marks_content(marks, search_query)
	local lines = {}
	local highlights = {}
	local mark_info = {} -- Store mark data for each line

	-- Get ordered mark names from storage
	local storage = require("marksman.storage")
	local mark_names = storage.get_mark_names()

	-- Filter marks if search query provided
	local filtered_names = {}
	if search_query and search_query ~= "" then
		search_query = search_query:lower()
		for _, name in ipairs(mark_names) do
			local mark = marks[name]
			if mark then
				local searchable = (name .. " " .. vim.fn.fnamemodify(mark.file, ":t") .. " " .. (mark.text or "")):lower()
				if searchable:find(search_query, 1, true) then
					table.insert(filtered_names, name)
				end
			end
		end
	else
		filtered_names = mark_names
	end

	if config.minimal then
		if #filtered_names == 0 then
			table.insert(lines, " No marks")
			return lines, highlights, {}
		end

		for i, name in ipairs(filtered_names) do
			local mark = marks[name]
			local filepath = get_relative_path_display(mark.file)
			local line = string.format("[%d] %s %s", i, name, filepath)
			table.insert(lines, line)

			local line_idx = #lines - 1
			mark_info[line_idx] = { name = name, mark = mark, index = i }

			local number_part = string.format("[%d]", i)
			local name_start = string.len(number_part) + 1
			local name_end = name_start + string.len(name)

			-- Highlight the number
			table.insert(highlights, {
				line = line_idx,
				col = 0,
				end_col = string.len(number_part),
				hl_group = "ProjectMarksNumber",
			})
			-- Highlight the name
			table.insert(highlights, {
				line = line_idx,
				col = name_start,
				end_col = name_end,
				hl_group = "ProjectMarksName",
			})
			-- Highlight the filepath
			table.insert(highlights, {
				line = line_idx,
				col = name_end + 1,
				end_col = -1,
				hl_group = "ProjectMarksFile",
			})
		end

		return lines, highlights, mark_info
	end

	-- Header
	local title = search_query
			and search_query ~= ""
			and string.format(" 󰃀 Project Marks (filtered: %s) ", search_query)
		or " 󰃀 Project Marks "
	table.insert(lines, title)
	table.insert(highlights, { line = 0, col = 0, end_col = -1, hl_group = "ProjectMarksTitle" })
	table.insert(lines, "")

	-- Stats line
	local total_marks = vim.tbl_count(marks)
	local shown_marks = #filtered_names
	local stats_line = string.format(" Showing %d of %d marks", shown_marks, total_marks)
	table.insert(lines, stats_line)
	table.insert(highlights, { line = 2, col = 0, end_col = -1, hl_group = "ProjectMarksHelp" })
	table.insert(lines, "")

	-- Help text
	local help_lines = {
		" <CR>/1-9: Jump  d: Delete  r: Rename  /: Search",
		" J/K: Move up/down  C: Clear all  q: Close",
	}
	for _, help_line in ipairs(help_lines) do
		table.insert(lines, help_line)
		table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "ProjectMarksHelp" })
	end
	table.insert(lines, "")

	if #filtered_names == 0 then
		local no_marks_line = search_query and search_query ~= "" and " No marks found matching search"
			or " No marks in this project"
		table.insert(lines, no_marks_line)
		table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "ProjectMarksText" })
		return lines, highlights, {}
	end

	for i, name in ipairs(filtered_names) do
		local mark = marks[name]
		local icon = get_icon_for_file(mark.file)
		local rel_path = get_relative_path_display(mark.file)

		local number = string.format("[%d]", i)
		local name_part = icon .. " " .. name
		local file_part = rel_path .. ":" .. mark.line

		-- Main line with mark name
		local line = string.format("%s %s", number, name_part)
		table.insert(lines, line)

		local line_idx = #lines - 1
		mark_info[line_idx] = { name = name, mark = mark, index = i }

		table.insert(highlights, {
			line = line_idx,
			col = 0,
			end_col = #number,
			hl_group = "ProjectMarksNumber",
		})
		table.insert(highlights, {
			line = line_idx,
			col = #number + 1,
			end_col = #number + 1 + #name_part,
			hl_group = "ProjectMarksName",
		})

		-- Preview text
		local preview = "   │ " .. (mark.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if #preview > 80 then
			preview = preview:sub(1, 77) .. "..."
		end
		table.insert(lines, preview)
		table.insert(highlights, {
			line = #lines - 1,
			col = 0,
			end_col = -1,
			hl_group = "ProjectMarksText",
		})

		-- File info
		local info = string.format("   └─ %s", file_part)
		table.insert(lines, info)
		table.insert(highlights, {
			line = #lines - 1,
			col = 6,
			end_col = 6 + #file_part,
			hl_group = "ProjectMarksFile",
		})

		table.insert(lines, "")
	end

	return lines, highlights, mark_info
end

local function get_mark_under_cursor(mark_info)
	local line = vim.fn.line(".")

	-- Find the closest mark info
	local closest_mark = nil
	local closest_distance = math.huge

	for line_idx, info in pairs(mark_info) do
		local distance = math.abs(line - (line_idx + 1)) -- +1 for 1-indexed
		if distance < closest_distance then
			closest_distance = distance
			closest_mark = info
		end
	end

	return closest_mark
end

local function setup_window_keymaps(buf, marks, project_name, mark_info, search_query)
	local function refresh_window(new_search)
		local storage = require("marksman.storage")
		local fresh_marks = storage.get_marks()
		M.show_marks_window(fresh_marks, project_name, new_search)
	end

	local function goto_selected()
		local mark_info_item = get_mark_under_cursor(mark_info)
		if mark_info_item then
			close_window()
			local marksman = require("marksman")
			marksman.goto_mark(mark_info_item.name)
		end
	end

	local function delete_selected()
		local mark_info_item = get_mark_under_cursor(mark_info)
		if mark_info_item then
			local marksman = require("marksman")
			marksman.delete_mark(mark_info_item.name)
			-- Force immediate refresh
			vim.schedule(function()
				refresh_window(search_query)
			end)
		end
	end

	local function rename_selected()
		local mark_info_item = get_mark_under_cursor(mark_info)
		if mark_info_item then
			vim.ui.input({
				prompt = "New name: ",
				default = mark_info_item.name,
			}, function(new_name)
				if new_name and new_name ~= "" and new_name ~= mark_info_item.name then
					local marksman = require("marksman")
					marksman.rename_mark(mark_info_item.name, new_name)
					refresh_window(search_query)
				end
			end)
		end
	end

	local function move_selected(direction)
		local mark_info_item = get_mark_under_cursor(mark_info)
		if mark_info_item then
			local marksman = require("marksman")
			marksman.move_mark(mark_info_item.name, direction)
			refresh_window(search_query)
		end
	end

	local function search_marks()
		vim.ui.input({
			prompt = "Search: ",
			default = search_query or "",
		}, function(query)
			if query ~= nil then
				refresh_window(query)
			end
		end)
	end

	local function clear_all_marks()
		vim.ui.select({ "Yes", "No" }, {
			prompt = "Clear all marks in this project?",
		}, function(choice)
			if choice == "Yes" then
				local storage = require("marksman.storage")
				storage.clear_all_marks()
				close_window()
				notify("󰃀 All marks cleared", vim.log.levels.INFO)
			end
		end)
	end

	local keymap_opts = { buffer = buf, noremap = true, silent = true }

	-- Basic navigation
	vim.keymap.set("n", "q", close_window, keymap_opts)
	vim.keymap.set("n", "<Esc>", close_window, keymap_opts)
	vim.keymap.set("n", "<CR>", goto_selected, keymap_opts)

	-- Mark operations
	vim.keymap.set("n", "d", delete_selected, keymap_opts)
	vim.keymap.set("n", "r", rename_selected, keymap_opts)
	vim.keymap.set("n", "/", search_marks, keymap_opts)
	vim.keymap.set("n", "C", clear_all_marks, keymap_opts)

	-- Reordering
	vim.keymap.set("n", "J", function()
		move_selected("down")
	end, keymap_opts)
	vim.keymap.set("n", "K", function()
		move_selected("up")
	end, keymap_opts)

	-- Number key navigation
	for i = 1, 9 do
		vim.keymap.set("n", tostring(i), function()
			-- Find mark with index i
			for _, info in pairs(mark_info) do
				if info.index == i then
					close_window()
					local marksman = require("marksman")
					marksman.goto_mark(info.name)
					return
				end
			end
		end, keymap_opts)
	end
end

function M.setup(user_config)
	config = user_config or {}
	setup_highlights()
end

function M.show_marks_window(marks, project_name, search_query)
	-- Close existing window
	close_window()

	setup_highlights()

	local lines, highlights, mark_info = create_marks_content(marks, search_query)

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].filetype = "marksman"

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_add_highlight(buf, -1, hl.hl_group, hl.line, hl.col, hl.end_col)
	end

	-- Calculate window size
	local width = math.min(120, vim.o.columns - 10)
	local height = math.min(#lines + 2, vim.o.lines - 6)

	-- Window options
	local title = " " .. (project_name or "Project") .. " "
	if search_query and search_query ~= "" then
		title = title .. "(filtered) "
	end

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = (vim.o.lines - height) / 2,
		col = (vim.o.columns - width) / 2,
		border = "rounded",
		style = "minimal",
		title = title,
		title_pos = "center",
	}

	-- Create window
	local win = vim.api.nvim_open_win(buf, true, opts)
	current_window = win
	current_buffer = buf

	-- Set window highlight
	vim.api.nvim_win_set_option(win, "winhighlight", "Normal:Normal,FloatBorder:ProjectMarksBorder")

	-- Setup keymaps
	setup_window_keymaps(buf, marks, project_name, mark_info, search_query)

	-- Position cursor on first mark if available
	if not vim.tbl_isempty(mark_info) then
		local first_mark_line = math.huge
		for line_idx, _ in pairs(mark_info) do
			if line_idx < first_mark_line then
				first_mark_line = line_idx
			end
		end
		if first_mark_line ~= math.huge then
			vim.fn.cursor(first_mark_line + 1, 1) -- +1 for 1-indexed
		end
	end
end

function M.show_search_results(results, query)
	if vim.tbl_isempty(results) then
		notify("No marks found matching: " .. query, vim.log.levels.INFO)
		return
	end

	M.show_marks_window(results, "Search Results", query)
end

return M
