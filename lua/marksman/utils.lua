-- luacheck: globals vim
---@class Utils
local M = {}

-- Pattern matching for smart mark naming with expanded language support
local naming_patterns = {
	-- Lua patterns
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
	{
		pattern = "M%.([%w_]+)%s*=%s*function",
		language = { "lua" },
		type = "method",
	},
	
	-- JavaScript/TypeScript patterns
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
		pattern = "let%s+([%w_]+)%s*=%s*",
		language = { "js", "ts", "jsx", "tsx" },
		type = "variable",
	},
	{
		pattern = "class%s+([%w_]+)",
		language = { "js", "ts", "jsx", "tsx" },
		type = "class",
	},
	{
		pattern = "export%s+function%s+([%w_]+)",
		language = { "js", "ts", "jsx", "tsx" },
		type = "export",
	},
	{
		pattern = "([%w_]+)%s*:%s*function",
		language = { "js", "ts", "jsx", "tsx" },
		type = "method",
	},
	
	-- Python patterns
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
	{
		pattern = "async%s+def%s+([%w_]+)",
		language = { "py" },
		type = "async_function",
	},
	
	-- Go patterns
	{
		pattern = "func%s+([%w_]+)",
		language = { "go" },
		type = "function",
	},
	{
		pattern = "func%s+%([^%)]*%)%s+([%w_]+)",
		language = { "go" },
		type = "method",
	},
	{
		pattern = "type%s+([%w_]+)%s+struct",
		language = { "go" },
		type = "struct",
	},
	{
		pattern = "type%s+([%w_]+)%s+interface",
		language = { "go" },
		type = "interface",
	},
	
	-- Rust patterns
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
	{
		pattern = "enum%s+([%w_]+)",
		language = { "rs" },
		type = "enum",
	},
	{
		pattern = "trait%s+([%w_]+)",
		language = { "rs" },
		type = "trait",
	},
	{
		pattern = "impl%s+([%w_]+)",
		language = { "rs" },
		type = "impl",
	},
	
	-- C/C++ patterns
	{
		pattern = "class%s+([%w_]+)",
		language = { "cpp", "cc", "cxx", "hpp" },
		type = "class",
	},
	{
		pattern = "struct%s+([%w_]+)",
		language = { "c", "cpp", "cc", "cxx", "h", "hpp" },
		type = "struct",
	},
	{
		pattern = "enum%s+([%w_]+)",
		language = { "c", "cpp", "cc", "cxx", "h", "hpp" },
		type = "enum",
	},
	{
		pattern = "typedef%s+struct%s+([%w_]+)",
		language = { "c", "h" },
		type = "typedef",
	},
	
	-- Java patterns
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
	{
		pattern = "enum%s+([%w_]+)",
		language = { "java" },
		type = "enum",
	},
	{
		pattern = "public%s+class%s+([%w_]+)",
		language = { "java" },
		type = "class",
	},
	
	-- Generic patterns
	{
		pattern = "#define%s+([%w_]+)",
		language = { "c", "cpp", "h", "hpp" },
		type = "define",
	},
}

---Get file extension from filename
---@param filename string File path
---@return string extension File extension in lowercase
local function get_file_extension(filename)
	return vim.fn.fnamemodify(filename, ":e"):lower()
end

---Extract context information from a line of code
---@param line string Code line to analyze
---@param file_ext string File extension
---@return string|nil identifier Extracted identifier
---@return string|nil type Type of identifier (function, class, etc.)
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
			if identifier and identifier ~= "" then
				return identifier, pattern_info.type
			end
		end
	end

	-- Fallback patterns
	local fallback_patterns = {
		"([%w_]+)%s*[:=]", -- assignment patterns
		"([%w_]+)%s*{", -- opening brace patterns
		"([%w_]+)%s*%(", -- function call patterns
	}

	for _, pattern in ipairs(fallback_patterns) do
		local identifier = context:match(pattern)
		if identifier and identifier ~= "" then
			return identifier, "identifier"
		end
	end

	return nil
end

---Get surrounding context from nearby lines
---@param line_num number Current line number
---@param max_lines number Maximum lines to search (default: 3)
---@return table|nil context Context information with identifier, type, and distance
local function get_surrounding_context(line_num, max_lines)
	max_lines = max_lines or 3
	local contexts = {}
	local file_ext = get_file_extension(vim.fn.expand("%"))

	-- Look up and down for context
	for offset = -max_lines, max_lines do
		if offset ~= 0 then
			local context_line_num = line_num + offset
			if context_line_num > 0 and context_line_num <= vim.fn.line("$") then
				local context_line = vim.fn.getline(context_line_num)
				local identifier, type = get_context_from_line(context_line, file_ext)
				if identifier then
					table.insert(contexts, {
						identifier = identifier,
						type = type,
						distance = math.abs(offset),
					})
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

