-- luacheck: globals vim
---@class Marksman
---@field config table Plugin configuration
---@field storage table Storage module instance
---@field ui table UI module instance
---@field utils table Utils module instance
local M = {}

-- Lazy load modules
local storage = nil
local ui = nil
local utils = nil

-- Default configuration with validation schema
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
	silent = false,
	minimal = false,
	disable_default_keymaps = false,
	debounce_ms = 500, -- Debounce save operations
	ui = {
		-- Position of the marks window.
		-- "center" positions the window in the middle of the editor (default).
		-- "top_center" aligns the window at the top of the screen, centered horizontally.
		-- "bottom_center" aligns the window at the bottom of the screen, centered horizontally.
		position = "center",
	},
}

-- Configuration validation schema
local config_schema = {
	auto_save = { type = "boolean" },
	max_marks = { type = "number", min = 1, max = 1000 },
	silent = { type = "boolean" },
	minimal = { type = "boolean" },
	disable_default_keymaps = { type = "boolean" },
	debounce_ms = { type = "number", min = 100, max = 5000 },
	ui = {
		type = "table",
		fields = {
			position = {
				type = "string",
				allowed = { "center", "top_center", "bottom_center" },
			},
		},
	},
}

local config = {}

-- Debounced save timer
local save_timer = nil

---Helper function for conditional notifications
---@param message string The notification message
---@param level number The log level (vim.log.levels.*)
local function notify(message, level)
	if not config.silent then
		vim.notify(message, level)
	end
end

---Validate configuration against schema
---@param user_config table? User provided configuration
---@param schema table Validation schema
---@return table validated_config Validated configuration
local function validate_config(user_config, schema)
	local validated = {}

	for key, value in pairs(user_config or {}) do
		local rule = schema[key]
		if rule then
			if rule.type and type(value) ~= rule.type then
				notify(
					string.format("Invalid config type for %s: expected %s, got %s", key, rule.type, type(value)),
					vim.log.levels.WARN
				)
			elseif rule.min and value < rule.min then
				notify(
					string.format("Config value %s below minimum: %s < %s", key, value, rule.min),
					vim.log.levels.WARN
				)
			elseif rule.max and value > rule.max then
				notify(
					string.format("Config value %s above maximum: %s > %s", key, value, rule.max),
					vim.log.levels.WARN
				)
			else
				validated[key] = value
			end
		else
			validated[key] = value -- Allow unknown keys for forward compatibility
		end
	end

	return validated
end

---Lazy module loading with error handling
---@return table? storage Storage module
local function get_storage()
	if not storage then
		local ok, module = pcall(require, "marksman.storage")
		if not ok then
			notify("Failed to load storage module: " .. tostring(module), vim.log.levels.ERROR)
			return nil
		end
		storage = module
		storage.setup(config)
	end
	return storage
end

---Lazy module loading with error handling
---@return table? ui UI module
local function get_ui()
	if not ui then
		local ok, module = pcall(require, "marksman.ui")
		if not ok then
			notify("Failed to load UI module: " .. tostring(module), vim.log.levels.ERROR)
			return nil
		end
		ui = module
		ui.setup(config)
	end
	return ui
end

---Lazy module loading with error handling
---@return table? utils Utils module
local function get_utils()
	if not utils then
		local ok, module = pcall(require, "marksman.utils")
		if not ok then
			notify("Failed to load utils module: " .. tostring(module), vim.log.levels.ERROR)
			return nil
		end
		utils = module
	end
	return utils
end

---Debounced save operation
local function debounced_save()
	if save_timer then
		save_timer:stop()
	end

	save_timer = vim.defer_fn(function()
		local storage_module = get_storage()
		if storage_module then
			storage_module.save_marks()
		end
		save_timer = nil
	end, config.debounce_ms or 500)
end

---Add a mark at the current cursor position
---@param name string? Optional mark name (auto-generated if nil)
---@param description string? Optional mark description
---@return table result Result with success, message, and mark_name
function M.add_mark(name, description)
	local storage_module = get_storage()
	local utils_module = get_utils()

	if not storage_module or not utils_module then
		return { success = false, message = "Failed to load required modules" }
	end

	local bufname = vim.fn.expand("%:p")
	if bufname == "" or bufname == "[No Name]" then
		return { success = false, message = "Cannot add mark: no file or unnamed buffer" }
	end

	-- Check if file exists and is readable
	if vim.fn.filereadable(bufname) == 0 then
		return { success = false, message = "Cannot add mark: file is not readable" }
	end

	if storage_module.get_marks_count() >= config.max_marks then
		return {
			success = false,
			message = string.format("Maximum marks limit reached (%d)", config.max_marks),
		}
	end

	local line = vim.fn.line(".")
	local col = vim.fn.col(".")

	-- Validate and generate name if needed
	if name then
		local valid, err = utils_module.validate_mark_name(name)
		if not valid then
			return { success = false, message = "Invalid mark name: " .. err }
		end
	else
		name = utils_module.suggest_mark_name(bufname, line, storage_module.get_marks())
	end

	-- Check for existing mark with same name
	local existing_marks = storage_module.get_marks()
	if existing_marks[name] then
		return { success = false, message = "Mark already exists: " .. name }
	end

	local mark = {
		file = bufname,
		line = line,
		col = col,
		text = vim.fn.getline("."):sub(1, 80),
		created_at = os.time(),
		description = description,
	}

	local success = storage_module.add_mark(name, mark)
	if success then
		debounced_save()
		notify("󰃀 Mark added: " .. name, vim.log.levels.INFO)
		return { success = true, message = "Mark added successfully", mark_name = name }
	else
		return { success = false, message = "Failed to add mark: " .. name }
	end
