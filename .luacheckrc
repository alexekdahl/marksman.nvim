std = "luajit"

globals = {
	"vim",
}

read_globals = {
	"vim",
}

exclude_files = {
	".luarocks",
	"lua_modules",
	"tests/minimal_init.lua",
}

ignore = {
	"212", -- Unused argument
	"213", -- Unused loop variable
	"431", -- Shadowing upvalue
	"432", -- Shadowing upvalue argument
}

max_line_length = 100
max_cyclomatic_complexity = 15

files = {
	"lua/marksman/",
	"tests/",
}

files["tests/"] = {
	ignore = {
		"211", -- Unused local variable
		"212", -- Unused argument
		"213", -- Unused loop variable
	},
}
