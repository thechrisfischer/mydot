#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

setup_tmp() {
    TMPDIR="$(mktemp -d)"
    export HOME="$TMPDIR/home"
    export DOTFILES_REPO_DIR="$TMPDIR/repo"
    unset COMPOSIO_API_KEY COMPOSIO_MCP_URL GREPLER_TOKEN GREPLER_URL
    mkdir -p "$HOME/.bash" "$HOME/.codex" "$HOME/.cursor" "$TMPDIR/bin" "$DOTFILES_REPO_DIR"
    ln -s "$ROOT_DIR/mcp" "$DOTFILES_REPO_DIR/mcp"

    local system_path="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
    PATH="$system_path"
    if command -v jq >/dev/null 2>&1; then
        ln -s "$(command -v jq)" "$TMPDIR/bin/jq"
    else
        fail "jq is required for MCP tests"
    fi

    # Stub node + npx so wrapper-prereq checks pass without a real Node toolchain.
    # Use /usr/bin/true (exists on both macOS and Linux); /bin/true does not exist on macOS.
    ln -s /usr/bin/true "$TMPDIR/bin/node"
    ln -s /usr/bin/true "$TMPDIR/bin/npx"

    cat > "$TMPDIR/bin/codex" <<'BASH'
#!/bin/bash
config="$HOME/.codex/config.toml"
mkdir -p "$(dirname "$config")"
case "$1 $2" in
  "mcp remove")
    exit 0
    ;;
  "mcp add")
    name=""
    url=""
    bearer=""
    cmd=""
    cmd_args=()
    shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --url)
          url="$2"
          shift 2
          ;;
        --bearer-token-env-var)
          bearer="$2"
          shift 2
          ;;
        --env)
          shift 2
          ;;
        --env=*)
          shift
          ;;
        --)
          shift
          cmd="$1"
          shift
          cmd_args=("$@")
          break
          ;;
        --*)
          shift
          ;;
        *)
          if [[ -z "$name" ]]; then
            name="$1"
          fi
          shift
          ;;
      esac
    done
    {
      printf '[mcp_servers.%s]\n' "$name"
      if [[ -n "$url" ]]; then
        printf 'url = "%s"\n' "$url"
        if [[ -n "$bearer" ]]; then
          printf 'bearer_token_env_var = "%s"\n' "$bearer"
        fi
      else
        printf 'command = "%s"\n' "$cmd"
        if [[ ${#cmd_args[@]} -gt 0 ]]; then
          args_str="["
          first=1
          for a in "${cmd_args[@]}"; do
            if [[ $first -eq 1 ]]; then
              first=0
            else
              args_str="$args_str, "
            fi
            args_str="$args_str\"$a\""
          done
          args_str="$args_str]"
          printf 'args = %s\n' "$args_str"
        fi
      fi
    } > "$config"
    ;;
esac
BASH
    chmod +x "$TMPDIR/bin/codex"
    export PATH="$TMPDIR/bin:$system_path"
}

teardown_tmp() {
    rm -rf "$TMPDIR"
}

test_airtable_is_not_enabled_in_aggregate_installer() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/install.bash"
    for server in "${DOTFILES_MCP_SERVERS[@]}"; do
        [[ "$server" != "airtable" ]] || fail "Airtable must not be enabled by ./install.sh mcp"
    done

    teardown_tmp
}

test_airtable_is_not_enabled_in_aggregate_installer

test_cleanup_removes_stale_airtable_from_codex_config() {
    setup_tmp

    cat > "$HOME/.codex/config.toml" <<'TOML'
[mcp_servers.grepler]
command = "/bin/bash"
args = ["/tmp/grepler-mcp"]

[mcp_servers.airtable]
url = "https://mcp.airtable.com/mcp"
bearer_token_env_var = "AIRTABLE_MCP_PAT"

[mcp_servers.composio]
command = "/bin/bash"
args = ["/tmp/composio-mcp"]
TOML

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/_helpers.bash"
    _cleanup_stale_mcp_servers

    ! grep -q 'mcp_servers.airtable' "$HOME/.codex/config.toml" \
        || fail "stale Airtable MCP should be removed from Codex config"
    grep -q 'mcp_servers.grepler' "$HOME/.codex/config.toml" \
        || fail "cleanup should preserve non-stale Grepler Codex config"
    grep -q 'mcp_servers.composio' "$HOME/.codex/config.toml" \
        || fail "cleanup should preserve non-stale Composio Codex config"

    teardown_tmp
}

test_cleanup_removes_stale_airtable_from_codex_config

test_cleanup_removes_stale_servers_from_all_client_configs_and_desktop_extensions() {
    setup_tmp

    local desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    mkdir -p "$(dirname "$desktop_config")"

    cat > "$HOME/.claude.json" <<'JSON'
{
  "mcpServers": {
    "airtable": {"type": "http", "url": "https://mcp.airtable.com/mcp"},
    "composio": {"type": "stdio", "command": "/bin/bash", "args": ["/tmp/composio-mcp"]},
    "example-ext": {"type": "stdio", "command": "node", "_source": "claude-extension:example"}
  }
}
JSON

    cat > "$HOME/.cursor/mcp.json" <<'JSON'
{
  "mcpServers": {
    "lifelog": {"type": "stdio", "command": "/bin/bash"},
    "grepler": {"type": "stdio", "command": "/bin/bash", "args": ["/tmp/grepler-mcp"]}
  }
}
JSON

    cat > "$desktop_config" <<'JSON'
{
  "mcpServers": {
    "glowscape": {"command": "/bin/bash", "args": ["/tmp/glowscape"]},
    "example-ext": {"command": "node", "_source": "claude-extension:example"},
    "composio": {"command": "/bin/bash", "args": ["/tmp/composio-mcp"]}
  }
}
JSON

    cat > "$HOME/.codex/config.toml" <<'TOML'
[mcp_servers.grepler]
command = "/bin/bash"
args = ["/tmp/grepler-mcp"]

[mcp_servers.lifelog]
command = "/bin/bash"
args = ["/tmp/lifelog"]
TOML

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/_helpers.bash"
    _cleanup_stale_mcp_servers

    ! jq -e '.mcpServers.airtable' "$HOME/.claude.json" >/dev/null \
        || fail "stale Airtable MCP should be removed from Claude Code config"
    jq -e '.mcpServers.composio' "$HOME/.claude.json" >/dev/null \
        || fail "cleanup should preserve active Composio Claude Code config"
    jq -e '.mcpServers["example-ext"]' "$HOME/.claude.json" >/dev/null \
        || fail "general cleanup should leave Claude Code extension entries for dot-claude-sync to reconcile"

    ! jq -e '.mcpServers.lifelog' "$HOME/.cursor/mcp.json" >/dev/null \
        || fail "stale Lifelog MCP should be removed from Cursor config"
    jq -e '.mcpServers.grepler' "$HOME/.cursor/mcp.json" >/dev/null \
        || fail "cleanup should preserve active Grepler Cursor config"

    ! jq -e '.mcpServers.glowscape' "$desktop_config" >/dev/null \
        || fail "stale Glowscape MCP should be removed from Claude Desktop config"
    ! jq -e '.mcpServers["example-ext"]' "$desktop_config" >/dev/null \
        || fail "extension-managed MCP entries should be pruned from Claude Desktop config"
    jq -e '.mcpServers.composio' "$desktop_config" >/dev/null \
        || fail "cleanup should preserve active Composio Claude Desktop config"

    ! grep -q 'mcp_servers.lifelog' "$HOME/.codex/config.toml" \
        || fail "stale Lifelog MCP should be removed from Codex config"
    grep -q 'mcp_servers.grepler' "$HOME/.codex/config.toml" \
        || fail "cleanup should preserve active Grepler Codex config"

    teardown_tmp
}

test_cleanup_removes_stale_servers_from_all_client_configs_and_desktop_extensions

test_composio_registers_remote_oauth_without_api_key() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/composio.bash"
    install_composio >/tmp/composio-test.out 2>&1

    [[ -x "$HOME/.local/bin/composio-mcp" ]] \
        || fail "Composio legacy wrapper should be created and executable"

    grep -q 'mcp_servers.composio' "$HOME/.codex/config.toml" \
        || fail "Composio MCP should remain registered in Codex config"
    grep -q 'url = "https://connect.composio.dev/mcp"' "$HOME/.codex/config.toml" \
        || fail "Codex registration should use native remote HTTP OAuth"

    jq -e '.mcpServers.composio.url == "https://connect.composio.dev/mcp"' "$HOME/.cursor/mcp.json" >/dev/null \
        || fail "Composio MCP should use native remote HTTP OAuth in Cursor config"
    ! jq -e '.mcpServers.composio.transport' "$HOME/.cursor/mcp.json" >/dev/null \
        || fail "Composio Cursor config should not force transport"

    jq -e '.mcpServers.composio.type == "http" and .mcpServers.composio.url == "https://connect.composio.dev/mcp"' "$HOME/.claude.json" >/dev/null \
        || fail "Composio MCP should use native remote HTTP OAuth in Claude Code config"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
        jq -e '.mcpServers.composio' "$desktop_config" >/dev/null \
            || fail "Composio MCP should remain registered in Claude Desktop config (macOS)"
    fi

    grep -q 'codex mcp login composio' /tmp/composio-test.out \
        || fail "install output should explain Codex OAuth login"

    rm -f /tmp/composio-test.out
    teardown_tmp
}

