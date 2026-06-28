#!/bin/bash

# GUI applications. Kept separate from packages.bash (CLI tooling) so a
# minimal install can skip GUI apps.

function install_apps {
    # Universal GUI apps only — a browser and the Cursor editor. Personal,
    # account-gated apps (Slack, Granola, Wispr Flow, Superhuman, Google Drive,
    # Tailscale) are intentionally NOT installed here; add your own in a private
    # overlay if you want them.
    if [[ "$(uname -s)" == "Linux" ]]; then
        _install_google_chrome_linux
        return
    fi

    _ensure_brew || return 1
    _brew_cask_install google-chrome
    _install_cursor_app || return 1

    if [[ "$(uname -s)" == "Darwin" ]]; then
        # shellcheck source=/dev/null
        source "$DOTFILES_REPO_DIR/install/iterm.bash"
        install_iterm
    fi
}

function _install_google_chrome_linux {
    if command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null; then
        _install_step_done "google-chrome" "already installed"
        return 0
    fi

    if ! command -v apt-get &>/dev/null; then
        _install_step_fail "google-chrome" "Linux installer currently supports apt only"
        return 1
    fi

    _apt_update_once || return 1
    _install_step_start "google-chrome" "installing Google apt repository..."
    if ! sudo apt-get install -y ca-certificates curl gnupg &>/dev/null; then
        _install_step_fail "google-chrome" "repo prerequisites failed"
        return 1
    fi
    sudo install -d -m 0755 /etc/apt/keyrings || {
        _install_step_fail "google-chrome" "keyring directory failed"
        return 1
    }
    sudo rm -f /etc/apt/keyrings/google-chrome.gpg
    if ! curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/google-chrome.gpg; then
        _install_step_fail "google-chrome" "signing key install failed"
        return 1
    fi
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null || {
            _install_step_fail "google-chrome" "apt source install failed"
            return 1
        }

    _install_step_start "google-chrome" "apt install google-chrome-stable..."
    if sudo apt-get update &>/dev/null && sudo apt-get install -y google-chrome-stable &>/dev/null; then
        _install_step_done_changed "google-chrome" "installed (apt)"
    else
        _install_step_fail "google-chrome" "apt install failed"
        return 1
    fi
}

function _install_cursor_app {
    if ! command -v brew &> /dev/null; then
        _install_step_fail "cursor" "brew not available"
        return 1
    fi
    _brew_update_once

    local action="install" verb="installing" result="installed" status=0
    if brew list --cask cursor &> /dev/null; then
        local outdated
        if ! outdated=$(brew outdated --cask --greedy --quiet cursor 2>/dev/null); then
            outdated=$(brew outdated --cask --quiet cursor 2>/dev/null || true)
        fi
        if [[ -z "$outdated" ]]; then
            _link_cursor_launcher || { _install_step_fail "cursor" "current app, but launcher link failed"; return 1; }
            _install_step_done "cursor" "already current (cask; launcher linked)"
            return 0
        fi
        action="upgrade" verb="upgrading" result="upgraded"
    fi

    _install_step_start "cursor" "$verb Homebrew cask without binary links..."
    local install_out
    if [[ "$action" == "upgrade" ]]; then
        if install_out=$(brew upgrade --cask --greedy --no-binaries cursor 2>&1); then
            status=0
        elif install_out=$(brew upgrade --cask --no-binaries cursor 2>&1); then
            status=0
        else
            status=$?
        fi
    else
        if install_out=$(brew install --cask --no-binaries cursor 2>&1); then
            status=0
        else
            status=$?
        fi
        # App exists outside brew's Caskroom (manual install, wiped Caskroom, etc.)
        if [[ $status -ne 0 ]] && grep -q "It seems there is already an App at" <<<"$install_out"; then
            if install_out=$(brew install --cask --no-binaries --adopt cursor 2>&1); then
                status=0
                result="adopted"
            else
                status=$?
            fi
        fi
    fi
    if [[ "$status" -eq 0 ]]; then
        _link_cursor_launcher || { _install_step_fail "cursor" "$result app, but launcher link failed"; return 1; }
        _install_step_done_changed "cursor" "$result (cask; linked launcher manually)"
        return 0
    fi
    if [[ -n "$install_out" ]]; then
        printf '%s\n' "$install_out" > "$(_install_out_target)"
    fi
    _install_step_fail "cursor" "cask $action failed"
    return 1
}

function _link_cursor_launcher {
    _link_cursor_cli
}
