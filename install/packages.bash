#!/bin/bash

function install_packages {
    local failed=0
    local have_brew=1
    local package

    # On Linux this routes to the system package manager. On macOS <15 this
    # routes to MacPorts (which still ships bottled binaries for older macOS);
    # macOS 15+ uses Homebrew. Installing brew as well on old macOS is harmless
    # and keeps casks working. Env knobs for aging machines: DOTFILES_SKIP_* in
    # install/_helpers.bash (brew/macports metadata), DOTFILES_SKIP_AWSCLI_PKG,
    # DOTFILES_SKIP_IMPECCABLE_SKILL.
    if _is_linux; then
        have_brew=0
    elif _prefer_macports; then
        _ensure_macports || return 1
        _ensure_brew || {
            have_brew=0
            _install_progress "brew unavailable — casks will be skipped"
        }
    else
        _ensure_brew || return 1
    fi

    # Pre-warm package-manager metadata once at the top so the "updating
    # metadata" lines don't interleave with per-package step rows.
    if _is_linux; then
        _apt_update_once 2>/dev/null || true
    elif _prefer_macports; then
        _macports_selfupdate_once
        [[ "$have_brew" -eq 1 ]] && _brew_update_once
    else
        _brew_update_once
    fi

    for package in python3 node; do
        _pkg_install "$package" || failed=1
    done
    _ensure_node_package_manager || failed=1
    for package in jq uv shellcheck flake8 cmatrix virtualenv pipx gh flyctl screen tmux; do
        _pkg_install "$package" || failed=1
    done
    _ensure_flake8_command || failed=1
    _install_reattach_to_user_namespace "$have_brew" || failed=1
    _install_awscli_with_fallback || failed=1
    for package in pip-search autopep8; do
        _pip_install "$package" || failed=1
    done

    _install_codex_managed_npm || failed=1
    _install_claude_code_managed_npm || failed=1
    _install_gemini_cli_managed_npm || failed=1

    # cursor-agent self-manages its install directory (~/.local/share/cursor-agent/
    # versions/<v>/) and deletes files it doesn't recognize at startup, so the
    # cursor-cli brew cask gets clobbered on first run. Use the official
    # installer instead, same pattern as flyctl.
    _install_cursor_agent_direct || failed=1

    _install_composio_direct || failed=1

    _install_impeccable_cli || failed=1
    _install_impeccable_skill || failed=1

    return "$failed"
}

function _ensure_flake8_command {
    if command -v flake8 &>/dev/null; then
        _install_step_done "flake8 command" "available at $(command -v flake8)"
        return 0
    fi
    if ! python3 -m flake8 --version &>/dev/null; then
        _install_step_fail "flake8 command" "python3 -m flake8 unavailable"
        return 1
    fi
    _ensure_npm_user_prefix
    _install_step_start "flake8 command" "creating ~/.local/bin shim..."
    cat > "$HOME/.local/bin/flake8" <<'EOF'
#!/bin/bash
exec python3 -m flake8 "$@"
EOF
    chmod +x "$HOME/.local/bin/flake8"
    _install_step_done_changed "flake8 command" "shim installed"
}

function _install_awscli_with_fallback {
    # Primary: MacPorts on macOS <15 (binary archives when available) or Homebrew on 15+.
    # macOS fallback before pipx: AWS-signed CLIV2.pkg (pre-built). Last resort: pipx → CLI v1.
    if _pkg_install awscli; then
        return 0
    fi

    if _is_macos && [[ "${DOTFILES_SKIP_AWSCLI_PKG:-0}" != 1 ]]; then
        _install_step_start "awscli" "fallback: AWS CLIV2.pkg (Apple installer; pre-built binary)..."
        if _install_awscli_pkg_macos; then
            _install_step_done_changed "awscli" "installed (AWS CLIV2.pkg)"
            return 0
        fi
        _install_progress "awscli: PKG install failed — trying pipx (CLI v1)"
    fi

    if ! command -v pipx &>/dev/null; then
        _install_step_fail "awscli" "install failed (see errors above); pipx unavailable for PyPI fallback"
        return 1
    fi

    _install_step_start "awscli" "fallback: pipx install awscli (v1; use when v2 port/build fails)..."
    local pipx_bin
    pipx_bin=$(pipx environment --value PIPX_BIN_DIR 2>/dev/null || true)
    [[ -n "$pipx_bin" ]] || pipx_bin="${HOME}/.local/bin"
    if pipx install awscli; then
        export PATH="${pipx_bin}:${PATH}"
        if [[ -x "${pipx_bin}/aws" ]] || command -v aws &>/dev/null; then
            _install_step_done_changed "awscli" "installed via pipx (AWS CLI v1)"
            _install_progress "awscli: pipx bin is ${pipx_bin} — run \`pipx ensurepath\` if aws is not on PATH in new terminals"
            return 0
        fi
    fi
    _install_step_fail "awscli" "pipx fallback failed"
    return 1
}

