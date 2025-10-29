-- luacheck: globals vim
local M = {}

-- State
local marks = {}
local current_project = nil
local config = {}
local deletion_history = {}

-- Initialize deletion history as a circular buffer
local function init_deletion_history()
	deletion_history = {
		items = {},
		max_size = 0,
		current = 0,
	}
end

local function get_project_root()
	-- Try multiple methods to find project root
	local methods = {
		function()
			local git_root = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", "")
			return vim.v.shell_error == 0 and git_root or nil
		end,
		function()
			-- Look for common project files
			local project_files = {
				".git",
				"package.json",
				"Cargo.toml",
				"go.mod",
				"pyproject.toml",
				"composer.json",
			}
			local current_dir = vim.fn.expand("%:p:h")

			while current_dir ~= "/" and current_dir ~= "" do
				for _, file in ipairs(project_files) do
					if
						vim.fn.filereadable(current_dir .. "/" .. file) == 1
						or vim.fn.isdirectory(current_dir .. "/" .. file) == 1
					then
						return current_dir
					end
				end
				current_dir = vim.fn.fnamemodify(current_dir, ":h")
			end
			return nil
		end,
		function()
			return vim.fn.getcwd()
		end,
	}

	for _, method in ipairs(methods) do
		local result = method()
		if result then
			return result
		end
	end

	return vim.fn.getcwd()
end

local function get_marks_file()
	local project = get_project_root()
	local hash = vim.fn.sha256(project):sub(1, 8)
	local data_path = vim.fn.stdpath("data")
	return data_path .. "/marksman_" .. hash .. ".json"
end

local function backup_marks_file()
	local file = get_marks_file()
	local backup_file = file .. ".backup"

	if vim.fn.filereadable(file) == 1 then
		local ok, err = pcall(function()
			local content = vim.fn.readfile(file)
			vim.fn.writefile(content, backup_file)
		end)

		if not ok then
			vim.notify("Failed to create backup: " .. tostring(err), vim.log.levels.WARN)
		end
	end
end

local function load_marks()
	current_project = get_project_root()
	local file = get_marks_file()

	if vim.fn.filereadable(file) == 1 then
		local ok, err = pcall(function()
			local content = vim.fn.readfile(file)
			if #content > 0 then
				local decoded = vim.json.decode(table.concat(content, "\n"))
				if decoded and type(decoded) == "table" then
					marks = decoded
				else
					marks = {}
				end
			else
				marks = {}
			end
		end)

		if not ok then
			vim.notify("Error loading marks: " .. tostring(err), vim.log.levels.ERROR)
			marks = {}
		end
	else
		marks = {}
	end

	return marks
end

local function save_marks()
	if not config.auto_save then
		return false
	end

	local file = get_marks_file()

	-- Create backup before saving
	backup_marks_file()

	local ok, err = pcall(function()
		local json = vim.json.encode(marks)
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
		vim.fn.writefile({ json }, file)
	end)

	if not ok then
		vim.notify("Failed to save marks: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	return true
end

local function add_to_deletion_history(name, mark)
	if deletion_history.max_size <= 0 then
		return
	end

	local item = {
		name = name,
		mark = vim.deepcopy(mark),
		deleted_at = os.time(),
	}

	-- Add to circular buffer
	deletion_history.current = (deletion_history.current % deletion_history.max_size) + 1
	deletion_history.items[deletion_history.current] = item
end

-- Public API
function M.setup(user_config)
	config = user_config or {}
	init_deletion_history()
	deletion_history.max_size = config.undo_levels or 10
	load_marks()
end

function M.get_marks()
	if vim.tbl_isempty(marks) then
		load_marks()
	end
	return marks
end

function M.get_marks_count()
	return vim.tbl_count(M.get_marks())
end

function M.get_project_name()
	return vim.fn.fnamemodify(current_project or get_project_root(), ":t")
end

function M.get_sorted_mark_names()
	local mark_names = {}
	local marks_data = M.get_marks()

	for name in pairs(marks_data) do
		table.insert(mark_names, name)
	end

	table.sort(mark_names, function(a, b)
		local mark_a = marks_data[a]
		local mark_b = marks_data[b]
		-- Sort by access time first, then creation time
		local time_a = mark_a.accessed_at or mark_a.created_at or 0
		local time_b = mark_b.accessed_at or mark_b.created_at or 0
		return time_a > time_b
	end)

	return mark_names
end

function M.add_mark(name, mark)
	if not name or name == "" then
		return false
	end

	local marks_data = M.get_marks()
	marks_data[name] = mark
	return save_marks()
end

function M.delete_mark(name)
	local marks_data = M.get_marks()

	if marks_data[name] then
		-- Add to deletion history before removing
		add_to_deletion_history(name, marks_data[name])
		marks_data[name] = nil
		return save_marks()
	end

	return false
end

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

	marks_data[new_name] = marks_data[old_name]
	marks_data[old_name] = nil
	return save_marks()
end

function M.update_mark_access(name)
	local marks_data = M.get_marks()

	if marks_data[name] then
		marks_data[name].accessed_at = os.time()
		return save_marks()
	end

	return false
end

function M.update_mark_description(name, description)
	local marks_data = M.get_marks()

	if marks_data[name] then
		marks_data[name].description = description or ""
		return save_marks()
	end

	return false
end

function M.clear_all_marks()
	marks = {}
	return save_marks()
end

function M.undo_last_deletion()
	if deletion_history.max_size <= 0 or #deletion_history.items == 0 then
		return nil
	end

	-- Find the most recent deletion
	local latest_item = nil
	local latest_time = 0
	local latest_index = nil

	for i, item in ipairs(deletion_history.items) do
		if item and item.deleted_at > latest_time then
			latest_item = item
			latest_time = item.deleted_at
			latest_index = i
		end
	end

	if latest_item then
		-- Restore the mark
		local marks_data = M.get_marks()
		marks_data[latest_item.name] = latest_item.mark
		save_marks()

		-- Remove from deletion history
		deletion_history.items[latest_index] = nil

		return latest_item.name
	end

	return nil
end

function M.export_marks()
	local marks_data = M.get_marks()

	if vim.tbl_isempty(marks_data) then
		vim.notify("No marks to export", vim.log.levels.INFO)
		return false
	end

	local export_data = {
		project = current_project,
		exported_at = os.date("%Y-%m-%d %H:%M:%S"),
		version = "2.0",
		marks = marks_data,
	}

	local ok, json = pcall(vim.json.encode, export_data)
	if ok then
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
					vim.notify("󰃀 Marks exported to " .. filename, vim.log.levels.INFO)
					return true
				else
					vim.notify("Export failed: " .. tostring(err), vim.log.levels.ERROR)
					return false
				end
			end
		end)
	else
		vim.notify("Failed to encode marks for export", vim.log.levels.ERROR)
		return false
	end
