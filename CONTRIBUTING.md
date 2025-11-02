# Contributing to Marksman.nvim

Thank you for your interest in contributing to Marksman.nvim! This document provides guidelines for contributing to this project.

## Getting Started

1. **Fork the repository** and clone your fork locally
2. **Create a new branch** for your feature or bug fix
3. **Test your changes** thoroughly
4. **Submit a pull request** with a clear description

## Development Setup

### Prerequisites
- Neovim >= 0.8.0
- Git
- Lua 5.1+ (for testing outside Neovim)

### Code Quality Tools
```bash
# Install luacheck for linting
luarocks install luacheck

# Install stylua for formatting
cargo install stylua

# Run linting
luacheck lua/

# Run formatting
stylua lua/
```

## Code Style

### Lua Style Guidelines
- Use **snake_case** for functions and variables
- Use **PascalCase** for classes/modules
- **Indent with tabs** (width: 4)
- **Line length**: 100 characters max
- **Use meaningful variable names**

### Documentation
- Add **JSDoc-style comments** for public functions
- Include **@param** and **@return** annotations
- Document **complex logic** with inline comments

Example:
```lua
---Add a mark at the current cursor position
---@param name string|nil Optional mark name (auto-generated if nil)
---@param description string|nil Optional mark description
---@return table result Result with success, message, and mark_name
function M.add_mark(name, description)
    -- Implementation here
end
```

## Project Structure

```
lua/marksman/
├── init.lua      -- Main plugin entry point
├── storage.lua   -- Mark persistence and project management
├── ui.lua        -- Floating window and interface
└── utils.lua     -- Utilities and validation
```

## Contribution Types

### Bug Fixes
1. **Create an issue** describing the bug
2. **Include reproduction steps** and expected behavior
3. **Write a test case** if applicable
4. **Fix the bug** and ensure tests pass

### New Features
1. **Discuss the feature** in an issue first
2. **Ensure it aligns** with the plugin's focused scope
3. **Write comprehensive documentation**
4. **Add configuration options** if needed

### Documentation
- **Fix typos** and improve clarity
- **Add examples** for complex features
- **Update README** with new functionality

## Testing Guidelines

### Manual Testing
- Test with **multiple projects**
- Verify **mark persistence** across sessions
- Test **edge cases** (empty files, special characters)
- Check **memory usage** with large mark sets

### Test Scenarios
1. **Basic Operations**:
   - Add/delete/rename marks
   - Jump to marks
   - Search functionality

2. **Project Switching**:
   - Marks isolated per project
   - Correct project detection

3. **Error Handling**:
   - Invalid file paths
   - Corrupted storage files
   - Memory limits

4. **UI Testing**:
   - Window sizing and positioning
   - Keyboard navigation
   - Search and filtering

## Performance Considerations

### Memory Efficiency
- **Lazy load modules** when possible
- **Clean up resources** on plugin disable
- **Cache strategically** with expiration
- **Debounce operations** to reduce I/O

### Code Patterns
```lua
-- Good: Lazy loading
local function get_storage()
    if not storage then
        storage = require("marksman.storage")
    end
    return storage
end

-- Good: Error handling
local ok, result = pcall(function()
    -- Potentially failing operation
end)
if not ok then
    notify("Operation failed: " .. tostring(result), vim.log.levels.ERROR)
    return false
end
```

## Error Handling

### Guidelines
- **Always handle errors** gracefully
- **Provide meaningful messages** to users
- **Log technical details** for debugging
- **Fallback to safe defaults** when possible

### Error Message Format
```lua
-- User-facing: Clear and actionable
notify("Cannot add mark: file is not readable", vim.log.levels.WARN)

-- Debug: Technical details
notify("Failed to save marks: " .. tostring(err), vim.log.levels.ERROR)
```

## Configuration Design

### Principles
- **Sensible defaults** that work out of the box
- **Granular options** for customization
- **Backward compatibility** when possible
- **Validation** for user inputs

### Example Configuration
```lua
require("marksman").setup({
    -- Core functionality
    max_marks = 100,
    auto_save = true,
    
    -- UI preferences
    minimal = false,
    silent = false,
    
    -- Performance tuning
    debounce_ms = 500,
    
    -- Customization
    keymaps = { ... },
    highlights = { ... },
})
```

## Pull Request Process

### Before Submitting
1. **Test thoroughly** on your system
2. **Run linting** and fix issues
3. **Update documentation** if needed
4. **Rebase on main** branch

### PR Description Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Refactoring

## Testing
Describe how you tested the changes

## Breaking Changes
List any breaking changes (if applicable)

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests pass
```

## Review Process

### What We Look For
- **Code quality** and maintainability
- **Performance impact**
- **User experience** improvements
- **Documentation completeness**
- **Test coverage**

### Response Time
- Initial review: 2-3 business days
- Follow-up reviews: 1-2 business days
- Simple fixes: Same day

## Getting Help

### Communication Channels
- **GitHub Issues**: Bug reports and feature requests
- **GitHub Discussions**: Questions and general discussion
- **Pull Request Comments**: Code-specific discussions

### Response Guidelines
- Be **respectful** and constructive
- **Ask questions** if requirements are unclear
- **Provide context** for your suggestions

## Recognition

Contributors are recognized in:
- **README.md** contributors section
- **Release notes** for significant contributions
- **GitHub repository** contributor graphs

Thank you for helping make Marksman.nvim better! 🚀
