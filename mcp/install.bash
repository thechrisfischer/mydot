#!/bin/bash

DOTFILES_MCP_SERVERS=(
    composio
    grepler
    playwright
)

function install_mcp {
    local failed=0
    local server

    echo "Installing enabled MCP servers..."

    # shellcheck source=/dev/null
    source "$DOTFILES_REPO_DIR/mcp/_helpers.bash"
    _cleanup_stale_mcp_servers

    for server in "${DOTFILES_MCP_SERVERS[@]}"; do
        local script="$DOTFILES_REPO_DIR/mcp/$server.bash"
        local fn="install_$server"

        if [[ ! -f "$script" ]]; then
            _install_step_fail "$server" "installer script missing"
            failed=1
            continue
        fi

        # shellcheck source=/dev/null
        source "$script"

        if ! declare -F "$fn" >/dev/null; then
            _install_step_fail "$server" "installer function $fn missing"
            failed=1
            continue
        fi

        if ! "$fn"; then
            failed=1
        fi
    done

    _install_log "Restart Claude Desktop / Cursor and start a new Codex session for MCP changes to take effect."

    return "$failed"
}
