<p align="center">
  <img src="assets/marksman.png" alt="marksman.nvim logo" width="420"/>
</p>

<h1 align="center">Marksman.nvim</h1>

<p align="center">
  Quick bookmarks for Neovim that actually stick around.
</p>

## Why?

Vim's built-in marks are great, but they're global and get messy fast. Marksman keeps your bookmarks organized by project and gives you a clean interface to manage them.

## What you get

- **Project-scoped marks** - Each project gets its own set of bookmarks
- **Persistent storage** - Your marks survive Neovim restarts  
- **Smart naming** - Auto-generates useful names based on context
- **Quick access** - Jump to your most recent marks with single keys
- **Clean interface** - Browse and manage marks in a floating window

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

## Setup

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
})
```

Want different keys? No problem:

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

## How to use it

1. **Add a mark**: Press `<C-a>` (or your custom key) 
2. **See your marks**: Press `<C-e>` to open the marks window
3. **Jump around**: Use `<M-y>`, `<M-u>`, etc. to jump to recent marks
4. **In the marks window**: Press Enter or 1-9 to jump, `d` to delete, `r` to rename

## Commands

```
:MarkAdd [name]     - Add a mark (auto-names if no name given)
:MarkGoto [name]    - Jump to mark or show marks list
:MarkDelete [name]  - Delete a mark  
:MarkRename old new - Rename a mark
:MarkList           - Show all marks
:MarkClear          - Clear all marks in project
:MarkExport         - Export marks to JSON
:MarkImport         - Import marks from JSON
```

## Telescope integration

If you use Telescope, drop this in your config:

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
    table.insert(entries, {
      value = name,
      display = name .. " - " .. vim.fn.fnamemodify(mark.file, ":~:.") .. ":" .. mark.line,
      ordinal = name .. " " .. mark.file,
      filename = mark.file,
      lnum = mark.line,
      col = mark.col,
    })
  end
  
  table.sort(entries, function(a, b)
    local mark_a = marks[a.value]
    local mark_b = marks[b.value]
    return (mark_a.created_at or 0) > (mark_b.created_at or 0)
  end)
  
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

## Snacks.nvim integration

For snacks.nvim users, add this function to your utils:

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
      display = string.format("%s %s:%d", name, vim.fn.fnamemodify(mark.file, ":~:."), tonumber(mark.line) or 1),
      ordinal = name .. " " .. vim.fn.fnamemodify(mark.file, ":t"),
      mark_name = name,
    }
    table.insert(results, entry)
  end
  
  -- Sort by creation time (newest first)
  table.sort(results, function(a, b)
    local mark_a = marks[a.mark_name]
    local mark_b = marks[b.mark_name]
    return (mark_a.created_at or 0) > (mark_b.created_at or 0)
  end)
  
  return results
end
```

Then configure the picker source:

```lua
{
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        marksman = {
          name = "Marksman Marks",
          finder = your_util.snacks_marksman, -- replace with your function
          confirm = function(item)
            if item and item.mark_name then
              require("marksman").goto_mark(item.mark_name)
            end
          end,
        },
      },
    },
  },
  keys = {
    {
      "<leader>b",
      function()
        Snacks.picker.pick("marksman")
      end,
      desc = "Find Marks",
    },
  },
}
```

## API

```lua
local marksman = require("marksman")

marksman.add_mark("my_mark")       -- Add a mark
marksman.goto_mark("my_mark")      -- Jump to mark by name
marksman.goto_mark(1)              -- Jump to first mark  
marksman.delete_mark("my_mark")    -- Delete a mark
marksman.show_marks()              -- Open marks window
marksman.get_marks_count()         -- Get number of marks
```

## How it works

Marks get saved to `~/.local/share/nvim/marksman_[hash].json` where the hash comes from your project path. Each project gets its own file, so your marks stay organized.

When you add a mark without a name, Marksman tries to be smart about it - it'll use function names, class names, or just fall back to filename:line.

## License

MIT
