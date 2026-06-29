#!/bin/bash

_dot_composio_auth_usage() {
    cat <<'EOF'
Usage: dot-composio-auth <status|login|reset|legacy-login|legacy-reset>

Manage Composio Connect MCP OAuth on this machine.

Composio Connect is a remote HTTP MCP server at:
  https://connect.composio.dev/mcp

Current clients use their own OAuth stores:
  Claude Code: /mcp -> composio -> Reconnect
  Codex CLI:   codex mcp login composio
  Cursor:      restart Cursor, then connect/approve composio in MCP settings

The legacy ~/.local/bin/composio-mcp wrapper is only for clients that still
need mcp-remote. It no longer sends COMPOSIO_API_KEY.

Commands:
  status   Check registrations and any legacy mcp-remote OAuth token
  login    Print native client OAuth steps
  reset    Print native client reset/reconnect steps
  legacy-login
           Start the legacy mcp-remote OAuth flow
  legacy-reset
           Clear scoped legacy Composio mcp-remote OAuth state

See ~/Code/mydot/mcp/composio-auth.md for the runbook.
EOF
}

_dot_composio_print_login_steps() {
    cat <<'EOF'
Composio uses per-client OAuth stores.

Codex:
  codex mcp login composio

Claude Code:
  /mcp -> composio -> Reconnect

Cursor:
  Restart Cursor, then connect/approve composio in MCP settings.

Composio apps:
  Connect desired apps in the Composio dashboard before using app-specific tools.
EOF
}

_dot_composio_print_reset_steps() {
    cat <<'EOF'
Composio native OAuth reset is per client.

Codex:
  codex mcp logout composio
  codex mcp login composio

Claude Code:
  /mcp -> composio -> Reconnect

Cursor:
  Disconnect/reconnect composio in MCP settings, then restart Cursor.
EOF
}

_dot_composio_mcp_url() {
    printf '%s\n' "${COMPOSIO_MCP_URL:-https://connect.composio.dev/mcp}"
}

_dot_composio_mcp_auth_dir() {
    local dir
    for dir in "$HOME"/.mcp-auth/mcp-remote-*; do
        [[ -d "$dir" ]] || continue
        printf '%s\n' "$dir"
        return 0
    done
    return 1
}

_dot_composio_probe_bearer() {
    local token="$1"
    local http_code
    http_code=$(curl --max-time 5 -sS -o /dev/null -w '%{http_code}' \
        -X POST "$(_dot_composio_mcp_url)" \
        -H "Authorization: Bearer ${token}" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"dot-composio-auth","version":"2.0"}}}' \
        2>/dev/null || echo "000")
    [[ "$http_code" == "200" ]]
}