test_composio_registers_remote_oauth_without_api_key

test_composio_native_clients_register_without_npx() {
    setup_tmp
    rm -f "$TMPDIR/bin/npx"
    export PATH="$TMPDIR/bin:/usr/bin:/bin"

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/composio.bash"
    install_composio >/tmp/composio-no-npx-test.out 2>&1

    jq -e '.mcpServers.composio.type == "http"' "$HOME/.claude.json" >/dev/null \
        || fail "Claude Code should register without npx"
    jq -e '.mcpServers.composio.url == "https://connect.composio.dev/mcp"' "$HOME/.cursor/mcp.json" >/dev/null \
        || fail "Cursor should register without npx"
    grep -q 'url = "https://connect.composio.dev/mcp"' "$HOME/.codex/config.toml" \
        || fail "Codex should register without npx"
    grep -q 'Claude Desktop Composio registration skipped' /tmp/composio-no-npx-test.out \
        || fail "missing npx should be reported as Desktop-only"

    rm -f /tmp/composio-no-npx-test.out
    teardown_tmp
}

test_composio_native_clients_register_without_npx

test_composio_codex_registration_does_not_call_codex_cli() {
    setup_tmp

    cat > "$TMPDIR/bin/codex" <<'BASH'
#!/bin/bash
echo "codex CLI should not be called for Composio install" >&2
exit 99
BASH
    chmod +x "$TMPDIR/bin/codex"

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/composio.bash"
    install_composio >/tmp/composio-codex-direct-test.out 2>&1

    grep -q 'url = "https://connect.composio.dev/mcp"' "$HOME/.codex/config.toml" \
        || fail "Composio should write Codex TOML directly"
    ! grep -q 'codex CLI should not be called' /tmp/composio-codex-direct-test.out \
        || fail "Composio install should not invoke codex CLI"

    rm -f /tmp/composio-codex-direct-test.out
    teardown_tmp
}

