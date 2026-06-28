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
    mkdir -p "$HOME/.local/bin" "$TEST_TMPDIR/bin"
    export PATH="$TEST_TMPDIR/bin:$HOME/.local/bin:/usr/bin:/bin"
    : > "$TEST_TMPDIR/log"

    cat > "$TEST_TMPDIR/bin/npm" <<'BASH'
#!/bin/bash
printf 'npm <%s>' "$@" >> "$TEST_TMPDIR/log"
printf '\n' >> "$TEST_TMPDIR/log"
case "$1" in
  list) exit 1 ;;
  install|update|uninstall) exit 0 ;;
esac
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/npm"

    cat > "$TEST_TMPDIR/bin/curl" <<'BASH'
#!/bin/bash
printf 'curl <%s>\n' "$*" >> "$TEST_TMPDIR/log"
exit 1
BASH
    chmod +x "$TEST_TMPDIR/bin/curl"

    cat > "$TEST_TMPDIR/bin/brew" <<'BASH'
#!/bin/bash
printf 'brew <%s>' "$@" >> "$TEST_TMPDIR/log"
printf '\n' >> "$TEST_TMPDIR/log"
case "$1 $2" in
  "list --cask") exit 1 ;;
  "uninstall --cask") exit 0 ;;
esac
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/brew"
    hash -r
}

teardown_tmp() {
    rm -rf "$TEST_TMPDIR"
}

test_sudo_keepalive_refresh_is_noninteractive() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/sudo" <<'BASH'
#!/bin/bash
printf 'sudo' >> "$TEST_TMPDIR/log"
printf ' <%s>' "$@" >> "$TEST_TMPDIR/log"
printf '\n' >> "$TEST_TMPDIR/log"
if [[ "$1" == "-n" ]]; then
    shift
    case "$1" in
        -v) exit 0 ;;
    esac
fi
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/sudo"
    hash -r

    # shellcheck source=/dev/null
    source install/_helpers.bash
    _DOTFILES_SUDO_KEEPALIVE_PID=$$

    _ensure_sudo_cached

    grep -q 'sudo <-n> <-v>' "$TEST_TMPDIR/log" \
        || fail "sudo cache refresh should use sudo -n -v; log=$(cat "$TEST_TMPDIR/log")"
    ! grep -qx 'sudo <-v>' "$TEST_TMPDIR/log" \
        || fail "sudo cache refresh should not prompt with bare sudo -v; log=$(cat "$TEST_TMPDIR/log")"

    _stop_sudo_keepalive
    teardown_tmp
}

test_sudo_keepalive_spawn_skips_installer_pid_pin() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/sudo" <<'BASH'
#!/bin/bash
printf 'sudo <%s>\n' "$*" >> "$TEST_TMPDIR/log"
if [[ "$1" == "-n" ]]; then
    shift
    case "$1" in -v) exit 0 ;; esac
fi
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/sudo"
    hash -r

    # shellcheck source=/dev/null
    source install/_helpers.bash
    _DOTFILES_SUDO_KEEPALIVE_PID=$$

    _spawn_sudo_keepalive

    [[ -n "${_DOTFILES_SUDO_KEEPALIVE_PID:-}" ]] \
        || fail "spawn should replace a pinned installer PID with a real worker"
    [[ "$_DOTFILES_SUDO_KEEPALIVE_PID" != "$$" ]] \
        || fail "keepalive worker should not be the installer shell"
    kill -0 "$_DOTFILES_SUDO_KEEPALIVE_PID" \
        || fail "keepalive worker should be running"

    _stop_sudo_keepalive
    teardown_tmp
}

test_agent_bin_path_missing_does_not_abort_under_set_e() {
    setup_tmp

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/packages.bash

    local bin
    bin=$(_agent_bin_path claude-not-installed-xyz)
    [[ -z "$bin" ]] \
        || fail "expected empty path when command is missing; got: $bin"

    teardown_tmp
}