-- Public API

---Validate mark name according to rules
---@param name string Mark name to validate
---@return boolean valid Whether the name is valid
---@return string|nil error Error message if invalid
function M.validate_mark_name(name)
	if not name or type(name) ~= "string" then
		return false, "Mark name must be a string"
	end

	if name:match("^%s*$") then
		return false, "Mark name cannot be empty or whitespace"
	end

	if #name > 50 then
		return false, "Mark name too long (max 50 characters)"
	end

	if #name < 1 then
		return false, "Mark name too short (min 1 character)"
	end

	-- Check for invalid characters
	if name:match('[<>:"/\\|?*]') then
		return false, "Mark name contains invalid characters: < > : \" / \\ | ? *"
	end

	-- Check for reserved names
	local reserved_names = { "CON", "PRN", "AUX", "NUL" }
	local upper_name = name:upper()
	for _, reserved in ipairs(reserved_names) do
		if upper_name == reserved then
			return false, "Mark name cannot be a reserved system name"
		end
	end

	return true
end

---Validate mark data structure
---@param mark table Mark data to validate
---@return boolean valid Whether the mark is valid
---@return string|nil error Error message if invalid
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

	-- Validate file exists and is readable
	if vim.fn.filereadable(mark.file) == 0 then
		return false, "File does not exist or is not readable: " .. mark.file
	end

	-- Validate optional fields
	if mark.text and type(mark.text) ~= "string" then
		return false, "Text field must be a string"
	end

	if mark.description and type(mark.description) ~= "string" then
		return false, "Description field must be a string"
	end

	if mark.created_at and type(mark.created_at) ~= "number" then
		return false, "Created_at field must be a number (timestamp)"
	end

	return true
end

---Generate intelligent mark name based on code context
---@param bufname string Buffer file path
---@param line number Line number
---@return string mark_name Generated mark name
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
		if type == "function" or type == "async_function" then
			prefix = "fn:"
		elseif type == "class" then
			prefix = "class:"
		elseif type == "struct" then
			prefix = "struct:"
		elseif type == "method" then
			prefix = "method:"
		elseif type == "interface" then
			prefix = "interface:"
		elseif type == "enum" then
			prefix = "enum:"
		elseif type == "trait" then
			prefix = "trait:"
		elseif type == "const" or type == "variable" then
			prefix = "var:"
		end
		return prefix .. identifier
	end

	-- Fallback to filename:line
	return filename .. ":" .. line
end

---Filter marks based on search query
---@param marks table All marks
---@param query string Search query
---@return table filtered_marks Marks matching the query
function M.filter_marks(marks, query)
	if not query or query == "" then
		return marks
	end

	local filtered = {}
	local search_terms = vim.split(query:lower(), "%s+")

	for name, mark in pairs(marks) do
		-- Create searchable text from multiple sources
		local searchable_parts = {
			name,
			vim.fn.fnamemodify(mark.file, ":t"), -- filename
			vim.fn.fnamemodify(mark.file, ":p:h:t"), -- parent directory
			mark.text or "", -- line content
			mark.description or "", -- description if available
		}
		
		local searchable_text = table.concat(searchable_parts, " "):lower()

		-- Check if all search terms match
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

---Sanitize mark name for safe filesystem usage
---@param name string Raw mark name
---@return string|nil sanitized_name Sanitized name or nil if invalid
function M.sanitize_mark_name(name)
	if not name or name == "" then
		return nil
	end

	-- Replace or remove problematic characters
	local sanitized = name:gsub('[<>:"/\\|?*]', "_") -- Replace filesystem-unsafe chars
	sanitized = sanitized:gsub("%s+", "_") -- Replace spaces with underscores
	sanitized = sanitized:gsub("_+", "_") -- Collapse multiple underscores
	sanitized = sanitized:gsub("^_+", "") -- Remove leading underscores
	sanitized = sanitized:gsub("_+$", "") -- Remove trailing underscores

	-- Ensure reasonable length
	if #sanitized > 50 then
		sanitized = sanitized:sub(1, 50):gsub("_*$", "")
	end

	-- Ensure minimum length
	if #sanitized < 1 then
		return nil
	end

	return sanitized
end