test_composio_codex_registration_does_not_call_codex_cli

test_cursor_generic_url_helper_keeps_explicit_transport() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/_helpers.bash"
    _register_cursor_url_mcp_server "example" "https://example.com/mcp" >/tmp/cursor-helper-test.out 2>&1

    jq -e '.mcpServers.example.transport == "streamableHttp"' "$HOME/.cursor/mcp.json" >/dev/null \
        || fail "generic Cursor URL helper should keep explicit streamableHttp transport"

    rm -f /tmp/cursor-helper-test.out
    teardown_tmp
}

test_cursor_generic_url_helper_keeps_explicit_transport

test_dot_composio_auth_status_fails_when_registrations_missing() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$ROOT_DIR/.bash/functions/dot-composio-auth.bash"
    if dot-composio-auth status >/tmp/composio-status-test.out 2>&1; then
        cat /tmp/composio-status-test.out >&2
        fail "status should fail when Composio registrations are missing"
    fi

    grep -q 'missing or legacy config' /tmp/composio-status-test.out \
        || fail "status output should explain missing registrations"

    rm -f /tmp/composio-status-test.out
    teardown_tmp
}

test_dot_composio_auth_status_fails_when_registrations_missing

test_dot_composio_auth_login_prints_native_client_steps() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$ROOT_DIR/.bash/functions/dot-composio-auth.bash"
    dot-composio-auth login >/tmp/composio-login-test.out 2>&1

    grep -q 'codex mcp login composio' /tmp/composio-login-test.out \
        || fail "login should direct users to Codex native OAuth"
    grep -q '/mcp' /tmp/composio-login-test.out \
        || fail "login should direct users to Claude Code MCP reconnect"
    grep -q 'Cursor' /tmp/composio-login-test.out \
        || fail "login should direct users to Cursor MCP approval"

    rm -f /tmp/composio-login-test.out
    teardown_tmp
}

test_dot_composio_auth_login_prints_native_client_steps

test_dot_composio_auth_reset_prints_native_client_steps() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$ROOT_DIR/.bash/functions/dot-composio-auth.bash"
    dot-composio-auth reset >/tmp/composio-native-reset-test.out 2>&1

    grep -q 'codex mcp logout composio' /tmp/composio-native-reset-test.out \
        || fail "reset should direct users to Codex native logout"
    grep -q 'codex mcp login composio' /tmp/composio-native-reset-test.out \
        || fail "reset should direct users to Codex native login"
    grep -q '/mcp' /tmp/composio-native-reset-test.out \
        || fail "reset should direct users to Claude Code MCP reconnect"

    rm -f /tmp/composio-native-reset-test.out
    teardown_tmp
}

test_dot_composio_auth_reset_prints_native_client_steps

