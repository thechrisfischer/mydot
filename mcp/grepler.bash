#!/bin/bash

function install_grepler {
    # shellcheck disable=SC1091
    source "$DOTFILES_REPO_DIR/mcp/_helpers.bash"

    _install_progress "grepler: configuring MCP server"

    # GREPLER_TOKEN is read from the environment (set it in ~/.bash/credentials.bash).

    if ! command -v node &>/dev/null; then
        _install_step_fail "grepler" "node not found — run './install.sh packages' first"
        return 1
    fi
    if ! command -v npx &>/dev/null; then
        _install_step_fail "grepler" "npx not found — run './install.sh packages' first"
        return 1
    fi

    local wrapper_path="$HOME/.local/bin/grepler-mcp"
    mkdir -p "$(dirname "$wrapper_path")"
    cat > "$wrapper_path" <<'EOF'
#!/bin/bash
set -euo pipefail

if [[ -f "$HOME/.bash/credentials.bash" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.bash/credentials.bash"
fi

if [[ -f "$HOME/.grepler/credentials.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.grepler/credentials.env"
fi

: "${GREPLER_URL:=https://grepler.dev/mcp/}"
: "${GREPLER_ORGANIZATION_ID:=}"

if [[ -z "${GREPLER_TOKEN:-}" ]]; then
  echo "GREPLER_TOKEN is not set. Add it to ~/.bash/credentials.bash or ~/.grepler/credentials.env." >&2
  exit 1
fi

headers=(--header "Authorization: Bearer ${GREPLER_TOKEN}")
if [[ -n "${GREPLER_ORGANIZATION_ID}" ]]; then
  headers+=(--header "X-Grepler-Organization-Id: ${GREPLER_ORGANIZATION_ID}")
fi

exec npx -y mcp-remote "$GREPLER_URL" "${headers[@]}"
EOF
    chmod +x "$wrapper_path"
    echo "✅ Installed Grepler MCP wrapper at $wrapper_path"

    local wrapper_args_json
    wrapper_args_json=$(jq -n --arg wrapper "$wrapper_path" '[$wrapper]')

    _register_mcp_server "grepler" "/bin/bash" "$wrapper_args_json" "{}" || { _install_step_fail "grepler" "claude code registration failed"; return 1; }
    _register_desktop_mcp_server "grepler" "/bin/bash" "$wrapper_args_json" "{}" || { _install_step_fail "grepler" "claude desktop registration failed"; return 1; }
    _register_cursor_mcp_server "grepler" "/bin/bash" "$wrapper_args_json" "{}" || { _install_step_fail "grepler" "cursor registration failed"; return 1; }
    _register_codex_mcp_server "grepler" "/bin/bash" "$wrapper_args_json" "{}" || { _install_step_fail "grepler" "codex registration failed"; return 1; }

    if [[ -f "$HOME/.bash/credentials.bash" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.bash/credentials.bash"
    fi
    if [[ -f "$HOME/.grepler/credentials.env" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.grepler/credentials.env"
    fi
    if [[ -z "${GREPLER_TOKEN:-}" ]]; then
        _install_step_fail "grepler" "GREPLER_TOKEN not set (registered but inaccessible)"
        return 1
    fi

    _install_step_done_changed "grepler" "registered in code + desktop + cursor + codex"
}
