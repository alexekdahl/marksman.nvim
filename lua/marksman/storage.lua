-- luacheck: globals vim
---@class Storage
---@field marks table Current marks data
---@field mark_order table Order of marks
---@field current_project string Current project path
---@field config table Plugin configuration
local M = {}

-- State
local marks = {}
local mark_order = {}
local current_project = nil
local config = {}

-- Cache for project root detection
local project_root_cache = {}
local cache_expiry = {}

---Helper function for conditional notifications
---@param message string The notification message
---@param level number The log level
local function notify(message, level)
	if not config.silent then
		vim.notify(message, level)
	end
end

---Detect project root using multiple methods with caching
---@return string project_root The project root directory
local function get_project_root()
	local current_dir = vim.fn.expand("%:p:h")

	-- Check cache first (expires after 30 seconds)
	local cache_key = current_dir
	local now = os.time()
	if project_root_cache[cache_key] and cache_expiry[cache_key] and cache_expiry[cache_key] > now then
		return project_root_cache[cache_key]
	end

	-- Try multiple methods to find project root
	local methods = {
		-- Git repository root
		function()
			local ok, git_root = pcall(function()
				local result = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
				return vim.v.shell_error == 0 and result or nil
			end)
			return ok and git_root or nil
		end,
		-- Look for common project files
		function()
			local project_files = {
				".git",
				"package.json",
				"Cargo.toml",
				"go.mod",
				"pyproject.toml",
				"composer.json",
				"Makefile",
				".editorconfig",
				"tsconfig.json",
			}
			local search_dir = current_dir

			while search_dir ~= "/" and search_dir ~= "" do
				for _, file in ipairs(project_files) do
					local path = search_dir .. "/" .. file
					if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
						return search_dir
					end
				end
				search_dir = vim.fn.fnamemodify(search_dir, ":h")
			end
			return nil
		end,
		-- Fallback to current working directory
		function()
			return vim.fn.getcwd()
		end,
	}

	local result = nil
	for _, method in ipairs(methods) do
		local ok, root = pcall(method)
		if ok and root and root ~= "" then
			result = root
			break
		end
	end

	-- Cache the result
	result = result or vim.fn.getcwd()
	project_root_cache[cache_key] = result
	cache_expiry[cache_key] = now + 30 -- Cache for 30 seconds

	return result
end

---Get the marks storage file path
---@return string file_path Path to the marks storage file
local function get_marks_file()
	local project = get_project_root()
	if not project then
		error("Could not determine project root")
	end

	local hash = vim.fn.sha256(project):sub(1, 8)
	local data_path = vim.fn.stdpath("data")
	if not data_path then
		error("Could not get Neovim data directory")
	end

	return data_path .. "/marksman_" .. hash .. ".json"
end

---Create backup of marks file
---@return boolean success Whether backup was created successfully
local function backup_marks_file()
	local file = get_marks_file()
	local backup_file = file .. ".backup"

	if vim.fn.filereadable(file) == 1 then
		local ok, err = pcall(function()
			local content = vim.fn.readfile(file)
			vim.fn.writefile(content, backup_file)
		end)

		if not ok then
			notify("Failed to create backup: " .. tostring(err), vim.log.levels.WARN)
			return false
		end
		return true
	end
	return false
end

---Restore marks from backup file
---@return boolean success Whether restoration was successful
local function restore_from_backup()
	local file = get_marks_file()
	local backup_file = file .. ".backup"

	if vim.fn.filereadable(backup_file) == 1 then
		local ok, err = pcall(function()
			local content = vim.fn.readfile(backup_file)
			vim.fn.writefile(content, file)
		end)

		if ok then
			notify("Restored marks from backup", vim.log.levels.INFO)
			return true
		else
			notify("Failed to restore from backup: " .. tostring(err), vim.log.levels.ERROR)
		end
	end
	return false
end

