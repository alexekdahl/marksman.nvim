<p align="center">
  <img src="assets/marksman.png" alt="marksman.nvim logo" width="420"/>
</p>

<h1 align="center">Marksman.nvim</h1>

<p align="center">
  Advanced bookmarks for Neovim that actually stick around.
</p>

## Why?

Vim's built-in marks are great, but they're global and get messy fast. Marksman keeps your bookmarks organized by project, adds powerful search capabilities, and provides a clean interface to manage them with modern features like smart naming and file path display.

## Features

- **Project-scoped marks** - Each project gets its own isolated set of bookmarks
- **Persistent storage** - Your marks survive Neovim restarts with automatic backup
- **Smart naming** - Context-aware auto-generation of mark names based on code structure
- **Quick access** - Jump to your marks with single keys
- **Enhanced search** - Find marks by name, file path, or content
- **Interactive UI** - Browse and manage marks in an enhanced floating window
- **Reordering** - Move marks up and down to organize them as needed
- **Multiple integrations** - Works with Telescope, Snacks.nvim, and more

## Requirements

- Neovim >= 0.8.0

## Installation

### lazy.nvim

```lua
{
  "alexekdahl/marksman.nvim",
  opts = {},
}
```

### With full configuration

```lua
{
  "alexekdahl/marksman.nvim",
  opts = {
    keymaps = {
      add = "<C-a>",
      show = "<C-e>", 
      goto_1 = "<M-y>",
      goto_2 = "<M-u>",
      goto_3 = "<M-i>",
      goto_4 = "<M-o>",
    },
    auto_save = true,
    max_marks = 100,
    search_in_ui = true,
    silent = false,
    minimal = false,
    disable_default_keymaps = false,
  },
}
```

## Setup

### Basic Setup

```lua
require("marksman").setup({
  keymaps = {
    add = "<C-a>",
    show = "<C-e>", 
    goto_1 = "<M-y>",
    goto_2 = "<M-u>",
    goto_3 = "<M-i>",
    goto_4 = "<M-o>",
  },
  auto_save = true,
  max_marks = 100,
  disable_default_keymaps = false,
})
```

### Custom Keymaps

```lua
require("marksman").setup({
  keymaps = {
    add = "<leader>ma",
    show = "<leader>ms",
    goto_1 = "<leader>m1",
    goto_2 = "<leader>m2", 
    goto_3 = "<leader>m3",
    goto_4 = "<leader>m4",
  },
})
```

### Disable Default Keymaps

```lua
require("marksman").setup({
  disable_default_keymaps = true,
})

-- Set your own keymaps manually
vim.keymap.set("n", "<leader>ma", require("marksman").add_mark)
vim.keymap.set("n", "<leader>ms", require("marksman").show_marks)
```

### Custom Highlights

```lua
require("marksman").setup({
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
})
```

## How to use it

### Basic Usage

1. **Add a mark**: Press `<C-a>` (or your custom key) 
2. **See your marks**: Press `<C-e>` to open the marks window
3. **Jump around**: Use `<M-y>`, `<M-u>`, etc. to jump to marks
4. **In the marks window**: 
   - Press Enter or 1-9 to jump
   - `d` to delete
   - `r` to rename  
   - `/` to search
   - `J`/`K` to move marks up/down

### Advanced Features

#### Search Functionality
Search through all mark data:
```lua
require("marksman").search_marks("api controller")
```

## Commands

```
:MarkAdd [name]              - Add a mark with optional name
:MarkGoto [name]             - Jump to mark or show marks list
:MarkDelete [name]           - Delete a mark  
:MarkRename old new          - Rename a mark
:MarkList                    - Show all marks in enhanced UI
:MarkClear                   - Clear all marks in project
:MarkSearch [query]          - Search marks
:MarkExport                  - Export marks to JSON
:MarkImport                  - Import marks from JSON
```

## Enhanced UI Features

The floating window includes:

- **Real-time search** - Press `/` to filter marks instantly
- **Enhanced navigation** - Better keyboard shortcuts and visual feedback
- **File path display** - View relative file paths for better context
- **Mark reordering** - Press `J`/`K` to move marks up/down

