#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$REPO_ROOT" || exit 1

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

setup_tmp() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    export HOME="$TEST_TMPDIR/home"
    export DOTFILES_REPO_DIR="$REPO_ROOT"
    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/node_modules/@openai/codex" \
        "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code" \
        "$HOME/.codex" "$HOME/.cursor" "$TEST_TMPDIR/bin"
    export PATH="$HOME/.local/bin:$TEST_TMPDIR/bin:/usr/bin:/bin"

    cat > "$HOME/.local/bin/claude" <<'BASH'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "2.1.190 (Claude Code)"; exit 0; }
exit 0
BASH
    cat > "$HOME/.local/bin/codex" <<'BASH'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "codex 0.99.0"; exit 0; }
exit 0
BASH
    cat > "$HOME/.local/bin/cursor-agent" <<'BASH'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "cursor-agent 1.2.3"; exit 0; }
exit 0
BASH
    cat > "$HOME/.local/bin/composio" <<'BASH'
#!/bin/bash
[[ "$1" == "--version" ]] && { echo "composio 9.9.9"; exit 0; }
exit 0
BASH
    chmod +x "$HOME/.local/bin/claude" "$HOME/.local/bin/codex" \
        "$HOME/.local/bin/cursor-agent" "$HOME/.local/bin/composio"

    cat > "$HOME/.codex/config.toml" <<'TOML'
[mcp_servers.composio]
url = "https://connect.composio.dev/mcp"
TOML
    cat > "$HOME/.cursor/mcp.json" <<'JSON'
{"mcpServers":{"composio":{"url":"https://connect.composio.dev/mcp"}}}
JSON
    cat > "$HOME/.claude.json" <<'JSON'
{"mcpServers":{"composio":{"type":"http","url":"https://connect.composio.dev/mcp"}}}
JSON

    # shellcheck source=/dev/null
    source "$REPO_ROOT/install/_helpers.bash"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/install/agents-doctor.bash"
}

teardown_tmp() {
    rm -rf "$TEST_TMPDIR"
}

test_agents_doctor_reports_versions_paths_and_auth() {
    setup_tmp

    install_agents_doctor > "$TEST_TMPDIR/out"

    grep -q 'Agent CLI status' "$TEST_TMPDIR/out" \
        || fail "doctor should print agent status heading"
    grep -q 'claude' "$TEST_TMPDIR/out" \
        || fail "doctor should include claude"
    grep -q "$HOME/.local/bin/codex" "$TEST_TMPDIR/out" \
        || fail "doctor should report resolved codex path"
    grep -q 'codex 0.99.0' "$TEST_TMPDIR/out" \
        || fail "doctor should report codex version"
    grep -q 'MCP registration status' "$TEST_TMPDIR/out" \
        || fail "doctor should print MCP heading"
    grep -q 'composio.*claude=ok.*cursor=ok.*codex=ok' "$TEST_TMPDIR/out" \
        || fail "doctor should report Composio registered in all native clients"

    teardown_tmp
}

test_install_sh_has_agents_doctor_target() {
    grep -q 'agents-doctor|doctor)' "$REPO_ROOT/install.sh" \
        || fail "install.sh should expose agents-doctor target"
}

test_agents_doctor_reports_versions_paths_and_auth
test_install_sh_has_agents_doctor_target

echo "agents-doctor tests passed"