end

---Jump to a mark by name or index
---@param name_or_index string|number Mark name or numeric index
---@return table result Result with success and message
function M.goto_mark(name_or_index)
	local storage_module = get_storage()
	if not storage_module then
		return { success = false, message = "Failed to load storage module" }
	end

	local marks = storage_module.get_marks()
	if vim.tbl_isempty(marks) then
		return { success = false, message = "No marks available" }
	end

	local mark = nil
	local mark_name = name_or_index

	if type(name_or_index) == "number" then
		local mark_names = storage_module.get_mark_names()
		if name_or_index > 0 and name_or_index <= #mark_names then
			mark_name = mark_names[name_or_index]
			mark = marks[mark_name]
		else
			return { success = false, message = "Invalid mark index: " .. name_or_index }
		end
	else
		mark = marks[name_or_index]
		if not mark then
			return { success = false, message = "Mark not found: " .. tostring(name_or_index) }
		end
	end

	-- Validate mark data before jumping
	local utils_module = get_utils()
	if utils_module then
		local valid, err = utils_module.validate_mark_data(mark)
		if not valid then
			return { success = false, message = "Invalid mark data: " .. err }
		end
	end

	-- Check if file still exists
	if vim.fn.filereadable(mark.file) == 0 then
		return { success = false, message = "Mark file no longer exists: " .. mark.file }
	end

	-- Safely jump to mark
	local ok, err = pcall(function()
		vim.cmd("edit " .. vim.fn.fnameescape(mark.file))
		vim.fn.cursor(mark.line, mark.col)
		vim.cmd("normal! zz") -- Center the line
	end)

	if ok then
		notify("󰃀 Jumped to: " .. mark_name, vim.log.levels.INFO)
		return { success = true, message = "Jumped to mark successfully", mark_name = mark_name }
	else
		return { success = false, message = "Failed to jump to mark: " .. tostring(err) }
	end
end

-- Finds the mark index closest to the current cursor position.
-- Returns:
--   current_index (number | nil): exact or closest index in current file, or nil if none in file
--   total_marks (number | nil): total number of marks, nil if no marks exist
--   error (string | nil): error message only when no marks exist at all
local function get_current_mark_index(storage_module)
	local mark_names = storage_module.get_mark_names()
	local total_marks = #mark_names
	if total_marks == 0 then
		return nil, nil, "No marks available"
	end

	local marks = storage_module.get_marks()
	local current_file = vim.fn.expand("%:p")
	local current_line = vim.fn.line(".")

	local nearest_index = nil
	local shortest_distance = nil

	for index, mark_name in ipairs(mark_names) do
		local mark = marks[mark_name]
		if mark.file == current_file then
			if mark.line == current_line then
				return index, total_marks, nil
			end
			local distance = math.abs(mark.line - current_line)
			if not shortest_distance or distance < shortest_distance then
				nearest_index = index
				shortest_distance = distance
			end
		end
	end

	return nearest_index, total_marks, nil
end

---Jump to the next mark.
---Navigation is context-aware:
---• If the cursor is on a mark, jump relative to it.
---• If the cursor is not on a mark, select the nearest mark in the same file before jumping.
---• If the current file has no marks, jump to the first index.
---Wraps when reaching the last mark.
---@return table result Result with success and optional message
function M.goto_next()
	local storage_module = get_storage()
	if not storage_module then
		return { success = false, message = "Failed to load storage module" }
	end

	local current_index, count, err = get_current_mark_index(storage_module)
	if err then
		return { success = false, message = err }
	end
	local next_index
	if not current_index then
		next_index = 1
	else
		next_index = (current_index % count) + 1
	end
	return M.goto_mark(next_index)
end