function _install_awscli_pkg_macos {
    # Official AWS distribution — avoids compiling the Homebrew formula on aging macOS.
    local tmp pkg
    tmp=$(mktemp -d) || return 1
    pkg="$tmp/AWSCLIV2.pkg"
    if ! curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "$pkg"; then
        rm -rf "$tmp"
        return 1
    fi
    if ! _ensure_sudo_cached; then
        rm -rf "$tmp"
        return 1
    fi
    if ! sudo /usr/sbin/installer -pkg "$pkg" -target /; then
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    export PATH="/usr/local/bin:${PATH}"
    command -v aws &>/dev/null
}

function _install_reattach_to_user_namespace {
    local have_brew=$1

    [[ "$(uname -s)" == "Darwin" ]] || return 0

    if [[ "$have_brew" -ne 1 ]]; then
        _install_step_fail "reattach-to-user-namespace" "Homebrew unavailable"
        return 1
    fi

    _brew_install reattach-to-user-namespace
}

function _ensure_node_package_manager {
    if command -v npm &> /dev/null && command -v npx &> /dev/null; then
        _install_step_done "npm/npx" "available"
    elif _prefer_macports || _is_linux; then
        _pkg_install npm || return 1
    fi

    if ! command -v npm &> /dev/null; then
        _install_step_fail "npm" "not available after node install"
        return 1
    fi

    if ! command -v npx &> /dev/null; then
        _install_step_fail "npx" "not available after node install"
        return 1
    fi

    _ensure_npm_user_prefix
}

function _npm_user_prefix {
    _dotfiles_user_prefix
}

function _ensure_npm_user_prefix {
    local prefix
    prefix=$(_npm_user_prefix)
    mkdir -p "$prefix/bin"
    case ":$PATH:" in
        *":$prefix/bin:"*) ;;
        *) export PATH="$prefix/bin:$PATH" ;;
    esac
}

# claude-code's install.cjs shells out to /usr/sbin/sysctl to detect arch;
# some user PATHs omit /usr/sbin, so ensure it's present for npm runs on macOS.
function _npm_path_for_macos {
    local incoming="$1"
    case ":$incoming:" in
        *":/usr/sbin:"*) printf '%s\n' "$incoming" ;;
        *) printf '/usr/sbin:%s\n' "$incoming" ;;
    esac
}

function _npm_global {
    local prefix path
    prefix=$(_npm_user_prefix)
    path="$PATH"
    [[ "$(uname -s)" == "Darwin" ]] && path=$(_npm_path_for_macos "$path")
    PATH="$path" NPM_CONFIG_PREFIX="$prefix" npm "$@"
}

function _remove_shadowing_impeccable {
    local shadow_path="$1"
    local managed_bin
    managed_bin="$(_npm_user_prefix)/bin/impeccable"

    [[ -z "$shadow_path" || "$shadow_path" == "$managed_bin" ]] && return 0

    if npm list -g impeccable --depth=0 &>/dev/null; then
        _install_progress "impeccable: removing shadowing npm global at $shadow_path"
        npm uninstall -g impeccable || return 1
        hash -r 2>/dev/null || true
    fi
}

