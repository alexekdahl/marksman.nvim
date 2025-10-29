-- luacheck: globals vim
local M = {}

-- Pattern matching for smart mark naming
local naming_patterns = {
	-- Lua
	{
		pattern = "function%s+([%w_.]+)",
		language = { "lua" },
		type = "function",
	},
	{
		pattern = "local%s+function%s+([%w_]+)",
		language = { "lua" },
		type = "function",
	},
	{
		pattern = "local%s+([%w_]+)%s*=%s*{",
		language = { "lua" },
		type = "table",
	},
	-- JavaScript/TypeScript
	{
		pattern = "function%s+([%w_]+)",
		language = { "js", "ts", "jsx", "tsx" },
		type = "function",
	},
	{
		pattern = "const%s+([%w_]+)%s*=%s*",
		language = { "js", "ts", "jsx", "tsx" },
		type = "const",
	},
	{
		pattern = "class%s+([%w_]+)",
		language = { "js", "ts", "jsx", "tsx" },
		type = "class",
	},
	-- Python
	{
		pattern = "def%s+([%w_]+)",
		language = { "py" },
		type = "function",
	},
	{
		pattern = "class%s+([%w_]+)",
		language = { "py" },
		type = "class",
	},
	-- Go
	{
		pattern = "func%s+([%w_]+)",
		language = { "go" },
		type = "function",
	},
	{
		pattern = "type%s+([%w_]+)%s+struct",
		language = { "go" },
		type = "struct",
	},
	-- Rust
	{
		pattern = "fn%s+([%w_]+)",
		language = { "rs" },
		type = "function",
	},
	{
		pattern = "struct%s+([%w_]+)",
		language = { "rs" },
		type = "struct",
	},
	-- C/C++
	{
		pattern = "class%s+([%w_]+)",
		language = { "cpp", "cc", "cxx" },
		type = "class",
	},
	{
		pattern = "struct%s+([%w_]+)",
		language = { "c", "cpp", "cc", "cxx" },
		type = "struct",
	},
	-- Java
	{
		pattern = "class%s+([%w_]+)",
		language = { "java" },
		type = "class",
	},
	{
		pattern = "interface%s+([%w_]+)",
		language = { "java" },
		type = "interface",
	},
	-- Generic patterns for many languages
	{
		pattern = "#define%s+([%w_]+)",
		language = { "c", "cpp", "h", "hpp" },
		type = "define",
	},
}

local function get_file_extension(filename)
	return vim.fn.fnamemodify(filename, ":e"):lower()
end

local function get_context_from_line(line, file_ext)
	if not line or line == "" then
		return nil
	end

	-- Clean the line
	local context = line:match("%s*(.-)%s*$")
	if not context or #context == 0 then
		return nil
	end

	-- Try language-specific patterns
	for _, pattern_info in ipairs(naming_patterns) do
		local matches_language = false
		for _, lang in ipairs(pattern_info.language) do
			if lang == file_ext then
				matches_language = true
				break
			end
		end

		if matches_language then
			local identifier = context:match(pattern_info.pattern)
			if identifier then
				return identifier, pattern_info.type
			end
		end
	end

	-- Fallback: look for any identifier pattern
	local fallback_patterns = {
		"([%w_]+)%s*[:=]", -- assignment patterns
		"([%w_]+)%s*{", -- opening brace patterns
		"([%w_]+)%s*%()", -- function call patterns
	}

	for _, pattern in ipairs(fallback_patterns) do
		local identifier = context:match(pattern)
		if identifier then
			return identifier, "identifier"
		end
	end

	return nil
end

local function get_surrounding_context(line_num, max_lines)
	max_lines = max_lines or 3
	local contexts = {}

	-- Look up and down for context
	for offset = -max_lines, max_lines do
		if offset ~= 0 then
			local context_line_num = line_num + offset
			if context_line_num > 0 and context_line_num <= vim.fn.line("$") then
				local context_line = vim.fn.getline(context_line_num)
				local identifier, type = get_context_from_line(context_line, get_file_extension(vim.fn.expand("%")))
				if identifier then
					table.insert(contexts, { identifier = identifier, type = type, distance = math.abs(offset) })
				end
			end
		end
	end

	-- Sort by distance (closest first)
	table.sort(contexts, function(a, b)
		return a.distance < b.distance
	end)

	return contexts[1] -- Return closest context
end

function M.generate_mark_name(bufname, line)
	local filename = vim.fn.fnamemodify(bufname, ":t:r")
	local file_ext = get_file_extension(bufname)
	local current_line = vim.fn.getline(".")

	-- Try to get context from current line
	local identifier, type = get_context_from_line(current_line, file_ext)

	-- If no context on current line, look at surrounding lines
	if not identifier then
		local context = get_surrounding_context(line)
		if context then
			identifier = context.identifier
			type = context.type
		end
	end

	-- Generate name based on what we found
	if identifier then
		local prefix = ""
		if type == "function" then
			prefix = "fn:"
		elseif type == "class" then
			prefix = "class:"
		elseif type == "struct" then
			prefix = "struct:"
		end
		return prefix .. identifier
	end

	-- Fallback to filename:line
	return filename .. ":" .. line
end

