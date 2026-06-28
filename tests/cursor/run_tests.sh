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
    mkdir -p "$HOME/.local/bin" "$HOME/Library/Application Support/Cursor/User" "$TEST_TMPDIR/bin" "$TEST_TMPDIR/fake-cursor-app/bin"
    export PATH="$HOME/.local/bin:$TEST_TMPDIR/bin:/usr/bin:/bin"

    mkdir -p "$DOTFILES_REPO_DIR/ide/cursor"
    cat > "$DOTFILES_REPO_DIR/ide/cursor/settings.json" <<'JSON'
{"terminal.integrated.defaultProfile.osx": "bash", "dotfiles.marker": true}
JSON
    cat > "$DOTFILES_REPO_DIR/ide/cursor/extensions.txt" <<'TXT'
publisher.keep-me
publisher.also-keep
TXT

    cat > "$TEST_TMPDIR/fake-cursor-app/bin/code" <<'BASH'
#!/bin/bash
STATE="$HOME/.cursor-test-extensions"
mkdir -p "$(dirname "$STATE")"
touch "$STATE"
case "$1" in
  --list-extensions)
    cat "$STATE" 2>/dev/null || true
    ;;
  --install-extension)
    echo "$2" >> "$STATE"
    ;;
  --uninstall-extension)
    grep -vx "$2" "$STATE" > "$STATE.tmp" 2>/dev/null || true
    mv "$STATE.tmp" "$STATE" 2>/dev/null || : > "$STATE"
    ;;
esac
exit 0
BASH
    chmod +x "$TEST_TMPDIR/fake-cursor-app/bin/code"
    export DOTFILES_CURSOR_APP_CLI_TARGET="$TEST_TMPDIR/fake-cursor-app/bin/code"
    ln -sfn "$DOTFILES_CURSOR_APP_CLI_TARGET" "$HOME/.local/bin/cursor"
    : > "$HOME/.cursor-test-extensions"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/cursor.bash
}

test_cursor_merges_settings() {
    setup_tmp
    export DOTFILES_CURSOR_SKIP_CLI_LINK=1
    local settings="$HOME/Library/Application Support/Cursor/User/settings.json"
    echo '{"editor.fontSize": 15, "terminal.integrated.shell.osx": "/bin/bash"}' > "$settings"

    install_cursor >/dev/null

    jq -e '.["editor.fontSize"] == 15' "$settings" >/dev/null \
        || fail "merge should preserve local keys"
    jq -e '.["dotfiles.marker"] == true' "$settings" >/dev/null \
        || fail "merge should apply dotfiles settings"
}

test_cursor_prunes_extensions_not_in_list() {
    setup_tmp
    printf '%s\n' publisher.keep-me publisher.remove-me > "$HOME/.cursor-test-extensions"

    DOTFILES_CURSOR_SKIP_EXTENSION_PRUNE=0 install_cursor >/dev/null

    grep -qx publisher.keep-me "$HOME/.cursor-test-extensions" \
        || fail "allowlisted extension should remain"
    grep -qx publisher.remove-me "$HOME/.cursor-test-extensions" \
        && fail "extension not in extensions.txt should be pruned"
    grep -qx publisher.also-keep "$HOME/.cursor-test-extensions" \
        || fail "missing allowlisted extension should be installed"
}

test_cursor_extension_prune_can_be_skipped() {
    setup_tmp
    printf '%s\n' publisher.keep-me publisher.remove-me > "$HOME/.cursor-test-extensions"

    DOTFILES_CURSOR_SKIP_EXTENSION_PRUNE=1 install_cursor >/dev/null

    grep -qx publisher.remove-me "$HOME/.cursor-test-extensions" \
        || fail "prune skip should leave extra extensions installed"
}