## Telescope Integration

Enhanced Telescope integration with search support:

```lua
local function telescope_marksman()
  local marksman = require("marksman")
  local marks = marksman.get_marks()
  
  if vim.tbl_isempty(marks) then
    vim.notify("No marks in current project")
    return
  end
  
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  
  local entries = {}
  for name, mark in pairs(marks) do
    local display_text = name
    
    table.insert(entries, {
      value = name,
      display = display_text .. " (" .. vim.fn.fnamemodify(mark.file, ":~:.") .. ":" .. mark.line .. ")",
      ordinal = name .. " " .. mark.file,
      filename = mark.file,
      lnum = mark.line,
      col = mark.col,
    })
  end
  
  pickers.new({}, {
    prompt_title = "Project Marks",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry) return entry end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          marksman.goto_mark(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

vim.keymap.set("n", "<leader>fm", telescope_marksman, { desc = "Find marks" })
```

## Snacks.nvim Integration

Enhanced integration for snacks.nvim users:

```lua
function M.snacks_marksman()
  local ok, marksman = pcall(require, "marksman")
  if not ok then
    return {}
  end
  
  local marks = marksman.get_marks()
  if vim.tbl_isempty(marks) then
    return {}
  end
  
  local results = {}
  for name, mark in pairs(marks) do
    local entry = {
      text = name,
      file = mark.file,
      pos = { tonumber(mark.line) or 1, tonumber(mark.col) or 1 },
      display = string.format("%s %s:%d", 
        name, 
        vim.fn.fnamemodify(mark.file, ":~:."), 
        tonumber(mark.line) or 1
      ),
      ordinal = name .. " " .. vim.fn.fnamemodify(mark.file, ":t"),
      mark_name = name,
    }
    
    table.insert(results, entry)
  end
  
  return results
end
```

## API Reference

### Core Functions

```lua
local marksman = require("marksman")

-- Basic operations
marksman.add_mark("my_mark")
marksman.goto_mark("my_mark")
marksman.goto_mark(1)  -- Jump to first mark by index
marksman.delete_mark("my_mark")
marksman.rename_mark("old_name", "new_name")

-- Enhanced features
marksman.search_marks("search query")
marksman.show_marks()

-- Utility functions
marksman.get_marks()
marksman.get_marks_count()
marksman.export_marks()
marksman.import_marks()
```

### Storage Operations

```lua
local storage = require("marksman.storage")

storage.get_project_name()    -- Get current project name
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `keymaps` | table | `{...}` | Key mappings for mark operations |
| `auto_save` | boolean | `true` | Automatically save marks |
| `max_marks` | number | `100` | Maximum marks per project |
| `search_in_ui` | boolean | `true` | Enable search in UI |
| `minimal` | boolean | `false` | Set to true for clean UI (number, name, and filepath only)|
| `silent` | boolean | `false` | Set to true to supress notifications|
| `disable_default_keymaps` | boolean | `false` | Set to true to disable all default keymaps |
| `highlights` | table | `{...}` | Custom highlight groups |

## How it works

### Storage
Marks are stored in `~/.local/share/nvim/marksman_[hash].json` where the hash is derived from your project path. Each project gets its own file with automatic backup support.

### Smart Naming
When you add a mark without a name, Marksman analyzes the code context to generate meaningful names:

- **Functions**: `fn:calculate_total`
- **Classes**: `class:UserModel` 
- **Structs**: `struct:Config`
- **Fallback**: `filename:line`

### Project Detection
Marksman uses multiple methods to find your project root:

1. Git repository root
2. Common project files (.git, package.json, Cargo.toml, etc.)
3. Current working directory as fallback

### Search Algorithm
The search function looks through:
- Mark names
- File names and paths
- Code context (the line content)

### File Path Display
The UI shows relative file paths instead of just filenames, making it easier to distinguish between files with the same name in different directories.

## Performance

- **Lazy loading**: Modules are only loaded when needed
- **Efficient storage**: JSON format with minimal file I/O
- **Smart caching**: Marks are cached in memory after first load
- **Fast search**: Optimized filtering algorithms

## License

MIT
