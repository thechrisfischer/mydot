#!/bin/bash

function _canonical_shell_path {
    local path="$1"

    if [[ -z "$path" ]]; then
        return 1
    fi

    if command -v realpath &> /dev/null; then
        realpath "$path" 2>/dev/null && return 0
    fi

    if command -v readlink &> /dev/null; then
        readlink -f "$path" 2>/dev/null && return 0
    fi

    printf '%s\n' "$path"
}

function configure_shell {
    echo "Configuring shell settings..."

    # Check current shell
    local current_shell
    current_shell=$SHELL
    echo "Current shell: $current_shell"

    local bash_path current_shell_resolved bash_path_resolved
    bash_path=$(command -v bash || true)
    if [[ -z "$bash_path" ]]; then
        echo "❌ bash not found on PATH"
        return 1
    fi
    current_shell_resolved=$(_canonical_shell_path "$current_shell" || printf '%s\n' "$current_shell")
    bash_path_resolved=$(_canonical_shell_path "$bash_path" || printf '%s\n' "$bash_path")

    # Set bash as default shell
    if [[ "$current_shell_resolved" != "$bash_path_resolved" ]]; then
        echo "Setting bash as default shell..."
        local target_user="${USER:-$(id -un)}"
        if [[ -r /etc/shells ]] && ! grep -qx "$bash_path" /etc/shells; then
            echo "⚠️  $bash_path is not listed in /etc/shells; skipping chsh"
        # Prefer sudo chsh when credentials are already cached (e.g. install.sh all
        # runs _ensure_sudo_cached first). Plain chsh prompts again on macOS via
        # OpenDirectory — same password, feels like "sudo twice".
        elif declare -f _ensure_sudo_cached &>/dev/null \
             && _ensure_sudo_cached \
             && sudo -n chsh -s "$bash_path" "$target_user"; then
            echo "✅ Bash set as default shell"
            echo "⚠️  Please restart your terminal for changes to take effect"
        elif [[ "${_DOTFILES_SECTION_CAPTURE:-0}" == 1 && ! ( -t 0 && -e /dev/tty && -w /dev/tty ) ]]; then
            echo "⚠️  No terminal available for chsh prompt; skipping chsh"
        else
            if [[ -t 0 && -e /dev/tty && -w /dev/tty ]]; then
                chsh -s "$bash_path" < /dev/tty > /dev/tty 2>&1
            else
                chsh -s "$bash_path"
            fi
            echo "✅ Bash set as default shell"
            echo "⚠️  Please restart your terminal for changes to take effect"
        fi
    else
        echo "✅ Bash is already your default shell"
    fi

    # Create .zshrc for zsh compatibility (if needed)
    if [[ -f ~/.zshrc ]]; then
        echo "Backing up existing .zshrc..."
        cp ~/.zshrc ~/.zshrc.backup."$(timestamp)"
    fi

    # Install .zshrc from repo
    if [[ -f "$DOTFILES_REPO_DIR/.zshrc" ]]; then
        cp "$DOTFILES_REPO_DIR/.zshrc" ~/
        echo "✅ Installed .zshrc with bash compatibility"
    fi

    # Configure terminal colors (macOS only)
    local os_type
    os_type=$(uname -s)
    if [[ "$os_type" == "Darwin" ]]; then
        echo "Configuring Terminal.app colors..."
        if [[ -f "$DOTFILES_REPO_DIR/system/macos/terminal-colors.sh" ]]; then
            # shellcheck source=/dev/null
            source "$DOTFILES_REPO_DIR/system/macos/terminal-colors.sh"
        else
            echo "⚠️  Terminal colors script not found"
        fi
    else
        echo "ℹ️  Terminal color configuration skipped (macOS only)"
    fi

    echo "Shell configuration completed!"
}
