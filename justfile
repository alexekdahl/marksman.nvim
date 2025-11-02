# Install plenary.nvim if not present
install-deps:
    #!/usr/bin/env bash
    if [ ! -d "$HOME/.local/share/nvim/lazy/plenary.nvim" ]; then
        echo "Installing plenary.nvim..."
        mkdir -p "$HOME/.local/share/nvim/lazy/plenary.nvim"
        git clone --depth=1 https://github.com/nvim-lua/plenary.nvim.git "$HOME/.local/share/nvim/lazy/plenary.nvim"
    fi

# Run all tests
test: install-deps
    nvim --headless --noplugin -u tests/minimal_init.lua \
        -c "lua require('plenary.test_harness').test_directory('tests', {minimal_init = 'tests/minimal_init.lua'})"

# Run specific test file
test-file FILE: install-deps
    nvim --headless --noplugin -u tests/minimal_init.lua \
        -c "lua require('plenary.busted').run('{{FILE}}')"

# Watch tests (requires entr: brew install entr or apt install entr)
test-watch:
    find lua/ tests/ -name "*.lua" | entr -c just test

# Clean test artifacts
clean:
    rm -rf /tmp/*marksman_test*

# Lint code
lint:
    #!/usr/bin/env bash
    if command -v luacheck >/dev/null; then
        luacheck lua/
    else
        echo "luacheck not found. Install with: luarocks install luacheck"
    fi

# Format code
format:
    #!/usr/bin/env bash
    if command -v stylua >/dev/null; then
        stylua lua/ tests/
    else
        echo "stylua not found. Install with: cargo install stylua"
    fi
