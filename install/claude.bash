#!/bin/bash

DOTFILES_CLAUDE_PLUGINS=(
    "chrome-devtools-mcp@claude-plugins-official"
)

function _merge_claude_settings {
    local existing="$1"
    local dotfiles="$2"
    local dest="$3"

    jq -s '
        .[0] as $existing |
        .[1] as $dotfiles |
        ($existing * $dotfiles) |
        .enabledPlugins = (($existing.enabledPlugins // {}) * ($dotfiles.enabledPlugins // {}))
    ' "$existing" "$dotfiles" > "$dest"
}

function _enable_claude_plugin {
    local plugin_ref="$1"

    if ! command -v claude &>/dev/null; then
        echo "⚠️  Claude plugin $plugin_ref: skipped (claude not found — run './install.sh packages' first)"
        return 0
    fi

    if claude plugin install "$plugin_ref" >/dev/null 2>&1; then
        _install_progress "Claude plugin $plugin_ref: installed"
        return 0
    fi

    if claude plugin enable "$plugin_ref" >/dev/null 2>&1; then
        _install_progress "Claude plugin $plugin_ref: enabled"
        return 0
    fi

    echo "⚠️  Claude plugin $plugin_ref: install/enable skipped (run: claude plugin install $plugin_ref)"
    return 0
}

function _print_claude_browser_reminders {
    cat <<'EOF'
ℹ️  Claude browser stack (see ide/chrome/README.md):
   • Playwright MCP — ./install.sh mcp (playwright) + Playwright MCP Bridge extension
   • Claude in Chrome — Claude in Chrome extension + claude --chrome (default via claude wrapper)
   • chrome-devtools — chrome-devtools-mcp plugin (enabled above)
   Chrome extensions sync via Google Chrome; logins are per-machine.
EOF
}

function install_claude {
    echo "Installing Claude Code configuration..."

    if ! command -v jq &> /dev/null; then
        echo "❌ jq not found — run './install.sh packages' first"
        return 1
    fi

    local claude_settings_dir="$HOME/.claude"

    # Create Claude settings directory if it doesn't exist
    mkdir -p "$claude_settings_dir"

    # Install settings.json (non-destructive merge with jq)
    local settings_file="$claude_settings_dir/settings.json"
    local source_settings="$DOTFILES_REPO_DIR/ide/claude/settings.json"

    if [[ ! -f "$source_settings" ]]; then
        echo "❌ Claude settings file not found at $source_settings"
        return 1
    fi

    if [[ -f "$settings_file" ]]; then
        local tmp_settings
        tmp_settings=$(mktemp)
        if _merge_claude_settings "$settings_file" "$source_settings" "$tmp_settings"; then
            mv "$tmp_settings" "$settings_file"
            echo "✅ Merged Claude Code settings"
        else
            rm -f "$tmp_settings"
            echo "❌ Failed to merge Claude Code settings"
            return 1
        fi
    else
        cp "$source_settings" "$settings_file"
        echo "✅ Installed Claude Code settings"
    fi

    # Install statusline script
    local statusline_src="$DOTFILES_REPO_DIR/ide/claude/statusline-command.sh"
    local statusline_dst="$claude_settings_dir/statusline-command.sh"
    if [[ -f "$statusline_src" ]]; then
        cp "$statusline_src" "$statusline_dst"
        chmod +x "$statusline_dst"
        echo "✅ Installed Claude Code statusline script"
    fi

    local plugin
    for plugin in "${DOTFILES_CLAUDE_PLUGINS[@]}"; do
        _enable_claude_plugin "$plugin"
    done

    # Stale MCP cleanup only — active servers are installed via ./install.sh mcp
    source "$DOTFILES_REPO_DIR/mcp/_helpers.bash"
    _cleanup_stale_mcp_servers

    _print_claude_browser_reminders

    echo "Claude Code configuration completed!"
    echo "⚠️  Restart Claude Code for changes to take effect"
}
