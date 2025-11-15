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

-- Fixed window dimensions
local WINDOW_WIDTH = 80
local WINDOW_HEIGHT = 20

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
	-- Set up default highlights
	local default_highlights = {
		ProjectMarksTitle = { fg = "#61AFEF", bold = true },
		ProjectMarksNumber = { fg = "#C678DD" },
		ProjectMarksName = { fg = "#98C379", bold = true },
		ProjectMarksFile = { fg = "#56B6C2" },
		ProjectMarksLine = { fg = "#D19A66" },
		ProjectMarksText = { fg = "#5C6370", italic = true },
		ProjectMarksHelp = { fg = "#5C6370" }, -- Dimmed for help text
		ProjectMarksBorder = { fg = "#5A5F8C" },
		ProjectMarksSearch = { fg = "#E5C07B" },
		ProjectMarksSeparator = { fg = "#3E4451" }, -- For separator line
		-- Highlight for the sign indicator shown next to marks from the current file.
		-- This colour defaults to the same as the title but can be overridden in the user's config.
		ProjectMarksSign = { fg = "#61AFEF" },
	}

	-- Merge with user config
	local highlights = vim.tbl_deep_extend("force", default_highlights, config.highlights or {})

	for name, attrs in pairs(highlights) do
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
	if #rel_path > 40 then
		local parent = vim.fn.fnamemodify(filepath, ":h:t")
		local filename = vim.fn.fnamemodify(filepath, ":t")
		return parent .. "/" .. filename
	end
	return rel_path
end

---Create header content for marks window
---@param total_marks number Total number of marks
---@param shown_marks number Number of marks shown
---@param search_query string? Search query if any
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

	-- Stats line
	local stats_line = string.format(" Showing %d of %d marks", shown_marks, total_marks)
	table.insert(lines, stats_line)
	table.insert(highlights, { line = 1, col = 0, end_col = -1, hl_group = "ProjectMarksFile" })

	-- Separator
	table.insert(lines, string.rep("─", WINDOW_WIDTH - 2))
	table.insert(highlights, { line = 2, col = 0, end_col = -1, hl_group = "ProjectMarksSeparator" })

	return lines, highlights
end