function _install_cursor_agent_direct {
    local resolved
    resolved=$(_agent_bin_path cursor-agent)
    if [[ -n "$resolved" ]]; then
        if [[ "$resolved" != *"/Caskroom/"* ]]; then
            _install_step_start "cursor-agent" "refreshing via official installer..."
            if curl -fsSL https://cursor.com/install | bash &>/dev/null; then
                _install_step_done_changed "cursor-agent" "refreshed (official)"
            else
                _install_step_done "cursor-agent" "self-managed at $resolved (official refresh failed)"
            fi
            if _is_macos && [[ -d "/Applications/Cursor.app" ]]; then
                _link_cursor_cli || true
            fi
            return 0
        fi
        _install_step_start "cursor-agent" "removing incompatible brew cursor-cli cask..."
        brew uninstall --cask cursor-cli &>/dev/null || true
    else
        _install_step_start "cursor-agent" "installing via official installer..."
    fi
    if curl -fsSL https://cursor.com/install | bash &>/dev/null; then
        _install_step_done_changed "cursor-agent" "installed (official)"
        if _is_macos && [[ -d "/Applications/Cursor.app" ]]; then
            _link_cursor_cli || _install_progress "cursor CLI: app bundle link skipped"
        fi
    else
        _install_step_fail "cursor-agent" "official installer failed"
        return 1
    fi
}

function _install_composio_direct {
    local official_bin="$HOME/.composio/composio"
    local local_bin="$HOME/.local/bin/composio"

    if [[ -x "$official_bin" && ! -e "$local_bin" ]]; then
        mkdir -p "$(dirname "$local_bin")"
        ln -sfn "$official_bin" "$local_bin"
        hash -r 2>/dev/null || true
    fi

    if command -v composio &> /dev/null; then
        _install_step_done "composio" "already installed at $(command -v composio)"
        return 0
    fi
    _install_step_start "composio" "installing via official installer..."
    if curl -fsSL https://composio.dev/install | bash &>/dev/null; then
        if [[ -x "$official_bin" ]]; then
            mkdir -p "$(dirname "$local_bin")"
            ln -sfn "$official_bin" "$local_bin"
            hash -r 2>/dev/null || true
        fi
        _install_step_done_changed "composio" "installed (official)"
    else
        _install_step_fail "composio" "installer failed"
        return 1
    fi
}

function _remove_agent_cask_if_present {
    local cask="$1"
    command -v brew &>/dev/null || return 0
    if brew list --cask "$cask" &>/dev/null; then
        _install_progress "$cask: removing Homebrew cask; CLI is managed by user-prefix npm"
        brew uninstall --cask "$cask" || return 1
        hash -r 2>/dev/null || true
    fi
}

function _npm_global_package_installed {
    local package="$1"
    _npm_global list -g "$package" --depth=0 &>/dev/null
}

function _install_npm_agent_package {
    local step_name="$1"
    local package="$2"
    local command_name="$3"
    shift 3
    local install_package="$package"
    if [[ "${1:-}" == --install-package=* ]]; then
        install_package="${1#--install-package=}"
        shift
    fi
    local npm_install_args=("$@")

    if ! command -v npm &>/dev/null; then
        _install_step_fail "$step_name" "npm not available"
        return 1
    fi

    _ensure_npm_user_prefix

    if _npm_global_package_installed "$package"; then
        _install_step_start "$step_name" "updating managed npm package..."
        if _npm_global install -g "$install_package" ${npm_install_args[@]+"${npm_install_args[@]}"}; then
            hash -r 2>/dev/null || true
            _install_step_done_changed "$step_name" "updated (npm)"
            return 0
        fi
        _install_step_fail "$step_name" "npm install failed"
        return 1
    fi

    # A non-npm binary occupying the bin path (native standalone installer, or
    # a leftover from a prior tool) makes `npm install -g` fail EEXIST and used
    # to abort the whole `all` run. Clear the conflicting link so npm can own it.
    local managed_bin
    managed_bin="$(_npm_user_prefix)/bin/$command_name"
    if [[ -e "$managed_bin" || -L "$managed_bin" ]]; then
        _install_progress "$step_name: removing conflicting $managed_bin before npm install"
        rm -f "$managed_bin"
    fi

    _install_step_start "$step_name" "installing managed npm package..."
    if _npm_global install -g "$install_package" ${npm_install_args[@]+"${npm_install_args[@]}"}; then
        hash -r 2>/dev/null || true
        if command -v "$command_name" &>/dev/null; then
            _install_step_done_changed "$step_name" "installed (npm)"
        else
            _install_step_done_changed "$step_name" "installed (npm; restart shell if command is not on PATH)"
        fi
        return 0
    fi

    _install_step_fail "$step_name" "npm install failed"
    return 1
}

function _claude_code_needs_arm64_optional_dep {
    [[ "$(uname -s)" == "Darwin" ]] || return 1
    [[ "$(_sysctl_value hw.optional.arm64 || true)" == 1 ]] || return 1
    [[ "$(_sysctl_value sysctl.proc_translated || true)" == 1 ]] || return 1
}