_dot_composio_find_valid_legacy_token_file() {
    local auth_dir token_file token
    for auth_dir in "$HOME"/.mcp-auth/mcp-remote-*; do
        [[ -d "$auth_dir" ]] || continue
        for token_file in "$auth_dir"/*_tokens.json; do
            [[ -f "$token_file" ]] || continue
            token=$(jq -r '.access_token // empty' "$token_file" 2>/dev/null || true)
            [[ -n "$token" ]] || continue
            if _dot_composio_probe_bearer "$token"; then
                printf '%s\n' "$token_file"
                return 0
            fi
        done
    done
    return 1
}

_dot_composio_clear_stale_locks() {
    local auth_dir lock_file pid
    for auth_dir in "$HOME"/.mcp-auth/mcp-remote-*; do
        [[ -d "$auth_dir" ]] || continue
        for lock_file in "$auth_dir"/*_lock.json; do
            [[ -f "$lock_file" ]] || continue
            pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null || true)
            if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
                rm -f "$lock_file"
                echo "removed stale lock: $(basename "$lock_file")"
            fi
        done
    done
}

_dot_composio_registration_status() {
    local claude_config="$HOME/.claude.json"
    local cursor_config="$HOME/.cursor/mcp.json"
    local codex_config="$HOME/.codex/config.toml"
    local url
    local status=0
    url="$(_dot_composio_mcp_url)"

    if [[ -f "$claude_config" ]] && jq -e --arg url "$url" '.mcpServers.composio.url == $url' "$claude_config" >/dev/null 2>&1; then
        echo "claude_code: remote HTTP"
    else
        echo "claude_code: missing or legacy config"
        status=1
    fi

    if [[ -f "$cursor_config" ]] && jq -e --arg url "$url" '.mcpServers.composio.url == $url' "$cursor_config" >/dev/null 2>&1; then
        echo "cursor: remote HTTP"
    else
        echo "cursor: missing or legacy config"
        status=1
    fi

    if [[ -f "$codex_config" ]] && awk -v url="$url" '
        $0 == "[mcp_servers.composio]" { in_section=1; next }
        in_section && /^\[/ { in_section=0 }
        in_section && $0 ~ "^url = " {
            gsub(/^url = "/, "", $0)
            gsub(/"$/, "", $0)
            if ($0 == url) found=1
        }
        END { exit found ? 0 : 1 }
    ' "$codex_config"; then
        echo "codex: remote HTTP"
    else
        echo "codex: missing or legacy config"
        status=1
    fi

    local desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    if [[ -f "$desktop_config" ]] && jq -e '.mcpServers.composio.command and .mcpServers.composio.args' "$desktop_config" >/dev/null 2>&1; then
        echo "desktop: mcp-remote proxy"
    else
        echo "desktop: missing legacy proxy (optional)"
    fi

    return "$status"
}

_dot_composio_auth_status() {
    local wrapper="$HOME/.local/bin/composio-mcp"
    local token_file
    local status=0

    _dot_composio_registration_status || status=1

    if [[ -x "$wrapper" ]]; then
        echo "legacy_wrapper: ok ($wrapper)"
    else
        echo "legacy_wrapper: missing ($wrapper)"
    fi

    _dot_composio_clear_stale_locks >/dev/null
    if token_file="$(_dot_composio_find_valid_legacy_token_file)"; then
        echo "legacy_mcp_remote_oauth: ok ($(basename "${token_file%_tokens.json}"))"
    else
        echo "legacy_mcp_remote_oauth: missing or invalid"
    fi

    echo "codex_login: run 'codex mcp login composio' if Codex still shows auth required"
    echo "claude_login: run '/mcp' then Reconnect composio if Claude still shows failed"
    return "$status"
}

_dot_composio_reset_legacy_tokens() {
    local token_file prefix
    token_file="$(_dot_composio_find_valid_legacy_token_file)" || true
    if [[ -z "${token_file:-}" ]]; then
        echo "no working legacy Composio OAuth session found to reset"
        return 0
    fi
    prefix="${token_file%_tokens.json}"
    rm -f "${prefix}_tokens.json" "${prefix}_lock.json" "${prefix}_code_verifier.txt"
    echo "removed legacy mcp-remote Composio OAuth state: $(basename "$prefix")"
}

_dot_composio_auth_login() {
    local wrapper="$HOME/.local/bin/composio-mcp"
    local log_file pid waited auth_url

    _dot_composio_clear_stale_locks

    if [[ ! -x "$wrapper" ]]; then
        echo "dot-composio-auth: install wrapper first: ./install.sh composio" >&2
        return 1
    fi
    if ! command -v npx >/dev/null 2>&1; then
        echo "dot-composio-auth: npx not found — run './install.sh packages' first" >&2
        return 1
    fi

    if _dot_composio_find_valid_legacy_token_file >/dev/null; then
        echo "Legacy mcp-remote OAuth is already valid."
        echo "For Codex native OAuth, run: codex mcp login composio"
        return 0
    fi

    log_file="$(mktemp -t composio-auth.XXXXXX)"
    echo "Starting legacy composio-mcp OAuth flow (browser should open)..."
    echo "Log: $log_file"
    "$wrapper" >"$log_file" 2>&1 &
    pid=$!

    waited=0
    while (( waited < 180 )); do
        if grep -q 'Proxy established successfully' "$log_file"; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            echo "Legacy mcp-remote OAuth complete."
            echo "Restart any clients that use the legacy wrapper."
            rm -f "$log_file"
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "dot-composio-auth: composio-mcp exited before connecting:" >&2
            tail -30 "$log_file" >&2
            rm -f "$log_file"
            return 1
        fi
        if [[ -z "${auth_url:-}" ]] && grep -q 'Please authorize this client by visiting:' "$log_file"; then
            auth_url=$(grep -Eo 'https://login\.composio\.dev/oauth2/authorize[^[:space:]]+' "$log_file" | head -1 || true)
            if [[ -n "$auth_url" ]]; then
                echo "If the browser did not open, visit:"
                echo "$auth_url"
            fi
        fi
        sleep 1
        waited=$((waited + 1))
    done

    kill "$pid" 2>/dev/null || true
    echo "dot-composio-auth: timed out waiting for OAuth (180s). See $log_file" >&2
    return 1
}

dot-composio-auth() {
    case "${1:-}" in
        -h|--help|help|"")
            _dot_composio_auth_usage
            return 0
            ;;
        status)
            _dot_composio_auth_status
            ;;
        login)
            _dot_composio_print_login_steps
            ;;
        reset)
            _dot_composio_print_reset_steps
            ;;
        legacy-login)
            _dot_composio_auth_login
            ;;
        legacy-reset)
            _dot_composio_reset_legacy_tokens
            ;;
        *)
            echo "dot-composio-auth: unknown command: $1" >&2
            _dot_composio_auth_usage >&2
            return 2
            ;;
    esac
}