---Create minimal mark display line
---@param name string Mark name
---@param mark table Mark data
---@param index number Mark index
---@param line_idx number Line index for highlights
---@return string line Formatted line
---@return table highlights Array of highlight definitions for this line
local function create_minimal_mark_line(name, mark, index, line_idx)
	local filepath = get_relative_path_display(mark.file)
	local line = string.format(" [%d] %-20s %s", index, name:sub(1, 20), filepath)

	-- Ensure line doesn't exceed window width
	if #line > WINDOW_WIDTH - 2 then
		line = line:sub(1, WINDOW_WIDTH - 5) .. "..."
	end

	local highlights = {}

	-- Number highlight
	table.insert(highlights, {
		line = line_idx,
		col = 1,
		end_col = 4 + #tostring(index),
		hl_group = "ProjectMarksNumber",
	})

	-- Name highlight
	local name_start = 4 + #tostring(index)
	local name_end = name_start + math.min(20, #name)
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

	-- Format: [1] icon name
	local number = string.format("[%d]", index)
	local name_display = name:sub(1, 30)
	local main_line = string.format(" %s %s %s", number, icon, name_display)

	-- Ensure line doesn't exceed window width
	if #main_line > WINDOW_WIDTH - 2 then
		main_line = main_line:sub(1, WINDOW_WIDTH - 5) .. "..."
	end

	table.insert(lines, main_line)

	-- Highlights for main line
	table.insert(highlights, {
		line = line_idx,
		col = 1,
		end_col = 1 + #number,
		hl_group = "ProjectMarksNumber",
	})
	table.insert(highlights, {
		line = line_idx,
		col = 1 + #number + 1,
		end_col = -1,
		hl_group = "ProjectMarksName",
	})

	-- File info on second line
	local file_info = string.format("    %s:%d", rel_path, mark.line)
	if #file_info > WINDOW_WIDTH - 2 then
		file_info = file_info:sub(1, WINDOW_WIDTH - 5) .. "..."
	end

	table.insert(lines, file_info)
	table.insert(highlights, {
		line = line_idx + 1,
		col = 4,
		end_col = -1,
		hl_group = "ProjectMarksFile",
	})

	return lines, highlights
end

---Create help text for the bottom of the window
---@return string help_line The help text line
local function create_help_line()
	local help_items = {
		"<CR>/1-9:Jump",
		"d:Delete",
		"r:Rename",
		"/:Search",
		"J/K:Move",
		"C:Clear",
		"q:Close",
	}

	local help_text = table.concat(help_items, "  ")
	local padding = math.max(0, WINDOW_WIDTH - #help_text - 2)
	local left_pad = math.floor(padding / 2)

	return string.rep(" ", left_pad) .. help_text
end

---Create complete marks window content
---@param marks table All marks data
---@param search_query string? Optional search query
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

	-- Create header
	local header_lines, header_highlights = create_header_content(total_marks, shown_marks, search_query)
	for _, line in ipairs(header_lines) do
		table.insert(lines, line)
	end
	for _, hl in ipairs(header_highlights) do
		table.insert(highlights, hl)
	end

	-- Calculate available space for marks
	local header_height = #header_lines
	local footer_height = 2 -- Separator + help line
	local available_height = WINDOW_HEIGHT - header_height - footer_height - 2

	-- Determine current file (absolute path) to mark entries belonging to the active buffer
	local current_file = vim.fn.expand("%:p")

	-- Handle no marks case
	if shown_marks == 0 then
		local no_marks_line = search_query and search_query ~= "" and " No marks found matching search"
			or " No marks in this project"
		table.insert(lines, "")
		table.insert(lines, no_marks_line)
		table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "ProjectMarksText" })

		-- Fill empty space
		while #lines < WINDOW_HEIGHT - footer_height - 1 do
			table.insert(lines, "")
		end
	else
		-- Create mark entries
		local current_line = #lines
		local marks_added = 0

		if config.minimal then
			-- Minimal mode - one line per mark
			for i, name in ipairs(filtered_names) do
				if marks_added >= available_height then
					break
				end

				local mark = marks[name]
				local line_idx = current_line + marks_added
				local line, line_highlights = create_minimal_mark_line(name, mark, i, line_idx)

				-- Determine if this mark is in the current file
				if mark.file == current_file then
					-- Replace leading space with sign indicator
					line = "●" .. line:sub(2)
					-- Add highlight for the sign indicator
					table.insert(highlights, {
						line = line_idx,
						col = 0,
						end_col = 1,
						hl_group = "ProjectMarksSign",
					})
				end

				table.insert(lines, line)
				mark_info[line_idx] = { name = name, mark = mark, index = i }

				for _, hl in ipairs(line_highlights) do
					table.insert(highlights, hl)
				end

				marks_added = marks_added + 1
			end
		else
			-- Detailed mode - two lines per mark
			for i, name in ipairs(filtered_names) do
				if marks_added + 2 > available_height then
					break
				end

				local mark = marks[name]
				local start_line_idx = current_line + marks_added
				local mark_lines, mark_highlights = create_detailed_mark_lines(name, mark, i, start_line_idx)

				-- If mark is in current file, decorate the first line with a sign indicator
				if mark.file == current_file then
					-- Replace leading space with sign indicator on the main line
					mark_lines[1] = "●" .. mark_lines[1]:sub(2)
					-- Insert highlight for sign indicator
					table.insert(highlights, {
						line = start_line_idx,
						col = 0,
						end_col = 1,
						hl_group = "ProjectMarksSign",
					})
				end

				mark_info[start_line_idx] = { name = name, mark = mark, index = i }

				for _, line_content in ipairs(mark_lines) do
					table.insert(lines, line_content)
				end
				for _, hl in ipairs(mark_highlights) do
					table.insert(highlights, hl)
				end

				marks_added = marks_added + #mark_lines
			end
		end

		-- Fill remaining space
		while #lines < WINDOW_HEIGHT - footer_height - 1 do
			table.insert(lines, "")
		end

		-- Add "..." indicator if there are more marks
		local displayed_count = config.minimal and marks_added or math.floor(marks_added / 2)
		if displayed_count < shown_marks then
			lines[#lines] = string.format(" ... and %d more marks", shown_marks - displayed_count)
			table.insert(highlights, {
				line = #lines - 1,
				col = 0,
				end_col = -1,
				hl_group = "ProjectMarksText",
			})
		end
	end

	-- Add separator before help
	table.insert(lines, string.rep("─", WINDOW_WIDTH - 2))
	table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "ProjectMarksSeparator" })

	-- Add help line
	table.insert(lines, create_help_line())
	table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "ProjectMarksHelp" })

	return lines, highlights, mark_info