function M.filter_marks(marks, query)
	if not query or query == "" then
		return marks
	end

	local filtered = {}
	local search_terms = vim.split(query:lower(), "%s+")

	for name, mark in pairs(marks) do
		local searchable_text = (
			name
			.. " "
			.. (mark.description or "")
			.. " "
			.. vim.fn.fnamemodify(mark.file, ":t")
			.. " "
			.. vim.fn.fnamemodify(mark.file, ":p:h:t")
			.. " " -- parent directory
			.. (mark.text or "")
		):lower()

		local matches_all = true
		for _, term in ipairs(search_terms) do
			if not searchable_text:find(term, 1, true) then
				matches_all = false
				break
			end
		end

		if matches_all then
			filtered[name] = mark
		end
	end

	return filtered
end

function M.sanitize_mark_name(name)
	if not name or name == "" then
		return nil
	end

	-- Remove or replace problematic characters
	local sanitized = name:gsub('[<>:"/\\|?*]', "_") -- Replace filesystem-unsafe chars
	sanitized = sanitized:gsub("%s+", "_") -- Replace spaces with underscores
	sanitized = sanitized:gsub("_+", "_") -- Collapse multiple underscores
	sanitized = sanitized:gsub("^_+", "") -- Remove leading underscores
	sanitized = sanitized:gsub("_+$", "") -- Remove trailing underscores

	-- Ensure reasonable length
	if #sanitized > 50 then
		sanitized = sanitized:sub(1, 50):gsub("_*$", "")
	end

	return sanitized ~= "" and sanitized or nil
end

function M.get_relative_path(filepath, base_path)
	base_path = base_path or vim.fn.getcwd()

	-- Convert to absolute paths first
	local abs_file = vim.fn.fnamemodify(filepath, ":p")
	local abs_base = vim.fn.fnamemodify(base_path, ":p")

	-- Check if file is under base path
	if abs_file:sub(1, #abs_base) == abs_base then
		return abs_file:sub(#abs_base + 2) -- +2 to skip the trailing slash
	end

	-- Fallback to just filename if not under base
	return vim.fn.fnamemodify(filepath, ":t")
end

function M.format_file_path(filepath, max_length)
	max_length = max_length or 50

	local rel_path = M.get_relative_path(filepath)

	if #rel_path <= max_length then
		return rel_path
	end

	-- Try to abbreviate by showing just filename and parent dir
	local filename = vim.fn.fnamemodify(filepath, ":t")
	local parent = vim.fn.fnamemodify(filepath, ":h:t")
	local short_path = parent .. "/" .. filename

	if #short_path <= max_length then
		return ".../" .. short_path
	end

	-- Last resort: truncate from the beginning
	return "..." .. rel_path:sub(-(max_length - 3))
end

function M.validate_mark_data(mark)
	if type(mark) ~= "table" then
		return false, "Mark must be a table"
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

	return true
end

function M.merge_marks(base_marks, new_marks, strategy)
	strategy = strategy or "merge" -- "merge", "replace", "skip_existing"

	local result = vim.deepcopy(base_marks)

	for name, mark in pairs(new_marks) do
		local is_valid, error_msg = M.validate_mark_data(mark)
		if not is_valid then
			vim.notify("Skipping invalid mark '" .. name .. "': " .. error_msg, vim.log.levels.WARN)
		else
			if strategy == "replace" or not result[name] then
				result[name] = mark
			elseif strategy == "merge" then
				-- Update existing mark with new data, preserving some fields
				local existing = result[name]
				result[name] = vim.tbl_deep_extend("force", existing, mark)
				-- Preserve original creation time
				if existing.created_at then
					result[name].created_at = existing.created_at
				end
			end
			-- "skip_existing" does nothing if mark already exists
		end
	end

	return result
end

function M.get_mark_statistics(marks)
	local stats = {
		total = 0,
		by_extension = {},
		by_directory = {},
		access_frequency = {},
		age_distribution = {},
	}

	local now = os.time()

	for name, mark in pairs(marks) do
		stats.total = stats.total + 1

		-- File extension stats
		local ext = get_file_extension(mark.file)
		stats.by_extension[ext] = (stats.by_extension[ext] or 0) + 1

		-- Directory stats
		local dir = vim.fn.fnamemodify(mark.file, ":h:t")
		stats.by_directory[dir] = (stats.by_directory[dir] or 0) + 1

		-- Access frequency
		local access_count = mark.access_count or 0
		local freq_bucket = access_count == 0 and "never"
			or access_count < 5 and "low"
			or access_count < 20 and "medium"
			or "high"
		stats.access_frequency[freq_bucket] = (stats.access_frequency[freq_bucket] or 0) + 1

		-- Age distribution
		if mark.created_at then
			local age_days = math.floor((now - mark.created_at) / 86400)
			local age_bucket = age_days < 1 and "today"
				or age_days < 7 and "week"
				or age_days < 30 and "month"
				or "older"
			stats.age_distribution[age_bucket] = (stats.age_distribution[age_bucket] or 0) + 1
		end
	end

	return stats
end

function M.suggest_mark_name(bufname, line, existing_marks)
	local base_name = M.generate_mark_name(bufname, line)
	local sanitized = M.sanitize_mark_name(base_name)

	if not sanitized then
		sanitized = "mark_" .. line
	end

	-- Check for conflicts and add suffix if needed
	local final_name = sanitized
	local counter = 1

	while existing_marks[final_name] do
		final_name = sanitized .. "_" .. counter
		counter = counter + 1

		-- Prevent infinite loop
		if counter > 100 then
			final_name = sanitized .. "_" .. os.time()
			break
		end
	end

	return final_name
end

return M
