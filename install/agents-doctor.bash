#!/bin/bash

function _agents_doctor_command_paths {
    local cmd="$1"
    (type -a "$cmd" 2>/dev/null || true) \
        | sed -n 's/.* is //p' \
        | awk '!seen[$0]++' \
        | paste -sd ',' -
}

function _agents_doctor_version {
    local cmd="$1"
    local path="$2"
    [[ -n "$path" && -x "$path" ]] || { printf '%s\n' "missing"; return 0; }
    "$path" --version 2>/dev/null | head -1 || printf '%s\n' "unknown"
}

function _agents_doctor_npm_status {
    local package="$1"
    local prefix="$2"
    command -v npm &>/dev/null || { printf '%s\n' "npm unavailable"; return 0; }
    NPM_CONFIG_PREFIX="$prefix" npm list -g "$package" --depth=0 2>/dev/null \
        | awk 'NR==2 {print $0; found=1} END {if (!found) print "not installed"}'
}

function _agents_doctor_json_mcp_ok {
    local config="$1"
    local name="$2"
    local url="$3"
    [[ -f "$config" ]] || return 1
    command -v jq &>/dev/null || return 1
    jq -e --arg name "$name" --arg url "$url" \
        '(.mcpServers[$name].url // empty) == $url' "$config" >/dev/null 2>&1
}

function _agents_doctor_codex_mcp_ok {
    local config="$1"
    local name="$2"
    local url="$3"
    [[ -f "$config" ]] || return 1
    awk -v section="[mcp_servers.$name]" -v url="$url" '
        $0 == section { in_section=1; next }
        in_section && /^\[/ { in_section=0 }
        in_section && $0 ~ /^url = / {
            gsub(/^url = "/, "", $0)
            gsub(/"$/, "", $0)
            if ($0 == url) found=1
        }
        END { exit found ? 0 : 1 }
    ' "$config"
}

function _agents_doctor_print_agent {
    local label="$1"
    local cmd="$2"
    local package="${3:-}"
    local path paths class version npm_status

    path=$(_agent_bin_path "$cmd")
    paths=$(_agents_doctor_command_paths "$cmd")
    class=$(_classify_agent_install "$cmd" "$package")
    version=$(_agents_doctor_version "$cmd" "$path")
    printf '%-14s path=%-45s class=%-18s version=%s\n' "$label" "${path:-missing}" "$class" "$version"
    [[ -n "$paths" ]] && printf '%-14s all_paths=%s\n' "" "$paths"
    if [[ -n "$package" ]]; then
        npm_status=$(_agents_doctor_npm_status "$package" "$(_dotfiles_user_prefix)")
        printf '%-14s npm_prefix=%s %s\n' "" "$(_dotfiles_user_prefix)" "$npm_status"
    fi
}

function _agents_doctor_print_mcp_status {
    local composio_url="${COMPOSIO_MCP_URL:-https://connect.composio.dev/mcp}"
    local claude_status=missing cursor_status=missing codex_status=missing

    _agents_doctor_json_mcp_ok "$HOME/.claude.json" composio "$composio_url" && claude_status=ok
    _agents_doctor_json_mcp_ok "$HOME/.cursor/mcp.json" composio "$composio_url" && cursor_status=ok
    _agents_doctor_codex_mcp_ok "$HOME/.codex/config.toml" composio "$composio_url" && codex_status=ok

    printf 'composio      claude=%s cursor=%s codex=%s url=%s\n' \
        "$claude_status" "$cursor_status" "$codex_status" "$composio_url"

    if [[ -f "$DOTFILES_REPO_DIR/.bash/functions/dot-composio-auth.bash" ]]; then
        printf 'composio_auth helper=dot-composio-auth status\n'
        # shellcheck source=/dev/null
        source "$DOTFILES_REPO_DIR/.bash/functions/dot-composio-auth.bash"
        dot-composio-auth status || true
    else
        printf 'composio_auth helper=missing\n'
    fi
}

function install_agents_doctor {
    echo "Agent CLI status"
    _agents_doctor_print_agent "claude" "claude" "@anthropic-ai/claude-code"
    _agents_doctor_print_agent "codex" "codex" "@openai/codex"
    _agents_doctor_print_agent "gemini-cli" "gemini" "@google/gemini-cli"
    _agents_doctor_print_agent "cursor" "cursor"
    _agents_doctor_print_agent "cursor-agent" "cursor-agent"
    _agents_doctor_print_agent "composio" "composio"

    echo ""
    echo "MCP registration status"
    _agents_doctor_print_mcp_status
}