test_classify_agent_install_detects_brew_global_npm() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/opt/homebrew/bin" \
        "$TEST_TMPDIR/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin"
    cat > "$TEST_TMPDIR/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe" <<'BASH'
#!/bin/bash
exit 0
BASH
    chmod +x "$TEST_TMPDIR/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
    ln -sf ../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
        "$TEST_TMPDIR/opt/homebrew/bin/claude"
    export PATH="$TEST_TMPDIR/opt/homebrew/bin:$PATH"
    hash -r 2>/dev/null || true

    # shellcheck source=/dev/null
    source install/_helpers.bash

    [[ "$(_classify_agent_install claude @anthropic-ai/claude-code)" == "brew-global-npm" ]] \
        || fail "expected brew-global-npm classification; got $(_classify_agent_install claude @anthropic-ai/claude-code)"

    teardown_tmp
}

test_remove_off_prefix_npm_agent_uninstalls_brew_copy() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/opt/homebrew/bin" \
        "$TEST_TMPDIR/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin" \
        "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe" <<'BASH'
#!/bin/bash
exit 0
BASH
    chmod +x "$TEST_TMPDIR/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
    ln -sf ../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
        "$TEST_TMPDIR/opt/homebrew/bin/claude"
    export PATH="$TEST_TMPDIR/bin:$TEST_TMPDIR/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin"
    hash -r 2>/dev/null || true

    cat > "$TEST_TMPDIR/bin/npm" <<'BASH'
#!/bin/bash
printf 'npm <%s>' "$@" >> "$TEST_TMPDIR/log"
printf '\n' >> "$TEST_TMPDIR/log"
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/npm"

    cat > "$TEST_TMPDIR/bin/brew" <<'BASH'
#!/bin/bash
if [[ "$1" == --prefix ]]; then
  printf '%s\n' "$TEST_TMPDIR/opt/homebrew"
  exit 0
fi
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/brew"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    _remove_off_prefix_npm_agent claude @anthropic-ai/claude-code

    grep -q 'npm <uninstall>npm <-g>npm <@anthropic-ai/claude-code>' "$TEST_TMPDIR/log" \
        || fail "brew-prefix npm uninstall should run during migration"

    teardown_tmp
}

test_remove_off_prefix_npm_agent_uninstalls_hidden_brew_copy() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/opt/homebrew/bin" \
        "$TEST_TMPDIR/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin" \
        "$HOME/.local/bin" \
        "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code" \
        "$TEST_TMPDIR/bin"
    cat > "$HOME/.local/bin/claude" <<'BASH'
#!/bin/bash
exit 0
BASH
    chmod +x "$HOME/.local/bin/claude"
    export PATH="$TEST_TMPDIR/bin:$HOME/.local/bin:$TEST_TMPDIR/opt/homebrew/bin:/usr/bin:/bin"
    hash -r 2>/dev/null || true

    cat > "$TEST_TMPDIR/bin/npm" <<'BASH'
#!/bin/bash
printf 'npm prefix=<%s>' "${NPM_CONFIG_PREFIX:-}" >> "$TEST_TMPDIR/log"
printf ' <%s>' "$@" >> "$TEST_TMPDIR/log"
printf '\n' >> "$TEST_TMPDIR/log"
case "${NPM_CONFIG_PREFIX:-}:$1" in
  "$TEST_TMPDIR/opt/homebrew:list") exit 0 ;;
  "$TEST_TMPDIR/opt/homebrew:uninstall") exit 0 ;;
esac
exit 1
BASH
    chmod +x "$TEST_TMPDIR/bin/npm"

    cat > "$TEST_TMPDIR/bin/brew" <<'BASH'
#!/bin/bash
if [[ "$1" == --prefix ]]; then
  printf '%s\n' "$TEST_TMPDIR/opt/homebrew"
  exit 0
fi
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/brew"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    _remove_off_prefix_npm_agent claude @anthropic-ai/claude-code

    grep -q 'npm prefix=<.*opt/homebrew> <uninstall> <-g> <@anthropic-ai/claude-code>' "$TEST_TMPDIR/log" \
        || fail "hidden brew-prefix npm install should be uninstalled even when ~/.local/bin shadows it"

    teardown_tmp
}

