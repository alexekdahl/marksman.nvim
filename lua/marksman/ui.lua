-- luacheck: globals vim
---@class UI
---@field config table Plugin configuration
---@field current_window number|nil Current window handle
---@field current_buffer number|nil Current buffer handle
local M = {}

local config = {}
local current_window = nil
local current_buffer = nil

-- File icon mapping for better visual display
local file_icons = {
	lua = "󰢱",
	py = "󰌠",
	js = "󰌞",
	ts = "󰛦",
	jsx = "󰜈",
	tsx = "󰛦",
	vue = "󰡄",
	go = "󰟓",
	rs = "󱘗",
	c = "",
	cpp = "󰙱",
	h = "󰟔",
	hpp = "󰙲",
	java = "󰬷",
	kt = "󱈙",
	cs = "󰌛",
	rb = "󰴭",
	php = "󰌟",
	html = "󰌝",
	css = "󰌜",
	scss = "󰛓",
	json = "󰘓",
	yaml = "󰈙",
	yml = "󰈙",
	toml = "󰈙",
	xml = "󰗀",
	md = "󰍔",
	txt = "󰈙",
	vim = "",
	sh = "󰘳",
	fish = "󰈺",
	zsh = "󰰶",
	bash = "󰘳",
}

---Helper function for conditional notifications
---@param message string The notification message
---@param level number The log level
local function notify(message, level)
	if not config.silent then
		vim.notify(message, level)
	end
end

---Setup highlight groups
local function setup_highlights()
	for name, attrs in pairs(config.highlights or {}) do
		vim.api.nvim_set_hl(0, name, attrs)
	end
end

---Get appropriate icon for file extension
---@param filename string File path
---@return string icon File icon
local function get_icon_for_file(filename)
	local extension = vim.fn.fnamemodify(filename, ":e"):lower()
	return file_icons[extension] or ""
end

---Close the current marks window
local function close_window()
	if current_window and vim.api.nvim_win_is_valid(current_window) then
		pcall(vim.api.nvim_win_close, current_window, true)
		current_window = nil
		current_buffer = nil
	end
end

---Get relative path display for better readability
---@param filepath string Full file path
---@return string relative_path Formatted relative path
local function get_relative_path_display(filepath)
	local rel_path = vim.fn.fnamemodify(filepath, ":~:.")

	-- If path is too long, show parent directory + filename
	if #rel_path > 50 then
		local parent = vim.fn.fnamemodify(filepath, ":h:t")
		local filename = vim.fn.fnamemodify(filepath, ":t")
		return parent .. "/" .. filename
	end
	return rel_path
end

---Create header content for marks window
---@param total_marks number Total number of marks
---@param shown_marks number Number of marks shown
---@param search_query string|nil Search query if any
---@return table lines Array of header lines
---@return table highlights Array of highlight definitions
local function create_header_content(total_marks, shown_marks, search_query)
	local lines = {}
	local highlights = {}

	-- Title
	local title = search_query
			and search_query ~= ""
			and string.format(" 󰃀 Project Marks (filtered: %s) ", search_query)
		or " 󰃀 Project Marks "
	table.insert(lines, title)
	table.insert(highlights, { line = 0, col = 0, end_col = -1, hl_group = "ProjectMarksTitle" })
	table.insert(lines, "")

	-- Stats
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

	return lines, highlights
end

---Create minimal mark display line
---@param name string Mark name
---@param mark table Mark data
---@param index number Mark index
---@return string line Formatted line
---@return table highlights Array of highlight definitions for this line
local function create_minimal_mark_line(name, mark, index, line_idx)
	local filepath = get_relative_path_display(mark.file)
	local line = string.format("[%d] %s %s", index, name, filepath)

	local highlights = {}
	local number_part = string.format("[%d]", index)
	local name_start = #number_part + 1
	local name_end = name_start + #name

	-- Number highlight
	table.insert(highlights, {
		line = line_idx,
		col = 0,
		end_col = #number_part,
		hl_group = "ProjectMarksNumber",
	})

	-- Name highlight
	table.insert(highlights, {
		line = line_idx,
		col = name_start,
		end_col = name_end,
		hl_group = "ProjectMarksName",
	})

	-- File path highlight
	table.insert(highlights, {
		line = line_idx,
		col = name_end + 1,
		end_col = -1,
		hl_group = "ProjectMarksFile",
	})

	return line, highlights