test_cursor_prune_honors_inline_comments_in_allowlist() {
    setup_tmp
    cat > "$DOTFILES_REPO_DIR/ide/cursor/extensions.txt" <<'TXT'
publisher.keep-me  # primary
publisher.also-keep
TXT
    printf '%s\n' publisher.keep-me publisher.also-keep > "$HOME/.cursor-test-extensions"

    DOTFILES_CURSOR_SKIP_EXTENSION_PRUNE=0 install_cursor >/dev/null

    grep -qx publisher.keep-me "$HOME/.cursor-test-extensions" \
        || fail "commented allowlist entry should not be pruned"
    grep -qx publisher.also-keep "$HOME/.cursor-test-extensions" \
        || fail "allowlisted extension should remain"
}

test_cursor_ide_bin_path_prefers_local_symlink_over_brew() {
    TEST_TMPDIR=$(mktemp -d)
    export HOME="$TEST_TMPDIR/home"
    export DOTFILES_REPO_DIR="$REPO_ROOT"
    mkdir -p "$HOME/.local/bin" "$TEST_TMPDIR/fake-cursor-app/bin" "$TEST_TMPDIR/brew/bin"
    export PATH="$TEST_TMPDIR/brew/bin:$HOME/.local/bin:/usr/bin:/bin"

    printf '#!/bin/bash\nexit 0\n' > "$TEST_TMPDIR/fake-cursor-app/bin/code"
    chmod +x "$TEST_TMPDIR/fake-cursor-app/bin/code"
    export DOTFILES_CURSOR_APP_CLI_TARGET="$TEST_TMPDIR/fake-cursor-app/bin/code"

    ln -sfn "$DOTFILES_CURSOR_APP_CLI_TARGET" "$TEST_TMPDIR/brew/bin/cursor"
    ln -sfn "$DOTFILES_CURSOR_APP_CLI_TARGET" "$HOME/.local/bin/cursor"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    resolved=$(_cursor_ide_bin_path)
    [[ "$resolved" == "$HOME/.local/bin/cursor" ]] \
        || fail "expected ~/.local/bin/cursor, got: $resolved"

    rm -rf "$TEST_TMPDIR"
}

test_remove_brew_cursor_cli_shim_drops_duplicate_symlink() {
    TEST_TMPDIR=$(mktemp -d)
    export HOME="$TEST_TMPDIR/home"
    export DOTFILES_REPO_DIR="$REPO_ROOT"
    mkdir -p "$HOME/.local/bin" "$TEST_TMPDIR/fake-cursor-app/bin" "$TEST_TMPDIR/brew/bin" "$TEST_TMPDIR/bin"
    export PATH="$TEST_TMPDIR/brew/bin:$HOME/.local/bin:/usr/bin:/bin"

    printf '#!/bin/bash\nexit 0\n' > "$TEST_TMPDIR/fake-cursor-app/bin/code"
    chmod +x "$TEST_TMPDIR/fake-cursor-app/bin/code"
    export DOTFILES_CURSOR_APP_CLI_TARGET="$TEST_TMPDIR/fake-cursor-app/bin/code"

    ln -sfn "$DOTFILES_CURSOR_APP_CLI_TARGET" "$TEST_TMPDIR/brew/bin/cursor"
    ln -sfn "$DOTFILES_CURSOR_APP_CLI_TARGET" "$HOME/.local/bin/cursor"

    cat > "$TEST_TMPDIR/bin/brew" <<BASH
#!/bin/bash
echo "$TEST_TMPDIR/brew"
BASH
    chmod +x "$TEST_TMPDIR/bin/brew"
    export PATH="$TEST_TMPDIR/bin:$PATH"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    _remove_brew_cursor_cli_shim

    [[ ! -e "$TEST_TMPDIR/brew/bin/cursor" ]] \
        || fail "brew cursor shim should be removed"
    [[ -L "$HOME/.local/bin/cursor" ]] \
        || fail "local cursor symlink should remain"

    rm -rf "$TEST_TMPDIR"
}

test_cursor_merges_settings
test_cursor_prunes_extensions_not_in_list
test_cursor_extension_prune_can_be_skipped
test_cursor_prune_honors_inline_comments_in_allowlist
test_cursor_ide_bin_path_prefers_local_symlink_over_brew
test_remove_brew_cursor_cli_shim_drops_duplicate_symlink

echo "All cursor install tests passed."
