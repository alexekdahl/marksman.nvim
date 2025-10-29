-- luacheck: globals vim
local M = {}

-- Lazy load modules
local storage = nil
local ui = nil
local utils = nil

-- Configuration
local default_config = {
	keymaps = {
		add = "<C-a>",
		show = "<C-e>",
		goto_1 = "<M-y>",
		goto_2 = "<M-u>",
		goto_3 = "<M-i>",
		goto_4 = "<M-o>",
	},
	highlights = {
		ProjectMarksTitle = { fg = "#61AFEF", bold = true },
		ProjectMarksNumber = { fg = "#C678DD" },
		ProjectMarksName = { fg = "#98C379", bold = true },
		ProjectMarksFile = { fg = "#56B6C2" },
		ProjectMarksLine = { fg = "#D19A66" },
		ProjectMarksText = { fg = "#5C6370", italic = true },
		ProjectMarksHelp = { fg = "#61AFEF" },
		ProjectMarksBorder = { fg = "#5A5F8C" },
		ProjectMarksSearch = { fg = "#E5C07B" },
	},
	auto_save = true,
	max_marks = 100,
	enable_descriptions = true,
	search_in_ui = true,
	undo_levels = 10,
	sort_marks = true,
	silent = false,
}

local config = {}

-- Helper function for conditional notifications
local function notify(message, level)
	if not config.silent then
		vim.notify(message, level)
	end
end

-- Lazy module loading
local function get_storage()
	if not storage then
		storage = require("marksman.storage")
		storage.setup(config)
	end
	return storage
end

local function get_ui()
	if not ui then
		ui = require("marksman.ui")
		ui.setup(config)
	end
	return ui
end

local function get_utils()
	if not utils then
		utils = require("marksman.utils")
	end
	return utils
end

-- Core API
function M.add_mark(name, description)
	local storage_module = get_storage()
	local utils_module = get_utils()

	local bufname = vim.fn.expand("%:p")
	if bufname == "" then
		notify("Cannot add mark: no file", vim.log.levels.WARN)
		return false
	end

	if storage_module.get_marks_count() >= config.max_marks then
		notify("Maximum marks limit reached (" .. config.max_marks .. ")", vim.log.levels.WARN)
		return false
	end

	local line = vim.fn.line(".")
	local col = vim.fn.col(".")

	if not name or name == "" then
		name = utils_module.generate_mark_name(bufname, line)
	end

	local mark = {
		file = bufname,
		line = line,
		col = col,
		text = vim.fn.getline("."):sub(1, 80),
		description = description or "",
		created_at = os.time(),
		accessed_at = os.time(),
	}

	local success = storage_module.add_mark(name, mark)
	if success then
		notify("󰃀 Mark added: " .. name, vim.log.levels.INFO)
		return true
	else
		notify("Failed to add mark: " .. name, vim.log.levels.ERROR)
		return false
	end
end

function M.goto_mark(name_or_index)
	local storage_module = get_storage()
	local marks = storage_module.get_marks()

	local mark = nil
	local mark_name = name_or_index

	if type(name_or_index) == "number" then
		local mark_names = storage_module.get_sorted_mark_names()
		if name_or_index > 0 and name_or_index <= #mark_names then
			mark_name = mark_names[name_or_index]
			mark = marks[mark_name]
		end
	else
		mark = marks[name_or_index]
	end

	if mark then
		if vim.fn.filereadable(mark.file) == 0 then
			notify("Mark file no longer exists: " .. mark.file, vim.log.levels.WARN)
			return false
		end

		-- Update access time
		storage_module.update_mark_access(mark_name)

		vim.cmd("edit " .. vim.fn.fnameescape(mark.file))
		vim.fn.cursor(mark.line, mark.col)
		vim.cmd("normal! zz") -- Center the line
		notify("󰃀 Jumped to: " .. mark_name, vim.log.levels.INFO)
		return true
	else
		notify("Mark not found: " .. tostring(name_or_index), vim.log.levels.WARN)
		return false
	end
end

