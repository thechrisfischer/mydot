#!/bin/bash

# MCP registration helpers — register servers in Claude Code, Claude Desktop, Cursor, and Codex.
# Sourced by individual MCP install scripts (e.g. mcp/grepler.bash).

# Fallback shims for install/_helpers.bash. The normal install flow sources
# install/_helpers.bash early via install.sh, but direct-source paths (notably
# tests/mcp/run_tests.sh which sources only mcp/<server>.bash) need stand-ins
# so the per-server installers don't crash with "command not found".
if ! command -v _install_progress >/dev/null 2>&1; then
    _install_progress() { printf '  - %s\n' "$*"; }
fi
if ! command -v _install_step_start >/dev/null 2>&1; then
    _install_step_start() { :; }
fi
if ! command -v _install_step_done >/dev/null 2>&1; then
    _install_step_done() { local n="$1" r="${2:-done}"; printf '  ✓ %s: %s\n' "$n" "$r"; }
fi
if ! command -v _install_step_done_changed >/dev/null 2>&1; then
    _install_step_done_changed() { local n="$1" r="${2:-installed}"; printf '  ✓ %s: %s\n' "$n" "$r"; }
fi
if ! command -v _install_step_fail >/dev/null 2>&1; then
    _install_step_fail() { local n="$1" r="${2:-failed}"; printf '  ✗ %s: %s\n' "$n" "$r" >&2; }
fi

function _dotfiles_jq_install_hint {
    echo "⚠️  jq not found. Install with: brew install jq — or sudo port install jq on legacy macOS (MacPorts)."
}

# Remove stale MCP servers that are no longer managed by dotfiles.
# Add server names here when they are retired or consolidated into other servers.
function _cleanup_stale_mcp_servers {
    local stale_servers=("airtable" "dovetail" "snowflake" "limitless" "metabase" "deco" "alexa" "reclaim" "lifelog" "glowscape")

    command -v jq &>/dev/null || return 0

    # Clean from JSON MCP configs.
    local configs=("$HOME/.claude.json")
    configs+=("$HOME/.cursor/mcp.json")
    [[ "$(uname -s)" == "Darwin" ]] && configs+=("$HOME/Library/Application Support/Claude/claude_desktop_config.json")

    for config in "${configs[@]}"; do
        [[ -f "$config" ]] || continue
        for name in "${stale_servers[@]}"; do
            if jq -e --arg name "$name" '.mcpServers[$name]' "$config" &>/dev/null; then
                local tmp_config
                tmp_config=$(mktemp)
                if jq --arg name "$name" 'del(.mcpServers[$name])' "$config" > "$tmp_config"; then
                    mv "$tmp_config" "$config"
                    echo "🧹 Removed stale MCP server '$name' from $config"
                else
                    rm -f "$tmp_config"
                fi
            fi
        done
    done

    # Clean from Codex TOML config.
    local codex_config="$HOME/.codex/config.toml"
    if [[ -f "$codex_config" ]]; then
        for name in "${stale_servers[@]}"; do
            if grep -q "^[[:space:]]*\\[mcp_servers\\.$name\\]" "$codex_config"; then
                _remove_codex_mcp_server_toml "$name" "$codex_config"
                echo "🧹 Removed stale MCP server '$name' from $codex_config"
            fi
        done
    fi

    _cleanup_extension_managed_from_desktop

    # Clean stale files from ~/.mcp/ and ~/.local/bin/
    local stale_files=(
        "$HOME/.mcp/dovetail"
        "$HOME/.mcp/dovetail-wrapper.sh"
        "$HOME/.mcp/snowflake-wrapper.sh"
    )
    for f in "${stale_files[@]}"; do
        if [[ -e "$f" ]]; then
            rm -rf "$f"
            echo "🧹 Removed stale file $f"
        fi
    done
}

