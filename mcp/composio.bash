#!/bin/bash

function install_composio {
    # shellcheck disable=SC1091
    source "$DOTFILES_REPO_DIR/mcp/_helpers.bash"

    _install_progress "composio: configuring MCP server"

    local composio_url="${COMPOSIO_MCP_URL:-https://connect.composio.dev/mcp}"
    local wrapper_path="$HOME/.local/bin/composio-mcp"
    mkdir -p "$(dirname "$wrapper_path")"
    cat > "$wrapper_path" <<'EOF'
#!/bin/bash
set -euo pipefail

: "${COMPOSIO_MCP_URL:=https://connect.composio.dev/mcp}"

exec npx -y mcp-remote "$COMPOSIO_MCP_URL"
EOF
    chmod +x "$wrapper_path"

    _register_url_mcp_server "composio" "$composio_url" || { _install_step_fail "composio" "claude code registration failed"; return 1; }
    _register_cursor_oauth_mcp_server "composio" "$composio_url" || { _install_step_fail "composio" "cursor registration failed"; return 1; }
    _register_codex_url_mcp_server_toml_fallback "composio" "$composio_url" || { _install_step_fail "composio" "codex registration failed"; return 1; }

    if command -v npx &>/dev/null; then
        _register_desktop_url_mcp_server "composio" "$composio_url" || \
            echo "⚠️  Claude Desktop Composio registration skipped (legacy mcp-remote registration failed)."
    else
        echo "⚠️  Claude Desktop Composio registration skipped: npx not found. Install Node.js before using the legacy Claude Desktop wrapper."
    fi

    _install_step_done_changed "composio" "registered as remote HTTP OAuth in code + cursor + codex"
    echo "ℹ️  Next on this machine: approve/login Composio from each MCP client that prompts for OAuth"
    echo "   Codex CLI: codex mcp login composio"
    echo "   Claude Code: /mcp → composio → Reconnect"
    echo "   Cursor: restart Cursor, then approve/connect composio in MCP settings"
    echo "   Composio apps: connect desired apps in the Composio dashboard"
    echo "   Docs: $DOTFILES_REPO_DIR/mcp/composio-auth.md"
}