---Validate marks file data structure
---@param data table The data to validate
---@return boolean valid Whether the data is valid
---@return string|nil error Error message if invalid
local function validate_marks_data(data)
	if type(data) ~= "table" then
		return false, "Data must be a table"
	end

	-- Handle legacy format (just marks)
	if data.marks then
		data = data.marks
	end

	for name, mark in pairs(data) do
		if type(name) ~= "string" or name == "" then
			return false, "Mark names must be non-empty strings"
		end

		if type(mark) ~= "table" then
			return false, "Mark data must be a table"
		end

		local required_fields = { "file", "line", "col" }
		for _, field in ipairs(required_fields) do
			if not mark[field] then
				return false, "Missing required field: " .. field
			end
		end

		if type(mark.line) ~= "number" or mark.line < 1 then
			return false, "Line must be a positive number"
		end

		if type(mark.col) ~= "number" or mark.col < 1 then
			return false, "Column must be a positive number"
		end

		if type(mark.file) ~= "string" or mark.file == "" then
			return false, "File must be a non-empty string"
		end
	end

	return true
end

---Load marks from storage file
---@return table marks The loaded marks
local function load_marks()
	current_project = get_project_root()
	local file = get_marks_file()

	-- Initialize empty state
	marks = {}
	mark_order = {}

	if vim.fn.filereadable(file) == 1 then
		local ok, err = pcall(function()
			local content = vim.fn.readfile(file)
			if #content > 0 then
				local raw_data = table.concat(content, "\n")
				if raw_data and raw_data ~= "" then
					local decoded = vim.json.decode(raw_data)
					if decoded then
						-- Validate the loaded data
						local valid, validation_error = validate_marks_data(decoded.marks or decoded)
						if not valid then
							error("Invalid marks data: " .. validation_error)
						end

						marks = decoded.marks or decoded
						mark_order = decoded.mark_order or {}

						-- Rebuild mark_order if missing or incomplete
						local mark_names = vim.tbl_keys(marks)
						if #mark_order == 0 or #mark_order ~= #mark_names then
							mark_order = {}
							for name in pairs(marks) do
								table.insert(mark_order, name)
							end
						end

						-- Remove invalid entries from mark_order
						local valid_order = {}
						for _, name in ipairs(mark_order) do
							if marks[name] then
								table.insert(valid_order, name)
							end
						end
						mark_order = valid_order
					end
				end
			end
		end)

		if not ok then
			notify("Error loading marks: " .. tostring(err), vim.log.levels.ERROR)
			-- Try to restore from backup
			if restore_from_backup() then
				-- Recursive call to load from restored backup
				return load_marks()
			end
			marks = {}
			mark_order = {}
		end
	end

	return marks
end

---Save marks to storage file with comprehensive error handling
---@return boolean success Whether save was successful
function M.save_marks()
	if not config.auto_save then
		return false
	end

	-- Validate data before saving
	if not marks or type(marks) ~= "table" then
		notify("Invalid marks data - cannot save", vim.log.levels.ERROR)
		return false
	end

	local valid, err = validate_marks_data(marks)
	if not valid then
		notify("Invalid marks data: " .. err, vim.log.levels.ERROR)
		return false
	end

	local file = get_marks_file()

	-- Create backup before saving
	backup_marks_file()

	local ok, save_err = pcall(function()
		local data = {
			marks = marks,
			mark_order = mark_order,
			version = "2.1",
			saved_at = os.date("%Y-%m-%d %H:%M:%S"),
			project = current_project,
		}

		local json = vim.json.encode(data)
		if not json then
			error("Failed to encode marks data")
		end

		-- Ensure directory exists
		local dir = vim.fn.fnamemodify(file, ":h")
		if vim.fn.isdirectory(dir) == 0 then
			local mkdir_result = vim.fn.mkdir(dir, "p")
			if mkdir_result == 0 then
				error("Failed to create directory: " .. dir)
			end
		end

		-- Write file atomically (write to temp file first)
		local temp_file = file .. ".tmp"
		local write_result = vim.fn.writefile({ json }, temp_file)
		if write_result ~= 0 then
			error("Failed to write temporary file")
		end

		-- Move temp file to final location
		local rename_ok = os.rename(temp_file, file)
		if not rename_ok then
			error("Failed to move temporary file to final location")
		end
	end)

	if not ok then
		notify("Failed to save marks: " .. tostring(save_err), vim.log.levels.ERROR)
		-- Try to restore from backup
		restore_from_backup()
		return false
	end

	return true
