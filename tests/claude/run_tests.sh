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
    export DOTFILES_REPO_DIR="$HOME/dotfiles"
    mkdir -p "$HOME/.local/bin" "$HOME/.claude" "$DOTFILES_REPO_DIR/ide" "$DOTFILES_REPO_DIR/install"

    cp -R ide/claude "$DOTFILES_REPO_DIR/ide/"
    cp -R mcp "$DOTFILES_REPO_DIR/mcp/"
    cp install/_helpers.bash "$DOTFILES_REPO_DIR/install/_helpers.bash"
    cp install/claude.bash "$DOTFILES_REPO_DIR/install/claude.bash"

    cat > "$HOME/.local/bin/claude" <<'BASH'
#!/bin/bash
printf 'claude' >> "$HOME/claude-plugin.log"
printf ' %q' "$@" >> "$HOME/claude-plugin.log"
printf '\n' >> "$HOME/claude-plugin.log"
case "$1" in
    plugin)
        case "$2" in
            install) exit 0 ;;
            enable) exit 0 ;;
        esac
        ;;
esac
exit 0
BASH
    chmod +x "$HOME/.local/bin/claude"

    export PATH="$HOME/.local/bin:/usr/bin:/bin"

    # shellcheck source=/dev/null
    source "$DOTFILES_REPO_DIR/install/_helpers.bash"
    # shellcheck source=/dev/null
    source "$DOTFILES_REPO_DIR/install/claude.bash"
}

test_claude_settings_merge_preserves_enabled_plugins() {
    setup_tmp
    local settings="$HOME/.claude/settings.json"
    cat > "$settings" <<'JSON'
{
  "effortLevel": "high",
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  }
}
JSON

    install_claude >/dev/null

    jq -e '.effortLevel == "high"' "$settings" >/dev/null \
        || fail "merge should preserve unrelated user settings"
    jq -e '.enabledPlugins["superpowers@claude-plugins-official"] == true' "$settings" >/dev/null \
        || fail "merge should preserve existing enabledPlugins entries"
    jq -e '.enabledPlugins["chrome-devtools-mcp@claude-plugins-official"] == true' "$settings" >/dev/null \
        || fail "merge should add chrome-devtools plugin"
    jq -e '.claudeInChromeDefaultEnabled == true' "$settings" >/dev/null \
        || fail "merge should enable Claude in Chrome by default"
    jq -e '.autoUpdatesChannel == "latest"' "$settings" >/dev/null \
        || fail "merge should set Claude Code auto-updates to the latest channel"
}

test_claude_wrapper_passes_chrome_by_default() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:/usr/bin:/bin"

    cat > "$HOME/.local/bin/claude" <<'BASH'
#!/bin/bash
printf '%s\n' "$@" > "$HOME/claude-args.txt"
BASH
    chmod +x "$HOME/.local/bin/claude"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/claude.bash"

    claude --version >/dev/null
    grep -qx -- '--chrome' "$HOME/claude-args.txt" \
        || fail "claude wrapper should pass --chrome by default"
    grep -qx -- '--version' "$HOME/claude-args.txt" \
        || fail "claude wrapper should forward user args"
}

test_claude_wrapper_respects_no_chrome() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:/usr/bin:/bin"

    cat > "$HOME/.local/bin/claude" <<'BASH'
#!/bin/bash
printf '%s\n' "$@" > "$HOME/claude-args.txt"
BASH
    chmod +x "$HOME/.local/bin/claude"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/claude.bash"

    claude --no-chrome --version >/dev/null
    ! grep -qx -- '--chrome' "$HOME/claude-args.txt" \
        || fail "claude --no-chrome should not pass --chrome"
}

test_claude_wrapper_skip_env() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:/usr/bin:/bin"
    export DOTFILES_CLAUDE_SKIP_CHROME=1

    cat > "$HOME/.local/bin/claude" <<'BASH'
#!/bin/bash
printf '%s\n' "$@" > "$HOME/claude-args.txt"
BASH
    chmod +x "$HOME/.local/bin/claude"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/claude.bash"

    claude --version >/dev/null
    ! grep -qx -- '--chrome' "$HOME/claude-args.txt" \
        || fail "DOTFILES_CLAUDE_SKIP_CHROME=1 should skip --chrome"
}

test_claude_settings_merge_preserves_enabled_plugins
test_claude_wrapper_passes_chrome_by_default
test_claude_wrapper_respects_no_chrome
test_claude_wrapper_skip_env

echo "claude tests passed"
