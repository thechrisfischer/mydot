#!/bin/bash

# Pin deliberately; bump when upgrading Playwright MCP.
PLAYWRIGHT_MCP_VERSION="0.0.76"

function install_playwright {
    # shellcheck disable=SC1091
    source "$DOTFILES_REPO_DIR/mcp/_helpers.bash"

    _install_progress "playwright: configuring MCP server"

    if ! command -v node &>/dev/null; then
        _install_step_fail "playwright" "node not found — run './install.sh packages' first"
        return 1
    fi
    if ! command -v npx &>/dev/null; then
        _install_step_fail "playwright" "npx not found — run './install.sh packages' first"
        return 1
    fi

    local wrapper_path="$HOME/.local/bin/playwright-mcp"
    mkdir -p "$(dirname "$wrapper_path")"
    cat > "$wrapper_path" <<EOF
#!/bin/bash
set -euo pipefail

if [[ -f "\$HOME/.bash/credentials.bash" ]]; then
  # shellcheck disable=SC1091
  source "\$HOME/.bash/credentials.bash"
fi

# Optional: set PLAYWRIGHT_MCP_EXTENSION_TOKEN in ~/.bash/credentials.bash
# (copy from the Playwright MCP Bridge extension UI) to skip per-session tab approval.
exec npx -y @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} --extension
EOF
    chmod +x "$wrapper_path"
    echo "✅ Installed Playwright MCP wrapper at $wrapper_path"

    local wrapper_args_json
    wrapper_args_json=$(jq -n --arg wrapper "$wrapper_path" '[$wrapper]')

    _register_mcp_server "playwright" "/bin/bash" "$wrapper_args_json" "{}" \
        || { _install_step_fail "playwright" "claude code registration failed"; return 1; }
    _register_desktop_mcp_server "playwright" "/bin/bash" "$wrapper_args_json" "{}" \
        || { _install_step_fail "playwright" "claude desktop registration failed"; return 1; }
    _register_cursor_mcp_server "playwright" "/bin/bash" "$wrapper_args_json" "{}" \
        || { _install_step_fail "playwright" "cursor registration failed"; return 1; }
    _register_codex_mcp_server "playwright" "/bin/bash" "$wrapper_args_json" "{}" \
        || { _install_step_fail "playwright" "codex registration failed"; return 1; }

    _install_step_done_changed "playwright" "registered in code + desktop + cursor + codex"
    echo "ℹ️  Install Playwright MCP Bridge in Chrome (see ide/chrome/README.md)"
    echo "ℹ️  Optional: PLAYWRIGHT_MCP_EXTENSION_TOKEN in ~/.bash/credentials.bash to auto-approve tab connections"
}
