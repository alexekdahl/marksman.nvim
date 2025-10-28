<p align="center">
  <img src="assets/marksman.png" alt="marksman.nvim logo" width="420"/>
</p>

<h1 align="center">Marksman.nvim</h1>

<p align="center">
  A project-scoped bookmark manager for Neovim with beautiful UI.
</p>

## Installation

### Using lazy.nvim

```lua
{
	"alexekdahl/marksman.nvim",
	event = "VeryLazy",
	keys = {
		{ "<C-a>", function() require("marksman").add_mark() end, desc = "Add mark" },
		{ "<C-e>", function() require("marksman").show_marks() end, desc = "Show marks" },
		{ "<M-y>", function() require("marksman").goto_mark(1) end, desc = "Go to mark 1" },
		{ "<M-u>", function() require("marksman").goto_mark(2) end, desc = "Go to mark 2" },
		{ "<M-i>", function() require("marksman").goto_mark(3) end, desc = "Go to mark 3" },
		{ "<M-o>", function() require("marksman").goto_mark(4) end, desc = "Go to mark 4" },
	},
	cmd = {
		"MarkAdd", "MarkGoto", "MarkDelete", "MarkRename",
		"MarkList", "MarkClear",
		"MarkExport", "MarkImport",
	},
	opts = {
		-- Configuration goes here
	},
}
```

## Configuration

Default configuration:

```lua
{
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
```

### Custom Configuration Example

```lua
{
	"alexekdahl/marksman.nvim",
	opts = {
		keymaps = {
			add = "<leader>ma",
			show = "<leader>ms",
			goto_1 = "<leader>m1",
			goto_2 = "<leader>m2",
			goto_3 = "<leader>m3",
			goto_4 = "<leader>m4",
		},
		max_marks = 50,
		auto_save = true,
	},
}
```

### Disable Keymaps

```lua
{
	"alexekdahl/marksman.nvim",
	opts = {
		keymaps = false, -- Disable all default keymaps
	},
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:MarkAdd [name]` | Add a mark at current cursor position |
| `:MarkGoto [name]` | Go to a mark (shows list if no name provided) |
| `:MarkDelete [name]` | Delete a mark (clears all if no name provided) |
| `:MarkRename <old> <new>` | Rename a mark |
| `:MarkList` | Show all marks in floating window |
| `:MarkClear` | Clear all marks (with confirmation) |
| `:MarkExport` | Export marks to JSON file |
| `:MarkImport` | Import marks from JSON file |

## Features

- **Project-scoped**: Marks are stored per-project (based on git root)
- **Smart naming**: Auto-generates meaningful names from context
- **Beautiful UI**: Floating window with syntax highlighting
- **File icons**: Automatic file type icons
- **Quick navigation**: Number keys (1-9) for instant jumping
- **Import/Export**: Share marks across machines
- **Persistent**: Marks survive Neovim restarts

## Usage

### Adding Marks

```vim
" Add mark with auto-generated name
:MarkAdd

" Add mark with custom name
:MarkAdd important_function
```

Or use the keymap: `<C-a>` (default)

### Viewing Marks

```vim
:MarkList
```

Or use the keymap: `<C-e>` (default)

In the marks window:
- `<CR>` or `1-9`: Jump to mark
- `d`: Delete mark
- `r`: Rename mark
- `q` or `<Esc>`: Close window

### Quick Access

Use the quick goto keymaps to jump to your most recent marks:
- `<M-y>`: Jump to mark #1
- `<M-u>`: Jump to mark #2
- `<M-i>`: Jump to mark #3
- `<M-o>`: Jump to mark #4

## API

```lua
local marksman = require("marksman.nvim")

-- Add a mark
marksman.add_mark("my_mark")

-- Go to a mark
marksman.goto_mark("my_mark")
marksman.goto_mark(1)  -- Jump to first mark

-- Delete a mark
marksman.delete_mark("my_mark")

-- Rename a mark
marksman.rename_mark("old_name", "new_name")

-- Show marks UI
marksman.show_marks()

-- Get marks count
local count = marksman.get_marks_count()

-- Clear all marks
marksman.clear_all_marks()

-- Export/Import
marksman.export_marks()
marksman.import_marks()
```

## License
MIT