end

---Create detailed mark display lines
---@param name string Mark name
---@param mark table Mark data
---@param index number Mark index
---@param line_idx number Starting line index
---@return table lines Array of lines for this mark
---@return table highlights Array of highlight definitions
local function create_detailed_mark_lines(name, mark, index, line_idx)
	local lines = {}
	local highlights = {}
	local icon = get_icon_for_file(mark.file)
	local rel_path = get_relative_path_display(mark.file)

	local number = string.format("[%d]", index)
	local name_part = icon .. " " .. name
	local file_part = rel_path .. ":" .. mark.line

	-- Main line with mark name
	local main_line = string.format("%s %s", number, name_part)
	table.insert(lines, main_line)

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
		line = line_idx + 1,
		col = 0,
		end_col = -1,
		hl_group = "ProjectMarksText",
	})

	-- File info
	local info = string.format("   └─ %s", file_part)
	table.insert(lines, info)
	table.insert(highlights, {
		line = line_idx + 2,
		col = 6,
		end_col = 6 + #file_part,
		hl_group = "ProjectMarksFile",
	})

	table.insert(lines, "")

	return lines, highlights
end

---Create complete marks window content
---@param marks table All marks data
---@param search_query string|nil Optional search query
---@return table lines Array of content lines
---@return table highlights Array of highlight definitions
---@return table mark_info Mapping of line numbers to mark info
local function create_marks_content(marks, search_query)
	local lines = {}
	local highlights = {}
	local mark_info = {}

	-- Get ordered mark names from storage
	local storage = require("marksman.storage")
	local mark_names = storage.get_mark_names()

	-- Filter marks if search query provided
	local filtered_names = {}
	if search_query and search_query ~= "" then
		local utils = require("marksman.utils")
		local filtered_marks = utils.filter_marks(marks, search_query)
		for _, name in ipairs(mark_names) do
			if filtered_marks[name] then
				table.insert(filtered_names, name)
			end
		end
	else
		filtered_names = mark_names
	end

	local total_marks = vim.tbl_count(marks)
	local shown_marks = #filtered_names

	-- Handle minimal mode
	if config.minimal then
		if shown_marks == 0 then
			table.insert(lines, " No marks")
			return lines, highlights, {}
		end

		for i, name in ipairs(filtered_names) do
			local mark = marks[name]
			local line_idx = #lines
			local line, line_highlights = create_minimal_mark_line(name, mark, i, line_idx)

			table.insert(lines, line)
			mark_info[line_idx] = { name = name, mark = mark, index = i }

			for _, hl in ipairs(line_highlights) do
				table.insert(highlights, hl)
			end
		end

		return lines, highlights, mark_info
	end

	-- Create header
	local header_lines, header_highlights = create_header_content(total_marks, shown_marks, search_query)
	for _, line in ipairs(header_lines) do
		table.insert(lines, line)
	end
	for _, hl in ipairs(header_highlights) do
		table.insert(highlights, hl)
	end

	-- Handle no marks case
	if shown_marks == 0 then
		local no_marks_line = search_query and search_query ~= "" and " No marks found matching search"
			or " No marks in this project"
		table.insert(lines, no_marks_line)
		table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "ProjectMarksText" })
		return lines, highlights, {}
	end

	-- Create detailed mark entries
	for i, name in ipairs(filtered_names) do
		local mark = marks[name]
		local start_line_idx = #lines
		local mark_lines, mark_highlights = create_detailed_mark_lines(name, mark, i, start_line_idx)

		mark_info[start_line_idx] = { name = name, mark = mark, index = i }

		for _, line in ipairs(mark_lines) do
			table.insert(lines, line)
		end
		for _, hl in ipairs(mark_highlights) do
			table.insert(highlights, hl)
		end
	end

	return lines, highlights, mark_info
end

---Find mark information for current cursor position
---@param mark_info table Mapping of line numbers to mark info
---@return table|nil mark_info Mark info for cursor position
local function get_mark_under_cursor(mark_info)
	local line = vim.fn.line(".")
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

