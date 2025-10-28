local M = {}

-- State
local marks = {}
local current_project = nil

-- Configuration
local config = {
	keymaps = {
		add = "<C-a>",
		show = "<C-e>",
		goto_1 = "<M-y>",
		goto_2 = "<M-u>",
		goto_3 = "<M-i>",
		goto_4 = "<M-o>",
	},
	highlights = {
		ProjectMarksTitle = { fg = "#7aa2f7", bold = true },
		ProjectMarksNumber = { fg = "#bb9af7" },
		ProjectMarksName = { fg = "#9ece6a", bold = true },
		ProjectMarksFile = { fg = "#73daca" },
		ProjectMarksLine = { fg = "#ff9e64" },
		ProjectMarksText = { fg = "#565f89", italic = true },
		ProjectMarksHelp = { fg = "#7aa2f7" },
		ProjectMarksBorder = { fg = "#3b4261" },
	},
	auto_save = true,
	max_marks = 100,
}

-- Utilities
local function setup_highlights()
	for name, attrs in pairs(config.highlights) do
		vim.api.nvim_set_hl(0, name, attrs)
	end
end

local function get_project_root()
	local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
	if vim.v.shell_error == 0 then
		return git_root
	end
	return vim.fn.getcwd()
end

local function get_marks_file()
	local project = get_project_root()
	local hash = vim.fn.sha256(project):sub(1, 8)
	local data_path = vim.fn.stdpath("data")
	return data_path .. "/marksman_" .. hash .. ".json"
end

local function load_marks()
	current_project = get_project_root()
	local file = get_marks_file()

	if vim.fn.filereadable(file) == 1 then
		local content = vim.fn.readfile(file)
		if #content > 0 then
			local ok, decoded = pcall(vim.json.decode, table.concat(content, "\n"))
			if ok and decoded then
				marks = decoded
			else
				marks = {}
			end
		end
	else
		marks = {}
	end
end

local function save_marks()
	if not config.auto_save then
		return
	end

	local file = get_marks_file()
	local ok, json = pcall(vim.json.encode, marks)
	if ok then
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
		vim.fn.writefile({ json }, file)
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
		cs = "",
		rb = "",
		php = "",
		html = "",
		css = "",
		scss = "",
		json = "",
		yaml = "",
		yml = "",
		toml = "",
		xml = "",
		md = "",
		txt = "",
		vim = "",
		sh = "",
		fish = "",
		zsh = "",
		bash = "",
	}
	return icons[extension] or ""
end

local function generate_mark_name(bufname, line)
	local filename = vim.fn.fnamemodify(bufname, ":t:r")
	local context = vim.fn.getline("."):match("%s*(.-)%s*$")

	if context and #context > 0 then
		local patterns = {
			"function%s+([%w_]+)",
			"class%s+([%w_]+)",
			"def%s+([%w_]+)",
			"const%s+([%w_]+)",
			"let%s+([%w_]+)",
			"var%s+([%w_]+)",
		}

		for _, pattern in ipairs(patterns) do
			local identifier = context:match(pattern)
			if identifier then
				return filename .. ":" .. identifier
			end
		end
	end

	return filename .. ":" .. line
end

-- Core API
function M.add_mark(name)
	load_marks()

	if vim.tbl_count(marks) >= config.max_marks then
		vim.notify("Maximum marks limit reached (" .. config.max_marks .. ")", vim.log.levels.WARN)
		return
	end

	local bufname = vim.fn.expand("%:p")
	if bufname == "" then
		vim.notify("Cannot add mark: no file", vim.log.levels.WARN)
		return
	end

	local line = vim.fn.line(".")
	local col = vim.fn.col(".")

	if not name or name == "" then
		name = generate_mark_name(bufname, line)
	end

	marks[name] = {
		file = bufname,
		line = line,
		col = col,
		text = vim.fn.getline("."):sub(1, 80),
		created_at = os.time(),
	}

	save_marks()
	vim.notify("󰃀 Mark added: " .. name, vim.log.levels.INFO)
end

function M.goto_mark(name_or_index)
	load_marks()

	local mark = nil
	local mark_name = name_or_index

	if type(name_or_index) == "number" then
		local mark_names = {}
		for name in pairs(marks) do
			table.insert(mark_names, name)
		end

		table.sort(mark_names, function(a, b)
			return (marks[a].created_at or 0) > (marks[b].created_at or 0)
		end)

		if name_or_index > 0 and name_or_index <= #mark_names then
			mark_name = mark_names[name_or_index]
			mark = marks[mark_name]
		end
	else
		mark = marks[name_or_index]
	end

	if mark then
		if vim.fn.filereadable(mark.file) == 0 then
			vim.notify("Mark file no longer exists: " .. mark.file, vim.log.levels.WARN)
			return
		end

		vim.cmd("edit " .. vim.fn.fnameescape(mark.file))
		vim.fn.cursor(mark.line, mark.col)
		vim.notify("󰃀 Jumped to: " .. mark_name, vim.log.levels.INFO)
	else
		vim.notify("Mark not found: " .. tostring(name_or_index), vim.log.levels.WARN)
	end