end

-- Public API

---Setup the storage module
---@param user_config table Plugin configuration
function M.setup(user_config)
	config = user_config or {}
	load_marks()
end

---Get all marks
---@return table marks Current marks
function M.get_marks()
	if vim.tbl_isempty(marks) then
		load_marks()
	end
	return marks
end

---Get number of marks
---@return number count Number of marks
function M.get_marks_count()
	return vim.tbl_count(M.get_marks())
end

---Get current project name
---@return string project_name Project name
function M.get_project_name()
	local project = current_project or get_project_root()
	return vim.fn.fnamemodify(project, ":t")
end

---Get ordered list of mark names
---@return table mark_names Ordered mark names
function M.get_mark_names()
	local valid_names = {}
	for _, name in ipairs(mark_order) do
		if marks[name] then
			table.insert(valid_names, name)
		end
	end
	return valid_names
end

---Add a new mark
---@param name string Mark name
---@param mark table Mark data
---@return boolean success Whether mark was added
function M.add_mark(name, mark)
	if not name or name == "" then
		return false
	end

	if type(mark) ~= "table" then
		return false
	end

	local marks_data = M.get_marks()

	-- Validate mark data
	local utils = require("marksman.utils")
	local valid, err = utils.validate_mark_data(mark)
	if not valid then
		notify("Invalid mark data: " .. err, vim.log.levels.ERROR)
		return false
	end

	-- If mark doesn't exist, add it to the order
	if not marks_data[name] then
		table.insert(mark_order, name)
	end

	marks_data[name] = mark
	return true -- Save is handled by debounced save in main module
end

---Delete a mark
---@param name string Mark name to delete
---@return boolean success Whether mark was deleted
function M.delete_mark(name)
	local marks_data = M.get_marks()

	if marks_data[name] then
		marks_data[name] = nil

		-- Remove from order
		for i, mark_name in ipairs(mark_order) do
			if mark_name == name then
				table.remove(mark_order, i)
				break
			end
		end

		return true
	end

	return false
end

---Rename a mark
---@param old_name string Current mark name
---@param new_name string New mark name
---@return boolean success Whether mark was renamed
function M.rename_mark(old_name, new_name)
	if not old_name or not new_name or old_name == new_name then
		return false
	end

	local marks_data = M.get_marks()

	if not marks_data[old_name] then
		return false
	end

	if marks_data[new_name] then
		return false -- Name already exists
	end

	-- Transfer mark data
	marks_data[new_name] = marks_data[old_name]
	marks_data[old_name] = nil

	-- Update order
	for i, mark_name in ipairs(mark_order) do
		if mark_name == old_name then
			mark_order[i] = new_name
			break
		end
	end

	return true
end

---Move a mark up or down in the order
---@param name string Mark name to move
---@param direction string "up" or "down"
---@return boolean success Whether mark was moved
function M.move_mark(name, direction)
	local current_index = nil

	-- Find current index
	for i, mark_name in ipairs(mark_order) do
		if mark_name == name then
			current_index = i
			break
		end
	end

	if not current_index then
		return false
	end

	local new_index
	if direction == "up" then
		new_index = current_index - 1
	elseif direction == "down" then
		new_index = current_index + 1
	else
		return false
	end

	-- Check bounds
	if new_index < 1 or new_index > #mark_order then
		return false
	end

	-- Swap positions
	mark_order[current_index], mark_order[new_index] = mark_order[new_index], mark_order[current_index]

	return true
end

---Clear all marks
---@return boolean success Whether marks were cleared
function M.clear_all_marks()
	marks = {}
	mark_order = {}
	return true
end