end

---Find mark information for current cursor position
---@param mark_info table Mapping of line numbers to mark info
---@return table? mark_info Mark info for cursor position
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

	-- Don't return mark if cursor is too far (e.g., on help text)
	if closest_distance > 3 then
		return nil
	end

	return closest_mark
end

---Setup keymaps for marks window
---@param buf number Buffer handle
---@param marks table Marks data
---@param project_name string Project name
---@param mark_info table Mark info mapping
---@param search_query string? Search query
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
				-- Save cursor position
				local cursor_line = vim.fn.line(".")
				refresh_window(search_query)
				-- Try to restore cursor position
				vim.schedule(function()
					if direction == "up" and cursor_line > 4 then
						vim.fn.cursor(cursor_line - 1, 1)
					elseif direction == "down" and cursor_line < WINDOW_HEIGHT - 3 then
						vim.fn.cursor(cursor_line + 1, 1)
					end
				end)
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
				local marksman = require("marksman.storage")
				marksman.clear_all_marks()
				marksman.save_marks()
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

-- Public API

---Setup the UI module
---@param user_config table? Plugin configuration
function M.setup(user_config)
	config = user_config or {}
	setup_highlights()
end

---Show marks in floating window
---@param marks table Marks data
---@param project_name string Project name
---@param search_query string? Optional search query
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
		-- Use vim.bo syntax instead of deprecated option setting
		local bufnr = buf
		vim.bo[bufnr].modifiable = false
		vim.bo[bufnr].buftype = "nofile"
		vim.bo[bufnr].filetype = "marksman"
	end)

	if not ok then
		notify("Failed to setup buffer: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		pcall(vim.api.nvim_buf_add_highlight, buf, -1, hl.hl_group, hl.line, hl.col, hl.end_col)
	end

	-- Calculate window position based on user configuration.  By default the
	-- marks window is centered in the editor, but users can override
	-- this by specifying ui.position in their plugin configuration.  A
	-- value of "top_center" positions the window near the top of the
	-- screen, while "bottom_center" aligns it near the bottom.  Any
	-- unrecognised value falls back to the centered position.  We also
	-- clamp the row so the window never renders outside the visible
	-- editor lines.  Note: vim.o.lines returns the total number of
	-- lines in the UI (not just the buffer), so subtracting the window
	-- height ensures the window is fully on screen.
	local pos = nil
	if config and type(config.ui) == "table" then
		pos = config.ui.position
	end
	local row
	if pos == "top_center" then
		-- Place the window a couple of lines down to avoid
		-- overlapping the very top of the UI.  A value of 1 gives
		-- a small margin but still keeps the window anchored near
		-- the top.
		row = 1
	elseif pos == "bottom_center" then
		-- Place the window a couple of lines above the bottom to
		-- leave room for command line and status line.  We subtract
		-- 2 to account for the border and padding.
		row = vim.o.lines - WINDOW_HEIGHT - 2
	else
		-- Default to center positioning
		row = math.floor((vim.o.lines - WINDOW_HEIGHT) / 2)
	end
	-- Ensure row stays within valid bounds
	if row < 0 then
		row = 0
	elseif row > vim.o.lines - WINDOW_HEIGHT then
		row = math.max(vim.o.lines - WINDOW_HEIGHT, 0)
	end
	-- Always center horizontally
	local col = math.floor((vim.o.columns - WINDOW_WIDTH) / 2)

	-- Window title
	local title = " " .. (project_name or "Project") .. " "
	if search_query and search_query ~= "" then
		title = title .. "(filtered) "
	end

	-- Window options
	local opts = {
		relative = "editor",
		width = WINDOW_WIDTH,
		height = WINDOW_HEIGHT,
		row = row,
		col = col,
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

	-- Set window highlight using vim.wo syntax
	pcall(function()
		vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:ProjectMarksBorder"
	end)

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
	else
		-- Position cursor on first content line after header
		pcall(vim.fn.cursor, 4, 1)
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
