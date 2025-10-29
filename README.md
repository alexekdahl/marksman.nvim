<p align="center">
  <img src="assets/marksman.png" alt="marksman.nvim logo" width="420"/>
</p>

<h1 align="center">Marksman.nvim</h1>

<p align="center">
  A project-scoped bookmark manager for Neovim with beautiful UI.
</p>

# marksman.nvim

A simple and fast bookmark management plugin for Neovim.

## Features

- **Fast bookmarks**: Quickly set and jump to marks across your project
- **Project-aware**: Automatically organizes marks by project/directory
- **Simple workflow**: Set marks with one key, jump with another

## Requirements

- Neovim >= 0.8.0
- (Optional) [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for fuzzy finding
- (Optional) [snacks.nvim](https://github.com/folke/snacks.nvim) for modern picker interface

## Installation

### lazy.nvim

```lua
{
  "alexekdahl/marksman.nvim",
    opts = {},
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
## Basic Usage

## Telescope Integration

Add this function to your config to search marks with Telescope:

```lua
local function telescope_marksman()
  local ok, marksman = pcall(require, "marksman")
  if not ok then
    return
  end
  
  local ok, _ = pcall(require, "telescope")
  if not ok then
    marksman.show_marks()
    return
  end
  
  local marks = marksman.get_marks()
  if vim.tbl_isempty(marks) then
    vim.notify("No marks in current project", vim.log.levels.INFO)
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
      ordinal = name .. " " .. mark.file .. " " .. (mark.text or ""),
      filename = mark.file,
      lnum = mark.line,
      col = mark.col,
      text = mark.text,
    })
  end
  
  -- Sort by creation time (newest first)
  table.sort(entries, function(a, b)
    local mark_a = marks[a.value]
    local mark_b = marks[b.value]
    return (mark_a.created_at or 0) > (mark_b.created_at or 0)
  end)
  
  pickers.new({}, {
    prompt_title = "Project Marks",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return entry
      end,
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

-- Bind to a key
vim.keymap.set("n", "<leader>fm", telescope_marksman, { desc = "Find marks" })
```

## Snacks.nvim Integration

If you're using snacks.nvim, you can create a custom picker:
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



```lua
-- snacks integration
picker = {
    sources = {
        marksman = {
            name = "Marksman Marks",
            finder = cmd.snack_marksman,
            confirm = function(item)
                if item and item.mark_name then
                    require("marksman").goto_mark(item.mark_name)
                end
            end,
        },
    },
}


## API
```lua
local marksman = require("marksman")
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

## FAQ

**Q: How are marks stored?**
A: Marks are stored per-project in ~/.local/share/nvim/marksman_[hash].json where the hash is generated from the project path.

**Q: Can I share marks between team members?**
A: Currently marks are local to your machine. Project-wide mark sharing is planned for a future release.

**Q: What happens to marks when files are deleted?**
A: Marksman automatically warns when marks pointing to non-existent files when you load the marks.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details.