---Jump to the previous mark.
---Navigation is context-aware:
---• If the cursor is on a mark, jump relative to it.
---• If the cursor is not on a mark, select the nearest mark in the same file before jumping.
---• If the current file has no marks, jump to the last index.
---Wraps when reaching the last mark.
---@return table result Result with success and optional message
function M.goto_previous()
	local storage_module = get_storage()
	if not storage_module then
		return { success = false, message = "Failed to load storage module" }
	end

	local current_index, count, err = get_current_mark_index(storage_module)
	if err then
		return { success = false, message = err }
	end

	local previous_index
	if not current_index and count then
		previous_index = count
	else
		previous_index = ((current_index - 2) % count) + 1
	end
	return M.goto_mark(previous_index)
end

---Delete a mark by name
---@param name string Mark name to delete
---@return table result Result with success and message
function M.delete_mark(name)
	local storage_module = get_storage()
	if not storage_module then
		return { success = false, message = "Failed to load storage module" }
	end

	if not name or name == "" then
		return { success = false, message = "Mark name cannot be empty" }
	end

	local success = storage_module.delete_mark(name)
	if success then
		debounced_save()
		notify("󰃀 Mark deleted: " .. name, vim.log.levels.INFO)
		return { success = true, message = "Mark deleted successfully", mark_name = name }
	else
		return { success = false, message = "Mark not found: " .. name }
	end
end

---Rename a mark
---@param old_name string Current mark name
---@param new_name string New mark name
---@return table result Result with success and message
function M.rename_mark(old_name, new_name)
	local storage_module = get_storage()
	local utils_module = get_utils()

	if not storage_module or not utils_module then
		return { success = false, message = "Failed to load required modules" }
	end

	-- Validate new name
	local valid, err = utils_module.validate_mark_name(new_name)
	if not valid then
		return { success = false, message = "Invalid new mark name: " .. err }
	end

	local success = storage_module.rename_mark(old_name, new_name)
	if success then
		debounced_save()
		notify("󰃀 Mark renamed: " .. old_name .. " → " .. new_name, vim.log.levels.INFO)
		return { success = true, message = "Mark renamed successfully", old_name = old_name, new_name = new_name }
	else
		return { success = false, message = "Failed to rename mark" }
	end
end

---Move a mark up or down in the list
---@param name string Mark name
---@param direction string "up" or "down"
---@return table result Result with success and message
function M.move_mark(name, direction)
	local storage_module = get_storage()
	if not storage_module then
		return { success = false, message = "Failed to load storage module" }
	end

	if direction ~= "up" and direction ~= "down" then
		return { success = false, message = "Invalid direction: must be 'up' or 'down'" }
	end

	local success = storage_module.move_mark(name, direction)
	if success then
		debounced_save()
		notify("󰃀 Mark moved " .. direction, vim.log.levels.INFO)
		return { success = true, message = "Mark moved successfully", direction = direction }
	else
		return { success = false, message = "Cannot move mark " .. direction }
	end
end

---Show marks in floating window
---@param search_query string? Optional search query to filter marks
function M.show_marks(search_query)
	local storage_module = get_storage()
	local ui_module = get_ui()

	if not storage_module or not ui_module then
		notify("Failed to load required modules", vim.log.levels.ERROR)
		return
	end

	local marks = storage_module.get_marks()
	if vim.tbl_isempty(marks) then
		notify("No marks in current project", vim.log.levels.INFO)
		return
	end

	ui_module.show_marks_window(marks, storage_module.get_project_name(), search_query)
end

---Search marks by query
---@param query string Search query
---@return table filtered_marks Filtered marks matching the query
function M.search_marks(query)
	local storage_module = get_storage()
	local utils_module = get_utils()

	if not storage_module or not utils_module then
		notify("Failed to load required modules", vim.log.levels.ERROR)
		return {}
	end

	if not query or query == "" then
		return storage_module.get_marks()
	end

	local marks = storage_module.get_marks()
	local filtered = utils_module.filter_marks(marks, query)

	if vim.tbl_isempty(filtered) then
		notify("No marks found matching: " .. query, vim.log.levels.INFO)
		return {}
	end

	return filtered
end

---Get total number of marks
---@return number count Number of marks in current project
function M.get_marks_count()
	local storage_module = get_storage()
	if not storage_module then
		return 0
	end
	return storage_module.get_marks_count()
end

---Get all marks
---@return table marks All marks in current project
function M.get_marks()
	local storage_module = get_storage()
	if not storage_module then
		return {}
	end
	return storage_module.get_marks()
end

---Clear all marks with confirmation
function M.clear_all_marks()
	vim.ui.select({ "Yes", "No" }, {
		prompt = "Clear all marks in this project?",
	}, function(choice)
		if choice == "Yes" then
			local storage_module = get_storage()
			if storage_module then
				storage_module.clear_all_marks()
				debounced_save()
				notify("󰃀 All marks cleared", vim.log.levels.INFO)
			end
		end
	end)
end