function _codex_expected_optional_package {
    case "$(uname -s):$(uname -m)" in
        Darwin:*) _is_apple_silicon && { printf '%s\n' "@openai/codex-darwin-arm64"; return 0; }
                  printf '%s\n' "@openai/codex-darwin-x64" ;;
        Linux:x86_64) printf '%s\n' "@openai/codex-linux-x64" ;;
        Linux:arm64|Linux:aarch64) printf '%s\n' "@openai/codex-linux-arm64" ;;
        *) return 1 ;;
    esac
}

function _codex_expected_optional_package_installed {
    local package package_dir
    package=$(_codex_expected_optional_package) || return 0
    package_dir="$(_npm_user_prefix)/lib/node_modules/@openai/codex/node_modules/${package}"
    [[ -d "$package_dir" ]]
}

function _verify_codex_native_binary {
    local codex_bin
    codex_bin=$(_agent_bin_path codex)
    [[ -n "$codex_bin" ]] || return 0

    _install_step_start "codex" "checking native package..."
    if _codex_expected_optional_package_installed && "$codex_bin" --version &>/dev/null; then
        _install_step_done "codex" "native package OK"
        return 0
    fi

    _install_step_fail "codex" "installed but expected native package is not runnable"
    if _is_apple_silicon; then
        _install_progress "codex: Apple Silicon install must include --os=darwin --cpu=arm64"
    fi
    return 1
}

function _verify_claude_code_native_binary {
    local claude_bin
    claude_bin=$(_agent_bin_path claude)
    [[ -n "$claude_bin" ]] || return 0

    _install_step_start "claude-code" "checking native binary..."
    if "$claude_bin" --version &>/dev/null; then
        _install_step_done "claude-code" "native binary OK"
        return 0
    fi

    if _repair_claude_code_native_binary && "$claude_bin" --version &>/dev/null; then
        _install_step_done_changed "claude-code" "native binary repaired"
        return 0
    fi

    _install_step_fail "claude-code" "installed but native binary is not runnable"
    if _claude_code_needs_arm64_optional_dep; then
        _install_progress "claude-code: Rosetta detected; npm install must include --os=darwin --cpu=arm64"
    fi
    return 1
}

function _repair_claude_code_native_binary {
    local package_dir path
    package_dir="$(_npm_user_prefix)/lib/node_modules/@anthropic-ai/claude-code"
    [[ -f "$package_dir/install.cjs" ]] || return 1
    command -v node &>/dev/null || return 1

    path="$PATH"
    [[ "$(uname -s)" == "Darwin" ]] && path=$(_npm_path_for_macos "$path")
    (cd "$package_dir" && PATH="$path" node install.cjs) &>/dev/null
}

function _install_codex_managed_npm {
    local npm_install_args=(--include=optional)
    if _is_apple_silicon; then
        npm_install_args+=(--os=darwin --cpu=arm64)
    fi

    _remove_agent_cask_if_present codex || return 1
    _remove_off_prefix_npm_agent codex @openai/codex || return 1

    # codex has no stable self-upgrade flag (`codex --upgrade` was removed and
    # now errors out), so always manage it through npm: _install_npm_agent_package
    # updates the managed package in place when present, installs it otherwise.
    local resolved
    resolved=$(_agent_bin_path codex)
    if [[ -n "$resolved" && "$resolved" != "$(_npm_user_prefix)/bin/codex" ]]; then
        _install_progress "codex: command exists at $resolved; installing managed npm copy in $(_npm_user_prefix)"
    fi

    _install_npm_agent_package "codex" "@openai/codex" "codex" \
        --install-package="@openai/codex@latest" "${npm_install_args[@]}" || return 1
    _verify_codex_native_binary
}