---Setup keymaps for marks window
---@param buf number Buffer handle
---@param marks table Marks data
---@param project_name string Project name
---@param mark_info table Mark info mapping
---@param search_query string|nil Search query
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
			local result = marksman.goto_mark(mark_info_item.name)
			if not result.success then
				notify(result.message, vim.log.levels.WARN)
			end
		end
	end

	local function delete_selected()
		local mark_info_item = get_mark_under_cursor(mark_info)
		if mark_info_item then
			local marksman = require("marksman")
			local result = marksman.delete_mark(mark_info_item.name)
			if result.success then
				vim.schedule(function()
					refresh_window(search_query)
				end)
			else
				notify(result.message, vim.log.levels.WARN)
			end
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
					local result = marksman.rename_mark(mark_info_item.name, new_name)
					if result.success then
						refresh_window(search_query)
					else
						notify(result.message, vim.log.levels.WARN)
					end
				end
			end)
		end
	end

	local function move_selected(direction)
		local mark_info_item = get_mark_under_cursor(mark_info)
		if mark_info_item then
			local marksman = require("marksman")
			local result = marksman.move_mark(mark_info_item.name, direction)
			if result.success then
				refresh_window(search_query)
			else
				notify(result.message, vim.log.levels.WARN)
			end
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
			for _, info in pairs(mark_info) do
				if info.index == i then
					close_window()
					local marksman = require("marksman")
					local result = marksman.goto_mark(info.name)
					if not result.success then
						notify(result.message, vim.log.levels.WARN)
					end
					return
				end
			end
		end, keymap_opts)
	end
end

---Calculate optimal window dimensions
---@param content_lines table Array of content lines
---@return table dimensions Window dimensions and position
local function calculate_window_dimensions(content_lines)
	local max_width = 120
	local max_height = vim.o.lines - 6

	-- Calculate content width
	local content_width = 0
	for _, line in ipairs(content_lines) do
		content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
	end

	local width = math.min(math.max(content_width + 4, 60), max_width)
	local height = math.min(#content_lines + 2, max_height)

	return {
		width = width,
		height = height,
		row = (vim.o.lines - height) / 2,
		col = (vim.o.columns - width) / 2,
	}
end

-- Public API

---Setup the UI module
---@param user_config table Plugin configuration
function M.setup(user_config)
	config = user_config or {}
	setup_highlights()
end

---Show marks in floating window
---@param marks table Marks data
---@param project_name string Project name
---@param search_query string|nil Optional search query
function M.show_marks_window(marks, project_name, search_query)
	-- Close existing window
	close_window()

	-- Refresh highlights
	setup_highlights()

	-- Create content
	local lines, highlights, mark_info = create_marks_content(marks, search_query)

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	if not buf or buf == 0 then
		notify("Failed to create buffer", vim.log.levels.ERROR)
		return
	end

	local ok, err = pcall(function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].filetype = "marksman"
	end)

	if not ok then
		notify("Failed to setup buffer: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		pcall(vim.api.nvim_buf_add_highlight, buf, -1, hl.hl_group, hl.line, hl.col, hl.end_col)
	end

	-- Calculate window dimensions
	local dimensions = calculate_window_dimensions(lines)

	-- Window title
	local title = " " .. (project_name or "Project") .. " "
	if search_query and search_query ~= "" then
		title = title .. "(filtered) "
	end

	-- Window options
	local opts = {
		relative = "editor",
		width = dimensions.width,
		height = dimensions.height,
		row = dimensions.row,
		col = dimensions.col,
		border = "rounded",
		style = "minimal",
		title = title,
		title_pos = "center",
	}

	-- Create window
	local win_ok, win = pcall(vim.api.nvim_open_win, buf, true, opts)
	if not win_ok then
		notify("Failed to create window: " .. tostring(win), vim.log.levels.ERROR)
		return
	end

	current_window = win
	current_buffer = buf

	-- Set window highlight
	pcall(vim.api.nvim_win_set_option, win, "winhighlight", "Normal:Normal,FloatBorder:ProjectMarksBorder")

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
			pcall(vim.fn.cursor, first_mark_line + 1, 1) -- +1 for 1-indexed
		end
	end
end

---Show search results in floating window
---@param results table Filtered marks
---@param query string Search query
function M.show_search_results(results, query)
	if vim.tbl_isempty(results) then
		notify("No marks found matching: " .. query, vim.log.levels.INFO)
		return
	end

	M.show_marks_window(results, "Search Results", query)
end

---Cleanup UI resources
function M.cleanup()
	close_window()
	config = {}
end

return M