---Get relative path from base directory
---@param filepath string Full file path
---@param base_path string|nil Base directory (default: cwd)
---@return string relative_path Relative path
function M.get_relative_path(filepath, base_path)
	base_path = base_path or vim.fn.getcwd()

	-- Convert to absolute paths first
	local abs_file = vim.fn.fnamemodify(filepath, ":p")
	local abs_base = vim.fn.fnamemodify(base_path, ":p")

	-- Ensure base path ends with separator
	if not abs_base:match("/$") then
		abs_base = abs_base .. "/"
	end

	-- Check if file is under base path
	if abs_file:sub(1, #abs_base) == abs_base then
		return abs_file:sub(#abs_base + 1)
	end

	-- Fallback to just filename if not under base
	return vim.fn.fnamemodify(filepath, ":t")
end

---Format file path for display with length limit
---@param filepath string Full file path
---@param max_length number|nil Maximum display length (default: 50)
---@return string formatted_path Formatted path
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

---Merge marks with different strategies
---@param base_marks table Base marks
---@param new_marks table New marks to merge
---@param strategy string|nil Merge strategy: "merge", "replace", "skip_existing"
---@return table merged_marks Merged marks
function M.merge_marks(base_marks, new_marks, strategy)
	strategy = strategy or "merge"

	local result = vim.deepcopy(base_marks)

	for name, mark in pairs(new_marks) do
		local is_valid, error_msg = M.validate_mark_data(mark)
		if not is_valid then
			vim.notify("Skipping invalid mark '" .. name .. "': " .. error_msg, vim.log.levels.WARN)
		else
			if strategy == "replace" or not result[name] then
				result[name] = mark
			elseif strategy == "merge" then
				result[name] = vim.tbl_deep_extend("force", result[name], mark)
			elseif strategy == "skip_existing" then
				-- Don't overwrite existing marks
				if not result[name] then
					result[name] = mark
				end
			end
		end
	end

	return result
end

---Suggest a unique mark name based on existing marks
---@param bufname string Buffer file path
---@param line number Line number
---@param existing_marks table Existing marks to avoid conflicts
---@return string suggested_name Unique suggested name
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

---Get statistics about marks
---@param marks table All marks
---@return table stats Statistics about the marks
function M.get_marks_statistics(marks)
	local stats = {
		total_marks = vim.tbl_count(marks),
		file_count = 0,
		files = {},
		types = {},
		oldest_mark = nil,
		newest_mark = nil,
	}

	local files_set = {}
	for name, mark in pairs(marks) do
		-- Count unique files
		if not files_set[mark.file] then
			files_set[mark.file] = true
			stats.file_count = stats.file_count + 1
			table.insert(stats.files, mark.file)
		end

		-- Count mark types based on name prefix
		local mark_type = "other"
		if name:match("^fn:") then
			mark_type = "function"
		elseif name:match("^class:") then
			mark_type = "class"
		elseif name:match("^struct:") then
			mark_type = "struct"
		elseif name:match("^method:") then
			mark_type = "method"
		elseif name:match("^var:") then
			mark_type = "variable"
		end

		stats.types[mark_type] = (stats.types[mark_type] or 0) + 1

		-- Track oldest/newest marks
		if mark.created_at then
			if not stats.oldest_mark or mark.created_at < stats.oldest_mark.created_at then
				stats.oldest_mark = mark
			end
			if not stats.newest_mark or mark.created_at > stats.newest_mark.created_at then
				stats.newest_mark = mark
			end
		end
	end

	return stats
end

---Check if mark is stale (file no longer exists or line changed significantly)
---@param mark table Mark data
---@return boolean is_stale Whether the mark appears stale
---@return string|nil reason Reason why it's stale
function M.is_mark_stale(mark)
	-- Check if file exists
	if vim.fn.filereadable(mark.file) == 0 then
		return true, "File no longer exists"
	end

	-- Check if line number is valid
	local file_lines = vim.fn.readfile(mark.file)
	if mark.line > #file_lines then
		return true, "Line number exceeds file length"
	end

	-- Check if content has changed significantly (if we have original text)
	if mark.text then
		local current_text = file_lines[mark.line]
		if current_text then
			-- Simple similarity check - if less than 50% similar, consider stale
			local similarity = 0
			local words1 = vim.split(mark.text:lower(), "%s+")
			local words2 = vim.split(current_text:lower(), "%s+")
			
			local common_words = 0
			for _, word1 in ipairs(words1) do
				for _, word2 in ipairs(words2) do
					if word1 == word2 then
						common_words = common_words + 1
						break
					end
				end
			end
			
			if #words1 > 0 then
				similarity = common_words / #words1
			end
			
			if similarity < 0.5 then
				return true, "Line content has changed significantly"
			end
		end
	end

	return false
end

return M
