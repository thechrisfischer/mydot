#!/bin/bash

function _install_ssh_config {
    local src="$DOTFILES_REPO_DIR/system/ssh/config"
    local dest_dir="$HOME/.ssh/config.d"
    local dest_file="$dest_dir/dotfiles"
    local main_config="$HOME/.ssh/config"
    local include_line="Include $dest_dir/dotfiles"

    if [[ ! -f "$src" ]]; then
        _install_step_fail "ssh" "config template missing: $src"
        return 1
    fi

    mkdir -p "$dest_dir"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cp -a "$src" "$dest_file"
    chmod 600 "$dest_file"

    if [[ ! -f "$main_config" ]]; then
        printf '%s\n' "$include_line" > "$main_config"
        chmod 600 "$main_config"
    elif ! grep -Fq "$include_line" "$main_config" 2>/dev/null; then
        {
            echo "$include_line"
            cat "$main_config"
        } > "${main_config}.tmp"
        mv "${main_config}.tmp" "$main_config"
        chmod 600 "$main_config"
    fi

    _install_progress "ssh config: installed $dest_file"
    return 0
}

function _install_ssh_add_keychain {
    local key="$HOME/.ssh/id_rsa"
    [[ -f "$key" ]] || return 0
    command -v ssh-add &>/dev/null || return 0

    if [[ "$(uname -s)" == "Darwin" ]]; then
        ssh-add --apple-use-keychain "$key" 2>/dev/null || ssh-add "$key" 2>/dev/null || true
    else
        ssh-add "$key" 2>/dev/null || true
    fi
}

function install_ssh {
    echo "Installing SSH config..."

    _install_ssh_config || return 1
    _install_ssh_add_keychain

    _install_step_done_changed "ssh" "config installed"
    if [[ ! -f "$HOME/.ssh/id_rsa" && ! -f "$HOME/.ssh/id_ed25519" ]]; then
        echo "ℹ️  No SSH key found — generate one (ssh-keygen) and add it to GitHub for git@ remotes"
    fi
    return 0
}