test_dot_composio_auth_legacy_reset_only_removes_valid_legacy_prefix() {
    setup_tmp

    local auth_dir="$HOME/.mcp-auth/mcp-remote-0.1.37"
    mkdir -p "$auth_dir"
    printf '{"access_token":"valid"}\n' > "$auth_dir/composio_tokens.json"
    printf 'verifier\n' > "$auth_dir/composio_code_verifier.txt"
    printf '{"pid":999999}\n' > "$auth_dir/composio_lock.json"
    printf '{"access_token":"other"}\n' > "$auth_dir/other_tokens.json"
    printf 'verifier\n' > "$auth_dir/other_code_verifier.txt"

    # shellcheck source=/dev/null
    source "$ROOT_DIR/.bash/functions/dot-composio-auth.bash"
    _dot_composio_probe_bearer() {
        [[ "$1" == "valid" ]]
    }
    dot-composio-auth legacy-reset >/tmp/composio-reset-test.out 2>&1

    [[ ! -e "$auth_dir/composio_tokens.json" ]] \
        || fail "reset should remove valid Composio legacy token"
    [[ ! -e "$auth_dir/composio_code_verifier.txt" ]] \
        || fail "reset should remove matching Composio verifier"
    [[ -e "$auth_dir/other_tokens.json" ]] \
        || fail "reset should preserve unrelated legacy token"
    [[ -e "$auth_dir/other_code_verifier.txt" ]] \
        || fail "reset should preserve unrelated verifier"

    rm -f /tmp/composio-reset-test.out
    teardown_tmp
}

test_dot_composio_auth_legacy_reset_only_removes_valid_legacy_prefix

test_grepler_stays_registered_when_token_missing_but_install_fails() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/grepler.bash"
    if install_grepler >/tmp/grepler-test.out 2>&1; then
        cat /tmp/grepler-test.out >&2
        fail "expected Grepler install to fail without GREPLER_TOKEN"
    fi

    [[ -x "$HOME/.local/bin/grepler-mcp" ]] \
        || fail "Grepler wrapper should be created and executable"

    grep -q 'mcp_servers.grepler' "$HOME/.codex/config.toml" \
        || fail "Grepler MCP should remain registered in Codex config"
    grep -q 'command = "/bin/bash"' "$HOME/.codex/config.toml" \
        || fail "Codex registration should use /bin/bash + wrapper (stdio form)"

    jq -e '.mcpServers.grepler' "$HOME/.cursor/mcp.json" >/dev/null \
        || fail "Grepler MCP should remain registered in Cursor config"

    jq -e '.mcpServers.grepler' "$HOME/.claude.json" >/dev/null \
        || fail "Grepler MCP should remain registered in Claude Code config"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
        jq -e '.mcpServers.grepler' "$desktop_config" >/dev/null \
            || fail "Grepler MCP should remain registered in Claude Desktop config (macOS)"
    fi

    grep -q 'registered but inaccessible' /tmp/grepler-test.out \
        || fail "missing-token failure should explain inaccessible MCP"

    rm -f /tmp/grepler-test.out
    teardown_tmp
}

test_grepler_stays_registered_when_token_missing_but_install_fails

test_playwright_registers_without_required_token() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$ROOT_DIR/mcp/playwright.bash"
    install_playwright >/tmp/playwright-test.out 2>&1

    [[ -x "$HOME/.local/bin/playwright-mcp" ]] \
        || fail "Playwright wrapper should be created and executable"
    grep -q '@playwright/mcp@' "$HOME/.local/bin/playwright-mcp" \
        || fail "Playwright wrapper should invoke pinned @playwright/mcp version"
    ! grep -q '@playwright/mcp@latest' "$HOME/.local/bin/playwright-mcp" \
        || fail "Playwright wrapper should not use @latest"

    jq -e '.mcpServers.playwright.command == "/bin/bash"' "$HOME/.claude.json" >/dev/null \
        || fail "Playwright should be registered in Claude Code"
    jq -e '.mcpServers.playwright' "$HOME/.cursor/mcp.json" >/dev/null \
        || fail "Playwright should be registered in Cursor"
    grep -q 'mcp_servers.playwright' "$HOME/.codex/config.toml" \
        || fail "Playwright should be registered in Codex"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        desktop_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
        jq -e '.mcpServers.playwright' "$desktop_config" >/dev/null \
            || fail "Playwright should be registered in Claude Desktop config (macOS)"
    fi

    grep -q 'Playwright MCP Bridge' /tmp/playwright-test.out \
        || fail "install should remind about Chrome extension"
    rm -f /tmp/playwright-test.out
    teardown_tmp
}

test_playwright_registers_without_required_token

echo "mcp tests passed"