test_apps_routes_cursor_through_dedicated_installer() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/uname" <<'BASH'
#!/bin/bash
printf 'TestOS\n'
BASH
    chmod +x "$TEST_TMPDIR/bin/uname"
    hash -r

    # shellcheck source=/dev/null
    source install/apps.bash
    # shellcheck disable=SC2329
    _ensure_brew() { printf '_ensure_brew\n' >> "$TEST_TMPDIR/log"; return 0; }
    # shellcheck disable=SC2329
    _brew_cask_install() { printf '_brew_cask_install <%s>\n' "$1" >> "$TEST_TMPDIR/log"; return 0; }
    # shellcheck disable=SC2329
    _install_cursor_app() { printf '_install_cursor_app\n' >> "$TEST_TMPDIR/log"; return 0; }

    install_apps >/dev/null

    grep -q '_brew_cask_install <google-chrome>' "$TEST_TMPDIR/log" \
        || fail "Chrome should still use the generic cask installer"
    grep -q '_install_cursor_app' "$TEST_TMPDIR/log" \
        || fail "Cursor should use the dedicated app installer"
    ! grep -q '_brew_cask_install <cursor>' "$TEST_TMPDIR/log" \
        || fail "Cursor should not use the generic cask installer"

    # Personal, account-gated apps must NOT be installed by default.
    local personal_app
    for personal_app in google-drive granola wispr-flow superhuman slack tailscale-app; do
        ! grep -q "_brew_cask_install <$personal_app>" "$TEST_TMPDIR/log" \
            || fail "$personal_app is a personal app and should not be installed by default"
    done

    teardown_tmp
}

test_cursor_app_installs_without_binaries_and_links_launcher() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/brew" <<'BASH'
#!/bin/bash
printf 'brew <%s>' "$@" >> "$TEST_TMPDIR/log"
printf '\n' >> "$TEST_TMPDIR/log"
case "$*" in
  "list --cask cursor") exit 1 ;;
  "install --cask --no-binaries cursor")
    echo "Error: It seems there is already an App at '/Applications/Cursor.app'."
    exit 1 ;;
  "install --cask --no-binaries --adopt cursor") exit 0 ;;
  *) exit 0 ;;
esac
BASH
    chmod +x "$TEST_TMPDIR/bin/brew"
    hash -r

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/apps.bash
    # shellcheck disable=SC2329
    _brew_update_once() { :; }
    # shellcheck disable=SC2329
    _link_cursor_launcher() { printf '_link_cursor_launcher\n' >> "$TEST_TMPDIR/log"; return 0; }

    _install_cursor_app >/dev/null

    grep -q 'brew <install>brew <--cask>brew <--no-binaries>brew <--adopt>brew <cursor>' "$TEST_TMPDIR/log" \
        || fail "Cursor should adopt when app already exists at /Applications"
    grep -q '_link_cursor_launcher' "$TEST_TMPDIR/log" \
        || fail "Cursor installer should link the launcher manually"

    teardown_tmp
}

test_cursor_app_installs_without_binaries_when_fresh() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/brew" <<'BASH'
#!/bin/bash
printf 'brew <%s>' "$@" >> "$TEST_TMPDIR/log"
printf '\n' >> "$TEST_TMPDIR/log"
case "$*" in
  "list --cask cursor") exit 1 ;;
  "install --cask --no-binaries cursor") exit 0 ;;
  *) exit 0 ;;
