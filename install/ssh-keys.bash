#!/bin/bash
# Optional SSH bootstrap: install ~/.ssh/config and register a GitHub key via gh(1).
#
# Fresh machines should use `gh auth login` + `gh repo clone` first. Run
# `./install.sh ssh-keys` when you also want a GitHub SSH key for git@ remotes.

function _ssh_keys_have_identity {
    [[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]]
}

function _ssh_keys_install_config {
    local src="$DOTFILES_REPO_DIR/.ssh/config/config"
    if [[ ! -f "$src" ]]; then
        _install_progress "ssh config: no template at $src — skipping"
        return 0
    fi

    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cp -a "$src" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    _install_step_done_changed "ssh config" "$HOME/.ssh/config"
}

function _ssh_keys_try_github_register {
    if _ssh_keys_have_identity; then
        _install_step_done "github key" "identity key already present"
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        _install_progress "github key: gh not found — run \`./install.sh packages\` first"
        return 0
    fi

    if ! gh auth status >/dev/null 2>&1; then
        _install_progress "github key: run \`gh auth login\` first, then re-run \`./install.sh ssh-keys\`"
        return 0
    fi

    local email=""
    if [[ -f "$HOME/.bash/config.bash" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.bash/config.bash"
        email="${DOTFILES_GIT_EMAIL:-}"
    fi

    _install_step_start "github key" "generating ed25519 + gh ssh-key add"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" \
        -C "${email:-$(whoami)@$(hostname -s)}" <<< y >/dev/null 2>&1
    chmod 600 "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"

    local title
    title="$(hostname -s)-$(date +%Y%m%d)"
    if gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$title" >/dev/null 2>&1; then
        _install_step_done_changed "github key" "registered $title on GitHub"
    else
        _install_step_fail "github key" "gh ssh-key add failed — check \`gh auth status\` (needs admin:public_key scope)"
        return 1
    fi
}

function _ssh_keys_verify_github {
    if ! _ssh_keys_have_identity; then
        return 0
    fi

    _install_step_start "github verify" "ssh -T git@github.com"
    local output
    if output=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1); then
        _install_step_done "github verify" "$output"
    elif grep -qi "successfully authenticated" <<<"$output"; then
        _install_step_done "github verify" "authenticated"
    else
        _install_step_fail "github verify" "$output"
        return 1
    fi
}

function install_ssh_keys {
    _install_progress "ssh-keys: installing config and bootstrapping GitHub SSH access"
    _ssh_keys_install_config || return 1
    _ssh_keys_try_github_register || return 1
    _ssh_keys_verify_github || return 1
    _install_step_done_changed "ssh-keys" "ready"
}
