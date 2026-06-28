#!/bin/bash

function install_vim {
    local backup_dir
    backup_dir="/tmp/vim_backup_$(timestamp)"
    mkdir -p "$backup_dir"

    if [[ -d ~/.vim ]]; then
        cp -a ~/.vim* "$backup_dir/" 2>/dev/null || true
    fi

    _install_step_start "vim files" "copying config..."
    if [[ -d "$DOTFILES_REPO_DIR/.vim" ]]; then
        cp -a "$DOTFILES_REPO_DIR/.vim"* ~/
        _install_step_done "vim files" "installed (backup: $backup_dir)"
    else
        _install_step_done "vim files" "no vim files in repo, skipped"
    fi

    local plug_path="$HOME/.vim/autoload/plug.vim"
    mkdir -p "$(dirname "$plug_path")"
    if [[ -f "$plug_path" ]]; then
        _install_step_start "vim-plug" "checking remote copy..."
        local before_mtime after_mtime
        before_mtime=$(stat -f %m "$plug_path" 2>/dev/null || stat -c %Y "$plug_path" 2>/dev/null)
        if curl -fsSL -z "$plug_path" -o "$plug_path" \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
            after_mtime=$(stat -f %m "$plug_path" 2>/dev/null || stat -c %Y "$plug_path" 2>/dev/null)
            if [[ "$before_mtime" != "$after_mtime" ]]; then
                _install_step_done_changed "vim-plug" "updated"
            else
                _install_step_done "vim-plug" "already current"
            fi
        else
            _install_step_fail "vim-plug" "download failed"
            return 1
        fi
    else
        _install_step_start "vim-plug" "installing..."
        if curl -fsSL -o "$plug_path" \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim; then
            _install_step_done_changed "vim-plug" "installed"
        else
            _install_step_fail "vim-plug" "download failed"
            return 1
        fi
    fi
}