esac
BASH
    chmod +x "$TEST_TMPDIR/bin/brew"
    hash -r

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/apps.bash
    # shellcheck disable=SC2329
    _brew_update_once() { :; }
    # shellcheck disable=SC2329
    _link_cursor_launcher() { printf '_link_cursor_launcher\n' >> "$TEST_TMPDIR/log"; return 0; }

    _install_cursor_app >/dev/null

    grep -q 'brew <install>brew <--cask>brew <--no-binaries>brew <cursor>' "$TEST_TMPDIR/log" \
        || fail "Cursor should install with --no-binaries"
    ! grep -q 'brew <--adopt>' "$TEST_TMPDIR/log" \
        || fail "Cursor should not adopt when a fresh install succeeds"
    grep -q '_link_cursor_launcher' "$TEST_TMPDIR/log" \
        || fail "Cursor installer should link the launcher manually"

    teardown_tmp
}

load_installers_with_stubs() {
    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/packages.bash

    _is_linux() { return 1; }
    _prefer_macports() { return 1; }
    _ensure_brew() { printf '_ensure_brew\n' >> "$TEST_TMPDIR/log"; return 0; }
    _brew_update_once() { :; }
    _pkg_install() { printf '_pkg_install <%s>\n' "$1" >> "$TEST_TMPDIR/log"; return 0; }
    _ensure_node_package_manager() { printf '_ensure_node_package_manager\n' >> "$TEST_TMPDIR/log"; return 0; }
    _ensure_flake8_command() { printf '_ensure_flake8_command\n' >> "$TEST_TMPDIR/log"; return 0; }
    _install_reattach_to_user_namespace() { printf '_install_reattach <%s>\n' "$1" >> "$TEST_TMPDIR/log"; return 0; }
    _install_awscli_with_fallback() { printf '_install_awscli\n' >> "$TEST_TMPDIR/log"; return 0; }
    _pip_install() { printf '_pip_install <%s>\n' "$1" >> "$TEST_TMPDIR/log"; return 0; }
    _install_cursor_agent_direct() { printf '_install_cursor_agent_direct\n' >> "$TEST_TMPDIR/log"; return 0; }
    _install_composio_direct() { printf '_install_composio_direct\n' >> "$TEST_TMPDIR/log"; return 0; }
    _install_impeccable_cli() { printf '_install_impeccable_cli\n' >> "$TEST_TMPDIR/log"; return 0; }
    _install_impeccable_skill() { printf '_install_impeccable_skill\n' >> "$TEST_TMPDIR/log"; return 0; }
    _brew_cask_install() { printf '_brew_cask_install <%s>\n' "$1" >> "$TEST_TMPDIR/log"; return 0; }
}

test_agents_install_without_homebrew_casks() {
    setup_tmp
    load_installers_with_stubs

    install_packages >/dev/null

    grep -q 'npm <install>npm <-g>npm <@openai/codex@latest>npm <--include=optional>' "$TEST_TMPDIR/log" \
        || fail "Codex should install through managed npm prefix with optional deps"
    grep -q 'npm <install>npm <-g>npm <@anthropic-ai/claude-code@latest>npm <--ignore-scripts=false>npm <--include=optional>' "$TEST_TMPDIR/log" \
        || fail "Claude Code should install through managed npm prefix with scripts and optional deps"
    ! grep -q '_brew_cask_install <codex>' "$TEST_TMPDIR/log" \
        || fail "Codex should not install through Homebrew cask"
    ! grep -q '_brew_cask_install <claude-code' "$TEST_TMPDIR/log" \
        || fail "Claude Code should not install through Homebrew cask"

    teardown_tmp
}

test_claude_code_forces_arm64_optional_dep_under_rosetta() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/sysctl" <<'BASH'
#!/bin/bash
case "$*" in
  "-n hw.optional.arm64") echo "1" ;;
  "-n sysctl.proc_translated") echo "1" ;;
  *) exit 1 ;;
esac
BASH
    cat > "$TEST_TMPDIR/bin/uname" <<'BASH'
#!/bin/bash
printf 'Darwin\n'
BASH
    chmod +x "$TEST_TMPDIR/bin/sysctl"
    chmod +x "$TEST_TMPDIR/bin/uname"
    hash -r

    load_installers_with_stubs

    _install_claude_code_managed_npm >/dev/null

    grep -q 'npm <install>npm <-g>npm <@anthropic-ai/claude-code@latest>npm <--ignore-scripts=false>npm <--include=optional>npm <--os=darwin>npm <--cpu=arm64>' "$TEST_TMPDIR/log" \
        || fail "Claude Code should force the arm64 optional dependency when Node runs under Rosetta"

    teardown_tmp
}