end

function M.delete_mark(name)
	load_marks()

	if marks[name] then
		marks[name] = nil
		save_marks()
		vim.notify("󰃀 Mark deleted: " .. name, vim.log.levels.INFO)
	else
		vim.notify("Mark not found: " .. name, vim.log.levels.WARN)
	end
end

function M.rename_mark(old_name, new_name)
	load_marks()

	if not marks[old_name] then
		vim.notify("Mark not found: " .. old_name, vim.log.levels.WARN)
		return
	end

	if marks[new_name] then
		vim.notify("A mark with that name already exists", vim.log.levels.WARN)
		return
	end

	marks[new_name] = marks[old_name]
	marks[old_name] = nil
	save_marks()
	vim.notify("󰃀 Mark renamed: " .. old_name .. " → " .. new_name, vim.log.levels.INFO)
end

function M.show_marks()
	load_marks()

	if vim.tbl_isempty(marks) then
		vim.notify("No marks in current project", vim.log.levels.INFO)
		return
	end

	setup_highlights()

	local lines = {}
	local mark_names = {}
	local highlights = {}

	for name in pairs(marks) do
		table.insert(mark_names, name)
	end

	table.sort(mark_names, function(a, b)
		return (marks[a].created_at or 0) > (marks[b].created_at or 0)
	end)

	-- Header
	table.insert(lines, " 󰃀 Project Marks ")
	table.insert(highlights, { line = 0, col = 0, end_col = -1, hl_group = "ProjectMarksTitle" })
	table.insert(lines, "")

	-- Help text
	table.insert(lines, " <CR>/1-9: Jump  d: Delete  r: Rename  q: Close")
	table.insert(highlights, { line = 2, col = 0, end_col = -1, hl_group = "ProjectMarksHelp" })
	table.insert(lines, "")

	for i, name in ipairs(mark_names) do
		local mark = marks[name]
		local icon = get_icon_for_file(mark.file)
		local rel_path = vim.fn.fnamemodify(mark.file, ":~:.")
		local time_str = os.date("%m/%d %H:%M", mark.created_at or 0)

		local number = string.format("[%d]", i)
		local name_part = icon .. " " .. name
		local file_part = rel_path .. ":" .. mark.line
		local time_part = "(" .. time_str .. ")"

		local line = string.format("%s %s", number, name_part)
		table.insert(lines, line)

		local line_idx = #lines - 1
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
		local preview = "   │ " .. (mark.text or ""):gsub("^%s+", "")
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

	-- Create floating window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].filetype = "marksman"

	-- Apply highlights
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_add_highlight(buf, -1, hl.hl_group, hl.line, hl.col, hl.end_col)
	end

	local width = math.min(100, vim.o.columns - 10)
	local height = math.min(#lines, vim.o.lines - 6)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = (vim.o.lines - height) / 2,
		col = (vim.o.columns - width) / 2,
		border = "rounded",
		style = "minimal",
		title = " " .. vim.fn.fnamemodify(current_project, ":t") .. " ",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(buf, true, opts)

	-- Keymaps
	local function close_window()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function get_mark_under_cursor()
		local line = vim.fn.line(".")
		local mark_idx = math.floor((line - 5) / 4) + 1
		if mark_idx > 0 and mark_idx <= #mark_names then
			return mark_names[mark_idx]
		end
		return nil
	end

	local function goto_selected()
		local mark_name = get_mark_under_cursor()
		if mark_name then
			close_window()
			M.goto_mark(mark_name)
		end
	end

	local function delete_selected()
		local mark_name = get_mark_under_cursor()
		if mark_name then
			M.delete_mark(mark_name)
			close_window()
			M.show_marks()
		end
	end

	local function rename_selected()
		local mark_name = get_mark_under_cursor()
		if mark_name then
			vim.ui.input({
				prompt = "New name: ",
				default = mark_name,
			}, function(new_name)
				if new_name and new_name ~= "" and new_name ~= mark_name then
					M.rename_mark(mark_name, new_name)
					close_window()
					M.show_marks()
				end
			end)
		end
	end

	local keymap_opts = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("n", "q", close_window, keymap_opts)
	vim.keymap.set("n", "<Esc>", close_window, keymap_opts)
	vim.keymap.set("n", "<CR>", goto_selected, keymap_opts)
	vim.keymap.set("n", "d", delete_selected, keymap_opts)
	vim.keymap.set("n", "r", rename_selected, keymap_opts)

	-- Number key navigation
	for i = 1, math.min(9, #mark_names) do
		vim.keymap.set("n", tostring(i), function()
			close_window()
			M.goto_mark(mark_names[i])
		end, keymap_opts)
	end
end

function M.telescope_marks()
	local ok, telescope = pcall(require, "telescope")
	if not ok then
		M.show_marks()
		return
	end

	load_marks()

	if vim.tbl_isempty(marks) then
		vim.notify("No marks in current project", vim.log.levels.INFO)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local entries = {}
	for name, mark in pairs(marks) do
		table.insert(entries, {
			value = name,
			display = name .. " - " .. vim.fn.fnamemodify(mark.file, ":~:.") .. ":" .. mark.line,
			ordinal = name .. " " .. mark.file .. " " .. (mark.text or ""),
			filename = mark.file,
			lnum = mark.line,
			col = mark.col,
			text = mark.text,
		})
	end

	table.sort(entries, function(a, b)
		local mark_a = marks[a.value]
		local mark_b = marks[b.value]
		return (mark_a.created_at or 0) > (mark_b.created_at or 0)
	end)

	pickers
		.new({}, {
			prompt_title = "Project Marks",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					return entry
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.grep_previewer({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						M.goto_mark(selection.value)
					end
				end)

				actions.delete_buffer:replace(function()
					local selection = action_state.get_selected_entry()
					if selection then
						M.delete_mark(selection.value)
						actions.close(prompt_bufnr)
						M.telescope_marks()
					end
				end)

				return true
			end,
		})
		:find()
end

function M.get_marks_count()
	load_marks()
	return vim.tbl_count(marks)
end

function M.clear_all_marks()
	vim.ui.select({ "Yes", "No" }, {
		prompt = "Clear all marks in this project?",
	}, function(choice)
		if choice == "Yes" then
			marks = {}
			save_marks()
			vim.notify("󰃀 All marks cleared", vim.log.levels.INFO)
		end
	end)
end

function M.export_marks()
	load_marks()

	if vim.tbl_isempty(marks) then
		vim.notify("No marks to export", vim.log.levels.INFO)
		return
	end

	local export_data = {
		project = current_project,
		exported_at = os.date("%Y-%m-%d %H:%M:%S"),
		marks = marks,
	}

	local ok, json = pcall(vim.json.encode, export_data)
	if ok then
		local filename = vim.fn.input("Export to: ", "marks_export.json")
		if filename ~= "" then
			vim.fn.writefile({ json }, filename)
			vim.notify("󰃀 Marks exported to " .. filename, vim.log.levels.INFO)
		end
	end
end

function M.import_marks()
	local filename = vim.fn.input("Import from: ", "", "file")
	if filename == "" or vim.fn.filereadable(filename) == 0 then
		vim.notify("File not found", vim.log.levels.WARN)
		return
	end

	local content = vim.fn.readfile(filename)
	if #content > 0 then
		local ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
		if ok and data and data.marks then
			load_marks()
			marks = vim.tbl_deep_extend("force", marks, data.marks)
			save_marks()
			vim.notify("󰃀 Marks imported successfully", vim.log.levels.INFO)
		else
			vim.notify("Invalid marks file", vim.log.levels.ERROR)
		end
	end
end

-- Setup
local initialized = false

local function init()
	if initialized then
		return
	end
	initialized = true

	-- User commands
	vim.api.nvim_create_user_command("MarkAdd", function(args)
		M.add_mark(args.args ~= "" and args.args or nil)
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("MarkGoto", function(args)
		if args.args == "" then
			M.show_marks()
		else
			M.goto_mark(args.args)
		end
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("MarkDelete", function(args)
		if args.args == "" then
			M.clear_all_marks()
		else
			M.delete_mark(args.args)
		end
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("MarkRename", function(args)
		local parts = vim.split(args.args, " ", { plain = true })
		if #parts >= 2 then
			local old_name = parts[1]
			local new_name = table.concat(parts, " ", 2)
			M.rename_mark(old_name, new_name)
		end
	end, { nargs = "+" })

	vim.api.nvim_create_user_command("MarkList", M.show_marks, {})
	vim.api.nvim_create_user_command("MarkClear", M.clear_all_marks, {})
	vim.api.nvim_create_user_command("MarkTelescope", M.telescope_marks, {})
	vim.api.nvim_create_user_command("MarkExport", M.export_marks, {})
	vim.api.nvim_create_user_command("MarkImport", M.import_marks, {})

	-- Set keymaps if not disabled
	if config.keymaps ~= false then
		local keymaps = config.keymaps

		if keymaps.add then
			vim.keymap.set("n", keymaps.add, M.add_mark, { desc = "Add mark" })
		end
		if keymaps.show then
			vim.keymap.set("n", keymaps.show, M.show_marks, { desc = "Show marks" })
		end

		for i = 1, 4 do
			local key = keymaps["goto_" .. i]
			if key then
				vim.keymap.set("n", key, function()
					M.goto_mark(i)
				end, { desc = "Go to mark " .. i })
			end
		end
	end

	setup_highlights()
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
	init()
end

-- Auto-initialize on first use
setmetatable(M, {
	__index = function(t, k)
		if not initialized and k ~= "setup" then
			init()
		end
		return rawget(t, k)
	end,
})

return M