function M.delete_mark(name)
	local storage_module = get_storage()
	local success = storage_module.delete_mark(name)

	if success then
		notify("󰃀 Mark deleted: " .. name, vim.log.levels.INFO)
		return true
	else
		notify("Mark not found: " .. name, vim.log.levels.WARN)
		return false
	end
end

function M.rename_mark(old_name, new_name)
	local storage_module = get_storage()
	local success = storage_module.rename_mark(old_name, new_name)

	if success then
		notify("󰃀 Mark renamed: " .. old_name .. " → " .. new_name, vim.log.levels.INFO)
		return true
	else
		notify("Failed to rename mark", vim.log.levels.WARN)
		return false
	end
end

function M.update_mark_description(name, description)
	local storage_module = get_storage()
	local success = storage_module.update_mark_description(name, description)

	if success then
		notify("󰃀 Mark description updated: " .. name, vim.log.levels.INFO)
		return true
	else
		notify("Failed to update mark description", vim.log.levels.WARN)
		return false
	end
end

function M.show_marks()
	local storage_module = get_storage()
	local ui_module = get_ui()

	local marks = storage_module.get_marks()
	if vim.tbl_isempty(marks) then
		notify("No marks in current project", vim.log.levels.INFO)
		return
	end

	ui_module.show_marks_window(marks, storage_module.get_project_name())
end

function M.search_marks(query)
	local storage_module = get_storage()
	local utils_module = get_utils()

	local marks = storage_module.get_marks()
	local filtered = utils_module.filter_marks(marks, query)

	if vim.tbl_isempty(filtered) then
		notify("No marks found matching: " .. query, vim.log.levels.INFO)
		return {}
	end

	return filtered
end

function M.get_marks_count()
	local storage_module = get_storage()
	return storage_module.get_marks_count()
end

function M.get_marks()
	local storage_module = get_storage()
	return storage_module.get_marks()
end

function M.clear_all_marks()
	vim.ui.select({ "Yes", "No" }, {
		prompt = "Clear all marks in this project?",
	}, function(choice)
		if choice == "Yes" then
			local storage_module = get_storage()
			storage_module.clear_all_marks()
			notify("󰃀 All marks cleared", vim.log.levels.INFO)
		end
	end)
end

function M.export_marks()
	local storage_module = get_storage()
	return storage_module.export_marks()
end

function M.import_marks()
	local storage_module = get_storage()
	return storage_module.import_marks()
end

function M.undo_last_deletion()
	local storage_module = get_storage()
	local restored = storage_module.undo_last_deletion()

	if restored then
		notify("󰃀 Restored mark: " .. restored, vim.log.levels.INFO)
		return true
	else
		notify("Nothing to undo", vim.log.levels.INFO)
		return false
	end
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Create user commands
	local commands = {
		{
			"MarkAdd",
			function(args)
				M.add_mark(args.args ~= "" and args.args or nil)
			end,
			{ nargs = "?" },
		},
		{
			"MarkGoto",
			function(args)
				if args.args == "" then
					M.show_marks()
				else
					M.goto_mark(args.args)
				end
			end,
			{ nargs = "?" },
		},
		{
			"MarkDelete",
			function(args)
				if args.args == "" then
					M.clear_all_marks()
				else
					M.delete_mark(args.args)
				end
			end,
			{ nargs = "?" },
		},
		{
			"MarkRename",
			function(args)
				local parts = vim.split(args.args, " ", { plain = true })
				if #parts >= 2 then
					local old_name = parts[1]
					local new_name = table.concat(parts, " ", 2)
					M.rename_mark(old_name, new_name)
				end
			end,
			{ nargs = "+" },
		},
		{ "MarkList", M.show_marks, {} },
		{ "MarkClear", M.clear_all_marks, {} },
		{ "MarkExport", M.export_marks, {} },
		{ "MarkImport", M.import_marks, {} },
		{
			"MarkSearch",
			function(args)
				M.search_marks(args.args)
			end,
			{ nargs = 1 },
		},
		{ "MarkUndo", M.undo_last_deletion, {} },
	}

	for _, cmd in ipairs(commands) do
		vim.api.nvim_create_user_command(cmd[1], cmd[2], cmd[3])
	end

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
end

return M