---Export marks to JSON file
---@return table result Result with success and message
function M.export_marks()
	local storage_module = get_storage()
	if not storage_module then
		return { success = false, message = "Failed to load storage module" }
	end
	return storage_module.export_marks()
end

---Import marks from JSON file
---@return table result Result with success and message
function M.import_marks()
	local storage_module = get_storage()
	if not storage_module then
		return { success = false, message = "Failed to load storage module" }
	end
	return storage_module.import_marks()
end

---Get memory usage statistics
---@return table stats Memory usage statistics
function M.get_memory_usage()
	local storage_module = get_storage()
	if not storage_module then
		return { marks_count = 0, file_size = 0 }
	end

	local marks_count = storage_module.get_marks_count()
	local file_size = storage_module.get_storage_file_size()

	return {
		marks_count = marks_count,
		file_size = file_size,
		modules_loaded = {
			storage = storage ~= nil,
			ui = ui ~= nil,
			utils = utils ~= nil,
		},
	}
end

---Cleanup function to free memory and resources
function M.cleanup()
	-- Stop any pending save operations
	if save_timer then
		save_timer:stop()
		save_timer = nil
	end

	-- Cleanup modules
	if ui then
		if ui.cleanup then
			ui.cleanup()
		end
		ui = nil
	end
	if storage then
		if storage.cleanup then
			storage.cleanup()
		end
		storage = nil
	end
	if utils then
		utils = nil
	end

	config = {}
end

---Setup function to initialize the plugin
---@param opts table? User configuration options
function M.setup(opts)
	-- Validate and merge configuration
	local validated_opts = validate_config(opts, config_schema)
	config = vim.tbl_deep_extend("force", default_config, validated_opts)

	-- Create user commands with better error handling
	local commands = {
		{
			"MarkAdd",
			function(args)
				local result = M.add_mark(args.args ~= "" and args.args or nil)
				if not result.success then
					notify(result.message, vim.log.levels.WARN)
				end
			end,
			{ nargs = "?", desc = "Add a mark at current position" },
		},
		{
			"MarkGoto",
			function(args)
				if args.args == "" then
					M.show_marks()
				else
					local result = M.goto_mark(args.args)
					if not result.success then
						notify(result.message, vim.log.levels.WARN)
					end
				end
			end,
			{ nargs = "?", desc = "Jump to mark or show marks list" },
		},
		{
			"MarkDelete",
			function(args)
				if args.args == "" then
					M.clear_all_marks()
				else
					local result = M.delete_mark(args.args)
					if not result.success then
						notify(result.message, vim.log.levels.WARN)
					end
				end
			end,
			{ nargs = "?", desc = "Delete a mark or clear all marks" },
		},
		{
			"MarkRename",
			function(args)
				local parts = vim.split(args.args, " ", { plain = true })
				if #parts >= 2 then
					local old_name = parts[1]
					local new_name = table.concat(parts, " ", 2)
					local result = M.rename_mark(old_name, new_name)
					if not result.success then
						notify(result.message, vim.log.levels.WARN)
					end
				else
					notify("Usage: MarkRename <old_name> <new_name>", vim.log.levels.WARN)
				end
			end,
			{ nargs = "+", desc = "Rename a mark" },
		},
		{ "MarkList", M.show_marks, { desc = "Show all marks" } },
		{ "MarkClear", M.clear_all_marks, { desc = "Clear all marks" } },
		{ "MarkExport", M.export_marks, { desc = "Export marks to JSON" } },
		{ "MarkImport", M.import_marks, { desc = "Import marks from JSON" } },
		{
			"MarkSearch",
			function(args)
				local filtered = M.search_marks(args.args)
				if not vim.tbl_isempty(filtered) then
					M.show_marks(args.args)
				end
			end,
			{ nargs = 1, desc = "Search marks" },
		},
		{
			"MarkStats",
			function()
				local stats = M.get_memory_usage()
				local msg = string.format("Marks: %d, File size: %d bytes", stats.marks_count, stats.file_size)
				notify(msg, vim.log.levels.INFO)
			end,
			{ desc = "Show mark statistics" },
		},
	}

	for _, cmd in ipairs(commands) do
		vim.api.nvim_create_user_command(cmd[1], cmd[2], cmd[3])
	end

	-- Set keymaps if not disabled
	if not config.disable_default_keymaps and config.keymaps ~= false then
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
					local result = M.goto_mark(i)
					if not result.success then
						notify(result.message, vim.log.levels.WARN)
					end
				end, { desc = "Go to mark " .. i })
			end
		end
	end

	-- Setup cleanup on VimLeavePre
	vim.api.nvim_create_autocmd("VimLeavePre", {
		pattern = "*",
		callback = M.cleanup,
		desc = "Cleanup marksman resources",
	})
end

return M