test_claude_code_existing_managed_npm_uses_latest_package_install() {
    setup_tmp
    load_installers_with_stubs

    mkdir -p "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/bin"
    cat > "$HOME/.local/bin/claude" <<'BASH'
#!/bin/bash
printf 'claude <%s>\n' "$*" >> "$TEST_TMPDIR/log"
exit 0
BASH
    chmod +x "$HOME/.local/bin/claude"
    touch "$HOME/.local/lib/node_modules/@anthropic-ai/claude-code/package.json"
    hash -r

    _install_claude_code_managed_npm >/dev/null

    grep -q 'npm <install>npm <-g>npm <@anthropic-ai/claude-code@latest>npm <--ignore-scripts=false>npm <--include=optional>' "$TEST_TMPDIR/log" \
        || fail "Existing managed Claude Code npm installs should be upgraded with @latest package install"
    ! grep -q 'claude <update>' "$TEST_TMPDIR/log" \
        || fail "Existing managed Claude Code npm installs should not rely on claude update"

    teardown_tmp
}

test_codex_forces_arm64_optional_dep_on_apple_silicon() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/sysctl" <<'BASH'
#!/bin/bash
case "$*" in
  "-n hw.optional.arm64") echo "1" ;;
  *) exit 1 ;;
esac
BASH
    cat > "$TEST_TMPDIR/bin/uname" <<'BASH'
#!/bin/bash
printf 'Darwin\n'
BASH
    chmod +x "$TEST_TMPDIR/bin/sysctl"
    chmod +x "$TEST_TMPDIR/bin/uname"
    hash -r

    load_installers_with_stubs

    _install_codex_managed_npm >/dev/null

    grep -q 'npm <install>npm <-g>npm <@openai/codex@latest>npm <--include=optional>npm <--os=darwin>npm <--cpu=arm64>' "$TEST_TMPDIR/log" \
        || fail "Codex should force the arm64 optional dependency on Apple Silicon"

    teardown_tmp
}

test_cursor_agent_existing_install_reruns_official_installer() {
    setup_tmp

    mkdir -p "$HOME/.local/share/cursor-agent/versions/1/bin"
    cat > "$HOME/.local/bin/cursor-agent" <<'BASH'
#!/bin/bash
printf 'cursor-agent <%s>\n' "$*" >> "$TEST_TMPDIR/log"
exit 0
BASH
    chmod +x "$HOME/.local/bin/cursor-agent"
    hash -r

    cat > "$TEST_TMPDIR/bin/curl" <<'BASH'
#!/bin/bash
cat <<'SCRIPT'
#!/bin/bash
printf 'cursor-installer\n' >> "$TEST_TMPDIR/log"
SCRIPT
BASH
    chmod +x "$TEST_TMPDIR/bin/curl"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/packages.bash

    _install_cursor_agent_direct >/dev/null

    grep -q 'cursor-installer' "$TEST_TMPDIR/log" \
        || fail "existing cursor-agent should still rerun the official installer to refresh"

    teardown_tmp
}

test_composio_direct_links_installed_binary_into_local_bin() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/curl" <<'BASH'
#!/bin/bash
cat <<'SCRIPT'
#!/bin/bash
mkdir -p "$HOME/.composio"
cat > "$HOME/.composio/composio" <<'COMPOSIO'
#!/bin/bash
echo composio test
COMPOSIO
chmod +x "$HOME/.composio/composio"
SCRIPT
BASH
    chmod +x "$TEST_TMPDIR/bin/curl"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/packages.bash

    _install_composio_direct >/dev/null

    [[ -L "$HOME/.local/bin/composio" ]] \
        || fail "Composio installer should link ~/.composio/composio into ~/.local/bin"
    [[ "$(readlink "$HOME/.local/bin/composio")" == "$HOME/.composio/composio" ]] \
        || fail "Composio symlink should point at official installer binary"

    teardown_tmp
}

