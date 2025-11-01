-- luacheck: globals vim
local M = {}

-- State
local marks = {}
local mark_order = {}
local current_project = nil
local config = {}

-- Helper function for conditional notifications
local function notify(message, level)
	if not config.silent then
		vim.notify(message, level)
	end
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
			notify("Failed to create backup: " .. tostring(err), vim.log.levels.WARN)
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
					marks = decoded.marks or decoded
					mark_order = decoded.mark_order or {}

					-- If mark_order is missing or incomplete, rebuild it
					if #mark_order == 0 then
						mark_order = {}
						for name in pairs(marks) do
							table.insert(mark_order, name)
						end
					end
				else
					marks = {}
					mark_order = {}
				end
			else
				marks = {}
				mark_order = {}
			end
		end)

		if not ok then
			notify("Error loading marks: " .. tostring(err), vim.log.levels.ERROR)
			marks = {}
			mark_order = {}
		end
	else
		marks = {}
		mark_order = {}
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
		local data = {
			marks = marks,
			mark_order = mark_order,
		}
		local json = vim.json.encode(data)
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
		vim.fn.writefile({ json }, file)
	end)

	if not ok then
		notify("Failed to save marks: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	return true
end

-- Public API
function M.setup(user_config)
	config = user_config or {}
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

function M.get_mark_names()
	-- Return marks in the order they were added/arranged
	local valid_names = {}
	for _, name in ipairs(mark_order) do
		if marks[name] then
			table.insert(valid_names, name)
		end
	end
	return valid_names
end

function M.add_mark(name, mark)
	if not name or name == "" then
		return false
	end

	local marks_data = M.get_marks()

	-- If mark doesn't exist, add it to the order
	if not marks_data[name] then
		table.insert(mark_order, name)
	end

	marks_data[name] = mark
	return save_marks()
end

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

	-- Update order
	for i, mark_name in ipairs(mark_order) do
		if mark_name == old_name then
			mark_order[i] = new_name
			break
		end
	end

	return save_marks()
end

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

	return save_marks()
end

function M.clear_all_marks()
	marks = {}
	mark_order = {}
	return save_marks()
end

function M.export_marks()
	local marks_data = M.get_marks()

	if vim.tbl_isempty(marks_data) then
		notify("No marks to export", vim.log.levels.INFO)
		return false
	end

	local export_data = {
		project = current_project,
		exported_at = os.date("%Y-%m-%d %H:%M:%S"),
		version = "2.0",
		marks = marks_data,
		mark_order = mark_order,
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
					notify("󰃀 Marks exported to " .. filename, vim.log.levels.INFO)
					return true
				else
					notify("Export failed: " .. tostring(err), vim.log.levels.ERROR)
					return false
				end
			end
		end)
	else
		notify("Failed to encode marks for export", vim.log.levels.ERROR)
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
			notify("File not found: " .. filename, vim.log.levels.WARN)
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
							mark_order = data.mark_order or {}
						elseif choice == "Merge" then
							marks = vim.tbl_deep_extend("force", marks_data, data.marks)
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
							return
						end

						if save_marks() then
							notify("󰃀 Marks imported successfully", vim.log.levels.INFO)
						else
							notify("Failed to save imported marks", vim.log.levels.ERROR)
						end
					end)
				else
					notify("Invalid marks file format", vim.log.levels.ERROR)
				end
			end
		end)

		if not ok then
			notify("Import failed: " .. tostring(err), vim.log.levels.ERROR)
		end
	end)
end

return M