function _install_claude_code_managed_npm {
    # --ignore-scripts=false defends against user ~/.npmrc setting ignore-scripts=true;
    # claude-code relies on its postinstall to set up the native binary.
    local npm_install_args=(--ignore-scripts=false --include=optional)
    if _claude_code_needs_arm64_optional_dep; then
        npm_install_args+=(--os=darwin --cpu=arm64)
    fi

    _remove_agent_cask_if_present claude-code || return 1
    _remove_agent_cask_if_present claude-code@latest || return 1
    _remove_off_prefix_npm_agent claude @anthropic-ai/claude-code || return 1

    local resolved
    resolved=$(_agent_bin_path claude)

    if [[ -n "$resolved" ]] && _claude_is_native_standalone; then
        # Native standalone installer symlinks ~/.local/bin/claude into
        # ~/.local/share/claude/versions/<v>. It self-updates in place.
        _install_step_start "claude-code" "updating native install..."
        "$resolved" update &>/dev/null || true
        if "$resolved" --version &>/dev/null; then
            _install_step_done "claude-code" "native install OK ($resolved)"
            return 0
        fi
        _install_progress "claude-code: native install not runnable — replacing with managed npm copy"
    elif [[ -n "$resolved" ]]; then
        _install_progress "claude-code: unexpected install at $resolved ($(_classify_agent_install claude @anthropic-ai/claude-code)) — replacing with managed npm copy"
    fi

    _install_npm_agent_package "claude-code" "@anthropic-ai/claude-code" "claude" \
        --install-package="@anthropic-ai/claude-code@latest" "${npm_install_args[@]}" || return 1
    _verify_claude_code_native_binary
}

function _install_gemini_cli_managed_npm {
    # Plain npm package (no native-binary postinstall), managed in the ~/.local
    # user prefix like codex. Auth is interactive: run `gemini` once and pick the
    # free Google login (generous personal-account tier) — no API key required.
    _remove_agent_cask_if_present gemini-cli || return 1
    _remove_off_prefix_npm_agent gemini @google/gemini-cli || return 1

    local resolved
    resolved=$(_agent_bin_path gemini)
    if [[ -n "$resolved" && "$resolved" != "$(_npm_user_prefix)/bin/gemini" ]]; then
        _install_progress "gemini-cli: command exists at $resolved; installing managed npm copy in $(_npm_user_prefix)"
    fi

    _install_npm_agent_package "gemini-cli" "@google/gemini-cli" "gemini" \
        --install-package="@google/gemini-cli@latest"
}

function _install_impeccable_cli {
    local existing_impeccable
    existing_impeccable=$(command -v impeccable 2>/dev/null || true)

    if ! command -v npm &> /dev/null; then
        _install_step_fail "impeccable" "npm not available"
        return 1
    fi

    _ensure_npm_user_prefix

    if _npm_global list -g impeccable --depth=0 &>/dev/null; then
        _install_step_start "impeccable" "updating npm global..."
        if _npm_global update -g impeccable || _npm_global install -g impeccable; then
            _remove_shadowing_impeccable "$existing_impeccable"
            _install_step_done_changed "impeccable" "updated (npm)"
            return 0
        else
            _install_step_fail "impeccable" "npm update failed"
            return 1
        fi
    fi

    _install_step_start "impeccable" "installing npm global..."
    if _npm_global install -g impeccable; then
        _remove_shadowing_impeccable "$existing_impeccable"
        _install_step_done_changed "impeccable" "installed (npm)"
    else
        _install_step_fail "impeccable" "npm install failed"
        return 1
    fi
}

function _install_impeccable_skill {
    if [[ "${DOTFILES_SKIP_IMPECCABLE_SKILL:-0}" == 1 ]]; then
        _install_step_done "impeccable skill" "skipped (DOTFILES_SKIP_IMPECCABLE_SKILL=1)"
        return 0
    fi

    if ! command -v npx &> /dev/null; then
        _install_step_fail "impeccable skill" "npx not available"
        return 1
    fi

    # Scope to the agents we actually use. The CLI's --all flag is shorthand
    # for "--skill '*' --agent '*' -y", which broadcasts a full ~2.2MB copy of
    # the skill into the config dir of EVERY known agent (~46 of them, e.g.
    # .augment, .roo, .zencoder, .qoder...) — ~100MB of junk dirs recreated on
    # every install. Keep --skill '*' (all skills in the repo) but pin --agent
    # to claude,codex,cursor. Override with DOTFILES_IMPECCABLE_AGENTS.
    local impeccable_agents="${DOTFILES_IMPECCABLE_AGENTS:-claude,codex,cursor}"
    _install_step_start "impeccable skill" "installing global skill for ${impeccable_agents}..."
    if npx --yes skills add pbakaus/impeccable -g --skill '*' --agent "$impeccable_agents" -y --copy &>/dev/null; then
        _install_step_done_changed "impeccable skill" "synced"
    else
        _install_step_fail "impeccable skill" "skills add failed"
        return 1
    fi
}