test_ensure_brew_prefers_native_homebrew_on_apple_silicon() {
    setup_tmp

    local arm_prefix="$TEST_TMPDIR/opt-homebrew"
    local intel_prefix="$TEST_TMPDIR/usr-local"
    mkdir -p "$arm_prefix/bin" "$intel_prefix/bin"
    export DOTFILES_HOMEBREW_ARM64_PREFIX="$arm_prefix"
    export DOTFILES_HOMEBREW_INTEL_PREFIX="$intel_prefix"
    export DOTFILES_ARCH_BIN="$TEST_TMPDIR/bin/arch"

    cat > "$arm_prefix/bin/brew" <<BASH
#!/bin/bash
if [[ "\$1" == "shellenv" ]]; then
    printf 'export PATH="%s/bin:\$PATH"\\n' "$arm_prefix"
    exit 0
fi
printf 'arm-brew <%s>\\n' "\$@" >> "$TEST_TMPDIR/log"
BASH
    cat > "$intel_prefix/bin/brew" <<BASH
#!/bin/bash
if [[ "\$1" == "shellenv" ]]; then
    printf 'export PATH="%s/bin:\$PATH"\\n' "$intel_prefix"
    exit 0
fi
printf 'intel-brew <%s>\\n' "\$@" >> "$TEST_TMPDIR/log"
BASH
    chmod +x "$arm_prefix/bin/brew" "$intel_prefix/bin/brew"
    PATH="$intel_prefix/bin:$PATH"

    cat > "$TEST_TMPDIR/bin/uname" <<'BASH'
#!/bin/bash
printf 'Darwin\n'
BASH
    cat > "$TEST_TMPDIR/bin/sysctl" <<'BASH'
#!/bin/bash
case "$*" in
  "-n hw.optional.arm64") echo "1" ;;
  *) exit 1 ;;
esac
BASH
    chmod +x "$TEST_TMPDIR/bin/uname" "$TEST_TMPDIR/bin/sysctl"
    hash -r

    # shellcheck source=/dev/null
    source install/_helpers.bash

    _ensure_brew >/dev/null

    [[ "$(command -v brew)" == "$arm_prefix/bin/brew" ]] \
        || fail "_ensure_brew should prefer native Homebrew on Apple Silicon"

    teardown_tmp
}

test_ensure_brew_installs_native_homebrew_when_only_intel_exists() {
    setup_tmp

    local arm_prefix="$TEST_TMPDIR/opt-homebrew"
    local intel_prefix="$TEST_TMPDIR/usr-local"
    mkdir -p "$intel_prefix/bin"
    export DOTFILES_HOMEBREW_ARM64_PREFIX="$arm_prefix"
    export DOTFILES_HOMEBREW_INTEL_PREFIX="$intel_prefix"
    export DOTFILES_ARCH_BIN="$TEST_TMPDIR/bin/arch"

    cat > "$intel_prefix/bin/brew" <<BASH
#!/bin/bash
if [[ "\$1" == "shellenv" ]]; then
    printf 'export PATH="%s/bin:\$PATH"\\n' "$intel_prefix"
    exit 0
fi
BASH
    chmod +x "$intel_prefix/bin/brew"
    PATH="$intel_prefix/bin:$PATH"

    cat > "$TEST_TMPDIR/bin/uname" <<'BASH'
#!/bin/bash
printf 'Darwin\n'
BASH
    cat > "$TEST_TMPDIR/bin/sysctl" <<'BASH'
#!/bin/bash
case "$*" in
  "-n hw.optional.arm64") echo "1" ;;
  *) exit 1 ;;
esac
BASH
    cat > "$TEST_TMPDIR/bin/curl" <<'BASH'
