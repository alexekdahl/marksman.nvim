-- luacheck: globals vim
local M = {}

local config = {}
local current_window = nil

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

local function format_time_ago(timestamp)
	if not timestamp then
		return "unknown"
	end

	local now = os.time()
	local diff = now - timestamp

	if diff < 60 then
		return "now"
	elseif diff < 3600 then
		return math.floor(diff / 60) .. "m ago"
	elseif diff < 86400 then
		return math.floor(diff / 3600) .. "h ago"
	elseif diff < 604800 then
		return math.floor(diff / 86400) .. "d ago"
	else
		return os.date("%m/%d", timestamp)
	end
end

local function close_window()
	if current_window and vim.api.nvim_win_is_valid(current_window) then
		vim.api.nvim_win_close(current_window, true)
		current_window = nil
		current_buffer = nil
	end
end

local function create_marks_content(marks, search_query)
	local lines = {}
	local highlights = {}
	local mark_info = {} -- Store mark data for each line

	-- Filter marks if search query provided
	local filtered_marks = {}
	if search_query and search_query ~= "" then
		search_query = search_query:lower()
		for name, mark in pairs(marks) do
			local searchable = (
				name
				.. " "
				.. (mark.description or "")
				.. " "
				.. vim.fn.fnamemodify(mark.file, ":t")
				.. " "
				.. (mark.text or "")
			):lower()
			if searchable:find(search_query, 1, true) then
				filtered_marks[name] = mark
			end
		end
	else
		filtered_marks = marks
	end

	-- Sort marks
	local mark_names = {}
	for name in pairs(filtered_marks) do
		table.insert(mark_names, name)
	end

	-- Only sort if sorting is enabled in config
	if config.sort_marks then
		table.sort(mark_names, function(a, b)
			local mark_a = filtered_marks[a]
			local mark_b = filtered_marks[b]
			local time_a = mark_a.accessed_at or mark_a.created_at or 0
			local time_b = mark_b.accessed_at or mark_b.created_at or 0
			return time_a > time_b
		end)
	else
		-- When sorting is disabled, maintain insertion order (oldest first)
		table.sort(mark_names, function(a, b)
			local mark_a = filtered_marks[a]
			local mark_b = filtered_marks[b]
			local time_a = mark_a.created_at or 0
			local time_b = mark_b.created_at or 0
			return time_a < time_b
		end)
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
	local shown_marks = vim.tbl_count(filtered_marks)
	local stats_line = string.format(" Showing %d of %d marks", shown_marks, total_marks)
	table.insert(lines, stats_line)
	table.insert(highlights, { line = 2, col = 0, end_col = -1, hl_group = "ProjectMarksHelp" })
	table.insert(lines, "")

	-- Help text
	local help_lines = {
		" <CR>/1-9: Jump  d: Delete  r: Rename  e: Edit desc  /: Search",
		" u: Undo delete  v: Validate  s: Stats  q: Close",
	}
	for _, help_line in ipairs(help_lines) do
		table.insert(lines, help_line)
		table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "ProjectMarksHelp" })
	end
	table.insert(lines, "")

	if vim.tbl_isempty(filtered_marks) then
		local no_marks_line = search_query and search_query ~= "" and " No marks found matching search"
			or " No marks in this project"
		table.insert(lines, no_marks_line)
		table.insert(highlights, { line = #lines - 1, col = 0, end_col = -1, hl_group = "ProjectMarksText" })
		return lines, highlights, {}
	end

	for i, name in ipairs(mark_names) do
		local mark = filtered_marks[name]
		local icon = get_icon_for_file(mark.file)
		local rel_path = vim.fn.fnamemodify(mark.file, ":~:.")
		local time_str = format_time_ago(mark.accessed_at or mark.created_at)

		local number = string.format("[%d]", i)
		local name_part = icon .. " " .. name
		local file_part = rel_path .. ":" .. mark.line
		local time_part = "(" .. time_str .. ")"

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

		-- Description line (if exists)
		if config.enable_descriptions and mark.description and mark.description ~= "" then
			local desc_line = "   │ " .. mark.description
			table.insert(lines, desc_line)
			table.insert(highlights, {
				line = #lines - 1,
				col = 0,
				end_col = -1,
				hl_group = "ProjectMarksText",
			})
		end

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
		local info = string.format("   └─ %s %s", file_part, time_part)
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
			refresh_window(search_query)
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

	local function edit_description()
		local mark_info_item = get_mark_under_cursor(mark_info)
		if mark_info_item then
			local current_desc = mark_info_item.mark.description or ""
			vim.ui.input({
				prompt = "Description: ",
				default = current_desc,
			}, function(new_desc)
				if new_desc ~= nil then
					local marksman = require("marksman")
					marksman.update_mark_description(mark_info_item.name, new_desc)
					refresh_window(search_query)
				end
			end)
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

	local function undo_deletion()
		local marksman = require("marksman")
		if marksman.undo_last_deletion() then
			refresh_window(search_query)
		end
	end

	local function validate_marks()
		local storage = require("marksman.storage")
		storage.validate_marks()
	end

	local function show_statistics()
		local storage = require("marksman.storage")
		local stats = storage.get_statistics()

		local stats_text = string.format(
			"Project: %s\nTotal marks: %d\nOldest: %s\nNewest: %s\nMost accessed: %s",
			stats.project,
			stats.total_marks,
			stats.oldest_mark or "none",
			stats.newest_mark or "none",
			stats.most_accessed or "none"
		)

		notify(stats_text, vim.log.levels.INFO)
	end

	local keymap_opts = { buffer = buf, noremap = true, silent = true }

	-- Basic navigation
	vim.keymap.set("n", "q", close_window, keymap_opts)
	vim.keymap.set("n", "<Esc>", close_window, keymap_opts)
	vim.keymap.set("n", "<CR>", goto_selected, keymap_opts)

	-- Mark operations
	vim.keymap.set("n", "d", delete_selected, keymap_opts)
	vim.keymap.set("n", "r", rename_selected, keymap_opts)
	vim.keymap.set("n", "e", edit_description, keymap_opts)
	vim.keymap.set("n", "/", search_marks, keymap_opts)
	vim.keymap.set("n", "u", undo_deletion, keymap_opts)
	vim.keymap.set("n", "v", validate_marks, keymap_opts)
	vim.keymap.set("n", "s", show_statistics, keymap_opts)

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
		vim.notify("No marks found matching: " .. query, vim.log.levels.INFO)
		return
	end

	M.show_marks_window(results, "Search Results", query)
end

return M