end

function M.import_marks()
	vim.ui.input({
		prompt = "Import from: ",
		default = "",
		completion = "file",
	}, function(filename)
		if not filename or filename == "" then
			return
		end

		if vim.fn.filereadable(filename) == 0 then
			vim.notify("File not found: " .. filename, vim.log.levels.WARN)
			return
		end

		local ok, err = pcall(function()
			local content = vim.fn.readfile(filename)
			if #content > 0 then
				local data = vim.json.decode(table.concat(content, "\n"))
				if data and data.marks then
					local marks_data = M.get_marks()

					-- Ask about merge strategy
					vim.ui.select({ "Merge", "Replace" }, {
						prompt = "Import strategy:",
					}, function(choice)
						if choice == "Replace" then
							marks = data.marks
						elseif choice == "Merge" then
							marks = vim.tbl_deep_extend("force", marks_data, data.marks)
						else
							return
						end

						if save_marks() then
							vim.notify("󰃀 Marks imported successfully", vim.log.levels.INFO)
						else
							vim.notify("Failed to save imported marks", vim.log.levels.ERROR)
						end
					end)
				else
					vim.notify("Invalid marks file format", vim.log.levels.ERROR)
				end
			end
		end)

		if not ok then
			vim.notify("Import failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end)
end

function M.validate_marks()
	local marks_data = M.get_marks()
	local invalid_marks = {}

	for name, mark in pairs(marks_data) do
		if not mark.file or vim.fn.filereadable(mark.file) == 0 then
			table.insert(invalid_marks, name)
		end
	end

	if #invalid_marks > 0 then
		vim.ui.select({ "Remove", "Keep", "Show" }, {
			prompt = string.format("Found %d invalid mark(s). Action:", #invalid_marks),
		}, function(choice)
			if choice == "Remove" then
				for _, name in ipairs(invalid_marks) do
					M.delete_mark(name)
				end
				vim.notify(string.format("Removed %d invalid marks", #invalid_marks), vim.log.levels.INFO)
			elseif choice == "Show" then
				vim.notify("Invalid marks: " .. table.concat(invalid_marks, ", "), vim.log.levels.INFO)
			end
		end)
	else
		vim.notify("All marks are valid", vim.log.levels.INFO)
	end

	return invalid_marks
end

function M.get_statistics()
	local marks_data = M.get_marks()
	local stats = {
		total_marks = vim.tbl_count(marks_data),
		project = M.get_project_name(),
		oldest_mark = nil,
		newest_mark = nil,
		most_accessed = nil,
		file_distribution = {},
	}

	local oldest_time = math.huge
	local newest_time = 0
	local max_access_count = 0

	for name, mark in pairs(marks_data) do
		-- Track oldest/newest
		local created_time = mark.created_at or 0
		if created_time < oldest_time then
			oldest_time = created_time
			stats.oldest_mark = name
		end
		if created_time > newest_time then
			newest_time = created_time
			stats.newest_mark = name
		end

		-- Track access patterns
		local access_count = mark.access_count or 0
		if access_count > max_access_count then
			max_access_count = access_count
			stats.most_accessed = name
		end

		-- File distribution
		local file = vim.fn.fnamemodify(mark.file, ":t")
		stats.file_distribution[file] = (stats.file_distribution[file] or 0) + 1
	end

	return stats
end

return M