#!/bin/bash
printf '# mock Homebrew installer\n'
BASH
    cat > "$TEST_TMPDIR/bin/arch" <<'BASH'
#!/bin/bash
printf 'arch <%s>\n' "$*" >> "$TEST_TMPDIR/log"
mkdir -p "$DOTFILES_HOMEBREW_ARM64_PREFIX/bin"
cat > "$DOTFILES_HOMEBREW_ARM64_PREFIX/bin/brew" <<BREW
#!/bin/bash
if [[ "\$1" == "shellenv" ]]; then
    printf 'export PATH="%s/bin:\$PATH"\\n' "$DOTFILES_HOMEBREW_ARM64_PREFIX"
    exit 0
fi
BREW
chmod +x "$DOTFILES_HOMEBREW_ARM64_PREFIX/bin/brew"
BASH
    chmod +x "$TEST_TMPDIR/bin/uname" "$TEST_TMPDIR/bin/sysctl" "$TEST_TMPDIR/bin/curl" "$TEST_TMPDIR/bin/arch"
    hash -r

    # shellcheck source=/dev/null
    source install/_helpers.bash
    _ensure_sudo_cached() { return 0; }

    _ensure_brew >/dev/null

    grep -q 'arch <-arm64 /bin/bash -c # mock Homebrew installer>' "$TEST_TMPDIR/log" \
        || fail "_ensure_brew should install native Homebrew with arch -arm64"
    [[ "$(command -v brew)" == "$arm_prefix/bin/brew" ]] \
        || fail "_ensure_brew should switch PATH to native Homebrew after install"

    teardown_tmp
}

test_installer_detects_rosetta_reexec_need_on_apple_silicon() {
    setup_tmp

    cat > "$TEST_TMPDIR/bin/uname" <<'BASH'
#!/bin/bash
printf 'Darwin\n'
BASH
    cat > "$TEST_TMPDIR/bin/sysctl" <<'BASH'
#!/bin/bash
case "$*" in
  "-n hw.optional.arm64") echo "1" ;;
  "-n sysctl.proc_translated") echo "1" ;;
  *) exit 1 ;;
esac
BASH
    chmod +x "$TEST_TMPDIR/bin/uname" "$TEST_TMPDIR/bin/sysctl"
    hash -r

    # shellcheck source=/dev/null
    source install/_helpers.bash

    _needs_arm64_reexec \
        || fail "Apple Silicon running under Rosetta should request arm64 re-exec"
    DOTFILES_REEXEC_ARM64=1 _needs_arm64_reexec && \
        fail "installer should not repeatedly re-exec after arm64 restart"
    DOTFILES_ALLOW_ROSETTA=1 _needs_arm64_reexec && \
        fail "DOTFILES_ALLOW_ROSETTA should suppress arm64 re-exec"

    teardown_tmp
}

test_sudo_keepalive_refresh_is_noninteractive
test_sudo_keepalive_spawn_skips_installer_pid_pin
test_agent_bin_path_missing_does_not_abort_under_set_e
test_classify_agent_install_detects_brew_global_npm
test_remove_off_prefix_npm_agent_uninstalls_brew_copy
test_remove_off_prefix_npm_agent_uninstalls_hidden_brew_copy
test_apps_routes_cursor_through_dedicated_installer
test_cursor_app_installs_without_binaries_and_links_launcher
test_cursor_app_installs_without_binaries_when_fresh
test_agents_install_without_homebrew_casks
test_claude_code_forces_arm64_optional_dep_under_rosetta
test_claude_code_existing_managed_npm_uses_latest_package_install
test_codex_forces_arm64_optional_dep_on_apple_silicon
test_cursor_agent_existing_install_reruns_official_installer
test_composio_direct_links_installed_binary_into_local_bin
test_ensure_brew_prefers_native_homebrew_on_apple_silicon
test_ensure_brew_installs_native_homebrew_when_only_intel_exists
test_installer_detects_rosetta_reexec_need_on_apple_silicon

bash -n install/apps.bash install/packages.bash

echo "package installer tests passed"