---Export marks to JSON file
---@return table result Export result with success status
function M.export_marks()
	local marks_data = M.get_marks()

	if vim.tbl_isempty(marks_data) then
		notify("No marks to export", vim.log.levels.INFO)
		return { success = false, message = "No marks to export" }
	end

	local export_data = {
		project = current_project,
		exported_at = os.date("%Y-%m-%d %H:%M:%S"),
		version = "2.1",
		marks = marks_data,
		mark_order = mark_order,
		metadata = {
			total_marks = vim.tbl_count(marks_data),
			project_name = M.get_project_name(),
		},
	}

	local ok, json = pcall(vim.json.encode, export_data)
	if not ok then
		return { success = false, message = "Failed to encode marks for export" }
	end

	vim.ui.input({
		prompt = "Export to: ",
		default = "marks_export_" .. os.date("%Y%m%d") .. ".json",
		completion = "file",
	}, function(filename)
		if filename and filename ~= "" then
			local success, err = pcall(function()
				vim.fn.writefile({ json }, filename)
			end)

			if success then
				notify("󰃀 Marks exported to " .. filename, vim.log.levels.INFO)
				return { success = true, message = "Marks exported successfully", filename = filename }
			else
				notify("Export failed: " .. tostring(err), vim.log.levels.ERROR)
				return { success = false, message = "Export failed: " .. tostring(err) }
			end
		end
	end)

	return { success = true, message = "Export initiated" }
end

---Import marks from JSON file
---@return table result Import result with success status
function M.import_marks()
	vim.ui.input({
		prompt = "Import from: ",
		default = "",
		completion = "file",
	}, function(filename)
		if not filename or filename == "" then
			return { success = false, message = "No file specified" }
		end

		if vim.fn.filereadable(filename) == 0 then
			notify("File not found: " .. filename, vim.log.levels.WARN)
			return { success = false, message = "File not found: " .. filename }
		end

		local ok, err = pcall(function()
			local content = vim.fn.readfile(filename)
			if #content > 0 then
				local data = vim.json.decode(table.concat(content, "\n"))
				if data and data.marks then
					-- Validate imported marks
					local valid, validation_err = validate_marks_data(data.marks)
					if not valid then
						error("Invalid marks file: " .. validation_err)
					end

					local marks_data = M.get_marks()

					-- Ask about merge strategy
					vim.ui.select({ "Merge", "Replace" }, {
						prompt = "Import strategy:",
					}, function(choice)
						if choice == "Replace" then
							marks = data.marks
							mark_order = data.mark_order or {}
						elseif choice == "Merge" then
							-- Merge marks
							for name, mark in pairs(data.marks) do
								marks_data[name] = mark
							end

							-- Merge order arrays, avoiding duplicates
							if data.mark_order then
								for _, name in ipairs(data.mark_order) do
									local exists = false
									for _, existing_name in ipairs(mark_order) do
										if existing_name == name then
											exists = true
											break
										end
									end
									if not exists and marks[name] then
										table.insert(mark_order, name)
									end
								end
							end
						else
							return { success = false, message = "Import cancelled" }
						end

						if M.save_marks() then
							notify("󰃀 Marks imported successfully", vim.log.levels.INFO)
							return { success = true, message = "Marks imported successfully" }
						else
							notify("Failed to save imported marks", vim.log.levels.ERROR)
							return { success = false, message = "Failed to save imported marks" }
						end
					end)
				else
					error("Invalid marks file format")
				end
			else
				error("Empty file")
			end
		end)

		if not ok then
			notify("Import failed: " .. tostring(err), vim.log.levels.ERROR)
			return { success = false, message = "Import failed: " .. tostring(err) }
		end
	end)

	return { success = true, message = "Import initiated" }
end

---Get storage file size in bytes
---@return number size File size in bytes
function M.get_storage_file_size()
	local file = get_marks_file()
	return vim.fn.getfsize(file)
end

---Cleanup storage module
function M.cleanup()
	-- Clear caches
	project_root_cache = {}
	cache_expiry = {}

	-- Reset state
	marks = {}
	mark_order = {}
	current_project = nil
	config = {}
end

return M