function _cleanup_extension_managed_from_desktop {
    local desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    [[ -f "$desktop_config" ]] || return 0
    command -v jq &>/dev/null || return 0

    local stale_names
    stale_names=$(jq -r '
        (.mcpServers // {}) | to_entries[]
        | select((.value._source // "") | startswith("claude-extension:"))
        | .key
    ' "$desktop_config")
    [[ -n "$stale_names" ]] || return 0

    local name tmp_config
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        tmp_config=$(mktemp)
        if jq --arg name "$name" 'del(.mcpServers[$name])' "$desktop_config" > "$tmp_config"; then
            mv "$tmp_config" "$desktop_config"
            echo "🧹 Removed extension-managed MCP server '$name' from $desktop_config"
        else
            rm -f "$tmp_config"
        fi
    done <<< "$stale_names"
}

function _remove_codex_mcp_server_toml {
    local name="$1"
    local codex_config="$2"
    local tmp_config

    tmp_config=$(mktemp)
    awk -v section="[mcp_servers.$name]" -v env_section="[mcp_servers.$name.env]" '
        $0 == section || $0 == env_section { skip=1; next }
        skip && /^\[/ { skip=0 }
        !skip { print }
    ' "$codex_config" > "$tmp_config"
    mv "$tmp_config" "$codex_config"
}

# Register a URL-based (streamable HTTP) MCP server in ~/.claude.json
# Usage: _register_url_mcp_server <name> <url>
function _register_url_mcp_server {
    local name="$1"
    local url="$2"
    local claude_config="$HOME/.claude.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    if [[ ! -f "$claude_config" ]]; then
        echo '{"mcpServers":{}}' > "$claude_config"
    fi

    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --arg url "$url" \
        '.mcpServers[$name] = {type: "http", url: $url}' "$claude_config" > "$tmp_config"; then
        mv "$tmp_config" "$claude_config"
        echo "✅ Registered MCP server '$name' in $claude_config"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name'"
        return 1
    fi
}

# Register a URL-based (streamable HTTP) MCP server with auth headers in ~/.claude.json
# Usage: _register_url_mcp_server_with_headers <name> <url> '<headers_json_object>'
function _register_url_mcp_server_with_headers {
    local name="$1"
    local url="$2"
    local headers_json="$3"
    local claude_config="$HOME/.claude.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    if [[ ! -f "$claude_config" ]]; then
        echo '{"mcpServers":{}}' > "$claude_config"
    fi

    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --arg url "$url" --argjson headers "$headers_json" \
        '.mcpServers[$name] = {type: "http", url: $url, headers: $headers}' "$claude_config" > "$tmp_config"; then
        mv "$tmp_config" "$claude_config"
        echo "✅ Registered MCP server '$name' (with headers) in $claude_config"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name'"
        return 1
    fi
}

# Register a URL-based (remote) MCP server with auth headers in Claude Desktop config.
# Uses npx mcp-remote with --header args for bearer token auth.
# macOS only.
# Usage: _register_desktop_url_mcp_server_with_headers <name> <url> <header_name> <header_value>
function _register_desktop_url_mcp_server_with_headers {
    local os_type
    os_type=$(uname -s)
    if [[ "$os_type" != "Darwin" ]]; then
        echo "ℹ️  Skipping Claude Desktop config (macOS only)"
        return 0
    fi

    local name="$1"
    local url="$2"
    local header_name="$3"
    local header_value="$4"
    local desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi
    local npx_cmd
    npx_cmd=$(command -v npx)
    if [[ -z "$npx_cmd" ]]; then
        echo "⚠️  npx not found. Install Node.js (port install nodejs22, or brew install node) for remote URL MCP in Claude Desktop."
        return 1
    fi

    mkdir -p "$(dirname "$desktop_config")"
    if [[ ! -f "$desktop_config" ]]; then
        echo '{"mcpServers":{}}' > "$desktop_config"
    fi

    local header_arg="${header_name}:${header_value}"
    # Build args: add --allow-http for non-HTTPS URLs
    local server_entry
    if [[ "$url" == http://* && "$url" != http://localhost* && "$url" != http://127.0.0.1* ]]; then
        server_entry=$(jq -n \
            --arg cmd "$npx_cmd" \
            --arg url "$url" \
            --arg header "$header_arg" \
            '{command: $cmd, args: ["-y", "mcp-remote", $url, "--header", $header, "--allow-http"]}')
    else
        server_entry=$(jq -n \
            --arg cmd "$npx_cmd" \
            --arg url "$url" \
            --arg header "$header_arg" \
            '{command: $cmd, args: ["-y", "mcp-remote", $url, "--header", $header]}')
    fi
    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --argjson entry "$server_entry" \
        '.mcpServers[$name] = $entry' "$desktop_config" > "$tmp_config"; then
        mv "$tmp_config" "$desktop_config"
        echo "✅ Registered MCP server '$name' in Claude Desktop config (via mcp-remote with auth)"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name' in Claude Desktop config"
        return 1
    fi
}

# Register a URL-based (remote) MCP server in Claude Desktop config.
# Claude Desktop only supports stdio (command + args), not raw "url". We use
# npx mcp-remote <url> as a local proxy that speaks stdio to Claude and
# HTTP/SSE to the remote server. Requires Node.js (for npx).
# macOS only.
# Usage: _register_desktop_url_mcp_server <name> <url>
function _register_desktop_url_mcp_server {
    local os_type
    os_type=$(uname -s)
    if [[ "$os_type" != "Darwin" ]]; then
        echo "ℹ️  Skipping Claude Desktop config (macOS only)"
        return 0
    fi

    local name="$1"
    local url="$2"
    local desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    local args_json="[\"-y\", \"mcp-remote\", \"$url\"]"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi
    local npx_cmd
    npx_cmd=$(command -v npx)
    if [[ -z "$npx_cmd" ]]; then
        echo "⚠️  npx not found. Install Node.js (port install nodejs22, or brew install node) for remote URL MCP in Claude Desktop."
        return 1
    fi

    mkdir -p "$(dirname "$desktop_config")"
    if [[ ! -f "$desktop_config" ]]; then
        echo '{"mcpServers":{}}' > "$desktop_config"
    fi

    local server_entry
    server_entry=$(jq -n \
        --arg cmd "$npx_cmd" \
        --argjson args "$args_json" \
        '{command: $cmd, args: $args}')
    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --argjson entry "$server_entry" \
        '.mcpServers[$name] = $entry' "$desktop_config" > "$tmp_config"; then
        mv "$tmp_config" "$desktop_config"
        echo "✅ Registered MCP server '$name' in Claude Desktop config (via mcp-remote)"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name' in Claude Desktop config"
        return 1
    fi
}

# Register a URL-based (streamable HTTP) MCP server with auth headers in Cursor global config.
# Usage: _register_cursor_url_mcp_server_with_headers <name> <url> '<headers_json_object>'
function _register_cursor_url_mcp_server_with_headers {
    local name="$1"
    local url="$2"
    local headers_json="$3"
    local cursor_config="$HOME/.cursor/mcp.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    mkdir -p "$(dirname "$cursor_config")"
    if [[ ! -f "$cursor_config" ]]; then
        echo '{"mcpServers":{}}' > "$cursor_config"
    fi

    local server_entry
    server_entry=$(jq -n --arg url "$url" --argjson headers "$headers_json" \
        '{url: $url, transport: "streamableHttp", headers: $headers}')
    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --argjson entry "$server_entry" \
        '.mcpServers[$name] = $entry' "$cursor_config" > "$tmp_config"; then
        mv "$tmp_config" "$cursor_config"
        echo "✅ Registered MCP server '$name' (with headers) in Cursor config (~/.cursor/mcp.json)"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name' in Cursor config"
        return 1
    fi
}

# Register a URL-based (streamable HTTP) MCP server in Cursor global config.
# Usage: _register_cursor_url_mcp_server <name> <url>
function _register_cursor_url_mcp_server {
    local name="$1"
    local url="$2"
    local cursor_config="$HOME/.cursor/mcp.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    mkdir -p "$(dirname "$cursor_config")"
    if [[ ! -f "$cursor_config" ]]; then
        echo '{"mcpServers":{}}' > "$cursor_config"
    fi

    local server_entry
    server_entry=$(jq -n --arg url "$url" '{url: $url, transport: "streamableHttp"}')
    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --argjson entry "$server_entry" \
        '.mcpServers[$name] = $entry' "$cursor_config" > "$tmp_config"; then
        mv "$tmp_config" "$cursor_config"
        echo "✅ Registered MCP server '$name' in Cursor config (~/.cursor/mcp.json)"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name' in Cursor config"
        return 1
    fi
}

# Register a URL-based MCP server in Cursor without forcing transport.
# Composio's current Cursor flow handles OAuth more reliably with just `url`.
function _register_cursor_oauth_mcp_server {
    local name="$1"
    local url="$2"
    local cursor_config="$HOME/.cursor/mcp.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    mkdir -p "$(dirname "$cursor_config")"
    if [[ ! -f "$cursor_config" ]]; then
        echo '{"mcpServers":{}}' > "$cursor_config"
    fi

    local server_entry
    server_entry=$(jq -n --arg url "$url" '{url: $url}')
    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --argjson entry "$server_entry" \
        '.mcpServers[$name] = $entry' "$cursor_config" > "$tmp_config"; then
        mv "$tmp_config" "$cursor_config"
        echo "✅ Registered OAuth MCP server '$name' in Cursor config (~/.cursor/mcp.json)"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register OAuth MCP server '$name' in Cursor config"
        return 1
    fi
}

# Register an MCP server in ~/.claude.json with env var passthrough (stdio)
# Usage: _register_mcp_server <name> <command> '<args_json_array>' '<env_json_object>'
function _register_mcp_server {
    local name="$1"
    local cmd="$2"
    local args_json="$3"
    local env_json="${4:-"{}"}"
    local claude_config="$HOME/.claude.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    if [[ ! -f "$claude_config" ]]; then
        echo '{"mcpServers":{}}' > "$claude_config"
    fi

    local server_entry
    server_entry=$(jq -n \
        --arg cmd "$cmd" \
        --argjson args "$args_json" \
        --argjson env "$env_json" \
        '{type: "stdio", command: $cmd, args: $args, env: $env}')

    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --argjson entry "$server_entry" \
        '.mcpServers[$name] = $entry' "$claude_config" > "$tmp_config"; then
        mv "$tmp_config" "$claude_config"
        echo "✅ Registered MCP server '$name' in $claude_config"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name'"
        return 1
    fi
}

# Register an MCP server in Claude Desktop config with literal env values baked in
# macOS only
function _register_desktop_mcp_server {
    local os_type
    os_type=$(uname -s)
    if [[ "$os_type" != "Darwin" ]]; then
        echo "ℹ️  Skipping Claude Desktop config (macOS only)"
        return 0
    fi

    local name="$1"
    local cmd="$2"
    local args_json="$3"
    local env_json="${4:-"{}"}"
    local desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    mkdir -p "$(dirname "$desktop_config")"
    if [[ ! -f "$desktop_config" ]]; then
        echo '{"mcpServers":{}}' > "$desktop_config"
    fi

    local server_entry
    server_entry=$(jq -n \
        --arg cmd "$cmd" \
        --argjson args "$args_json" \
        --argjson env "$env_json" \
        '{command: $cmd, args: $args, env: $env}')

    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --argjson entry "$server_entry" \
        '.mcpServers[$name] = $entry' "$desktop_config" > "$tmp_config"; then
        mv "$tmp_config" "$desktop_config"
        echo "✅ Registered MCP server '$name' in Claude Desktop config"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name' in Claude Desktop config"
        return 1
    fi
}

# Register an MCP server in Cursor global config (stdio)
# Usage: _register_cursor_mcp_server <name> <command> '<args_json_array>' '<env_json_object>'
function _register_cursor_mcp_server {
    local name="$1"
    local cmd="$2"
    local args_json="$3"
    local env_json="${4:-"{}"}"
    local cursor_config="$HOME/.cursor/mcp.json"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    mkdir -p "$(dirname "$cursor_config")"
    if [[ ! -f "$cursor_config" ]]; then
        echo '{"mcpServers":{}}' > "$cursor_config"
    fi

    local server_entry
    server_entry=$(jq -n \
        --arg cmd "$cmd" \
        --argjson args "$args_json" \
        --argjson env "$env_json" \
        '{type: "stdio", command: $cmd, args: $args, env: $env}')
    local tmp_config
    tmp_config=$(mktemp)
    if jq --arg name "$name" --argjson entry "$server_entry" \
        '.mcpServers[$name] = $entry' "$cursor_config" > "$tmp_config"; then
        mv "$tmp_config" "$cursor_config"
        echo "✅ Registered MCP server '$name' in Cursor config (~/.cursor/mcp.json)"
    else
        rm -f "$tmp_config"
        echo "❌ Failed to register MCP server '$name' in Cursor config"
        return 1
    fi
}

# Register an MCP server in Codex global config (stdio).
# Usage: _register_codex_mcp_server <name> <command> '<args_json_array>' '<env_json_object>'
function _register_codex_mcp_server {
    local name="$1"
    local cmd="$2"
    local args_json="$3"
    local env_json="${4:-"{}"}"

    if ! command -v jq &>/dev/null; then
        _dotfiles_jq_install_hint
        return 1
    fi

    local args=()
    local env_flags=()
    while IFS= read -r arg; do
        args+=("$arg")
    done < <(jq -r '.[]' <<< "$args_json")
    while IFS= read -r env_flag; do
        env_flags+=("$env_flag")
    done < <(jq -r 'to_entries[] | "--env=" + .key + "=" + (.value | tostring)' <<< "$env_json")

    if command -v codex &>/dev/null; then
        codex mcp remove "$name" 2>/dev/null || true
        codex mcp add "${env_flags[@]+"${env_flags[@]}"}" "$name" -- "$cmd" "${args[@]+"${args[@]}"}"
        echo "✅ Registered MCP server '$name' in Codex config"
        return 0
    fi

    _register_codex_mcp_server_toml_fallback "$name" "$cmd" "$args_json" "$env_json"
}

# Direct TOML fallback for systems where Codex is installed later or lacks
# `codex mcp add`. Keep this minimal and token-free; prefer the Codex CLI.
function _register_codex_mcp_server_toml_fallback {
    local name="$1"
    local cmd="$2"
    local args_json="$3"
    local env_json="${4:-"{}"}"
    local codex_config="$HOME/.codex/config.toml"

    mkdir -p "$(dirname "$codex_config")"
    touch "$codex_config"

    local tmp_config
    tmp_config=$(mktemp)
    awk -v section="[mcp_servers.$name]" -v env_section="[mcp_servers.$name.env]" '
        $0 == section || $0 == env_section { skip=1; next }
        skip && /^\[/ { skip=0 }
        !skip { print }
    ' "$codex_config" > "$tmp_config"

    {
        printf '\n[mcp_servers.%s]\n' "$name"
        printf 'command = %s\n' "$(jq -Rn --arg value "$cmd" '$value')"
        printf 'args = %s\n' "$(jq -c . <<< "$args_json")"
        if [[ "$(jq 'length' <<< "$env_json")" -gt 0 ]]; then
            printf '\n[mcp_servers.%s.env]\n' "$name"
            jq -r 'to_entries[] | "\(.key) = " + (.value | @json)' <<< "$env_json"
        fi
    } >> "$tmp_config"

    mv "$tmp_config" "$codex_config"
    echo "✅ Registered MCP server '$name' in $codex_config"
}

# Usage: _register_codex_url_mcp_server <name> <url> [bearer_token_env_var]
function _register_codex_url_mcp_server {
    local name="$1"
    local url="$2"
    local bearer_token_env_var="${3:-}"

    if command -v codex &>/dev/null; then
        codex mcp remove "$name" 2>/dev/null || true
        if [[ -n "$bearer_token_env_var" ]]; then
            codex mcp add "$name" --url "$url" --bearer-token-env-var "$bearer_token_env_var"
        else
            codex mcp add "$name" --url "$url"
        fi
        echo "✅ Registered URL MCP server '$name' in Codex config"
        return 0
    fi

    _register_codex_url_mcp_server_toml_fallback "$name" "$url" "$bearer_token_env_var"
}

# Direct TOML fallback for Codex URL servers. Keep token-free by referencing
# bearer_token_env_var instead of writing token literals.
function _register_codex_url_mcp_server_toml_fallback {
    local name="$1"
    local url="$2"
    local bearer_token_env_var="${3:-}"
    local codex_config="$HOME/.codex/config.toml"

    mkdir -p "$(dirname "$codex_config")"
    touch "$codex_config"

    local tmp_config
    tmp_config=$(mktemp)
    awk -v section="[mcp_servers.$name]" '
        $0 == section { skip=1; next }
        skip && /^\[/ { skip=0 }
        !skip { print }
    ' "$codex_config" > "$tmp_config"

    {
        printf '\n[mcp_servers.%s]\n' "$name"
        printf 'url = %s\n' "$(jq -Rn --arg value "$url" '$value')"
        if [[ -n "$bearer_token_env_var" ]]; then
            printf 'bearer_token_env_var = %s\n' "$(jq -Rn --arg value "$bearer_token_env_var" '$value')"
        fi
    } >> "$tmp_config"

    mv "$tmp_config" "$codex_config"
    echo "✅ Registered URL MCP server '$name' in $codex_config"
}

# Stdio MCP server with credentials: Claude Code = command + args + env (${VAR} refs);
# Desktop and Cursor = wrapper only (wrapper sources ~/.bash/credentials.bash at runtime).
# Usage: _register_stdio_mcp_with_credentials <name> <claude_cmd> <claude_args_json> <claude_env_json> <wrapper_path>
function _register_stdio_mcp_with_credentials {
    local name="$1"
    local claude_cmd="$2"
    local claude_args_json="$3"
    local claude_env_json="$4"
    local wrapper_path="$5"

    echo "Registering MCP server '$name' in Claude Code (env ref), Claude Desktop (wrapper), Cursor (wrapper)..."
    _register_mcp_server "$name" "$claude_cmd" "$claude_args_json" "$claude_env_json"
    _register_desktop_mcp_server "$name" "/bin/bash" "[\"$wrapper_path\"]" "{}"
    _register_cursor_mcp_server "$name" "/bin/bash" "[\"$wrapper_path\"]" "{}"
}
