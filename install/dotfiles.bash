#!/bin/bash

function install_dotfiles {
    echo "Installing dotfiles..."

    # Create backup timestamp
    local backup_timestamp
    backup_timestamp=$(timestamp)
    local temp_backup="/tmp/dotfiles_backup_$backup_timestamp"

    # Create temporary backup directory
    mkdir -p "$temp_backup"

    # Backup existing dotfiles to temp location
    echo "Backing up existing dotfiles to $temp_backup"

    # Backup .bash directory
    if [[ -d ~/.bash ]]; then
        cp -a ~/.bash "$temp_backup/"
        echo "Backed up ~/.bash"
    fi

    # Backup .vim directory
    if [[ -d ~/.vim ]]; then
        cp -a ~/.vim "$temp_backup/"
        echo "Backed up ~/.vim"
    fi

    # Backup .aws directory
    if [[ -d ~/.aws ]]; then
        cp -a ~/.aws "$temp_backup/"
        echo "Backed up ~/.aws"
    fi

    # Backup individual dotfiles
    for file in ~/.bash_profile ~/.bashrc ~/.gitconfig ~/.gitignore_global ~/.profile ~/.screenrc ~/.tmux.conf ~/.vimrc; do
        if [[ -e "$file" ]]; then
            cp -a "$file" "$temp_backup/"
            echo "Backed up $file"
        fi
    done

    # Install all .folders from repo
    echo "Installing .folders from repo..."

    # Install .bash directory
    if [[ -d "$DOTFILES_REPO_DIR/.bash" ]]; then
        cp -va "$DOTFILES_REPO_DIR/.bash" ~/
        echo "Installed .bash"
    fi

    # Install .vim directory
    if [[ -d "$DOTFILES_REPO_DIR/.vim" ]]; then
        cp -va "$DOTFILES_REPO_DIR/.vim" ~/
        echo "Installed .vim"
    fi

    # Seed ~/.bash/config.bash from the example on first install (it is
    # gitignored, so a fresh clone ships only the .example template).
    if [[ ! -f "$HOME/.bash/config.bash" && -f "$HOME/.bash/config.bash.example" ]]; then
        cp -a "$HOME/.bash/config.bash.example" "$HOME/.bash/config.bash"
        echo "Seeded ~/.bash/config.bash from config.bash.example — set DOTFILES_GIT_NAME/EMAIL there"
    fi

    # Install individual dotfiles
    echo "Installing individual dotfiles..."
    for file in .bash_profile .bashrc .gitconfig .gitignore_global .profile .screenrc .tmux.conf .vimrc .zshrc; do
        if [[ -e "$DOTFILES_REPO_DIR/$file" ]]; then
            cp -va "$DOTFILES_REPO_DIR/$file" ~/
            echo "Installed $file"
        fi
    done

    # Write git identity into ~/.gitconfig from the config vars (the committed
    # .gitconfig ships no [user] block). Non-destructive: only sets values that
    # are provided.
    # shellcheck source=/dev/null
    [[ -f "$HOME/.bash/config.bash" ]] && source "$HOME/.bash/config.bash"
    if [[ -n "${DOTFILES_GIT_NAME:-}" ]]; then
        git config --global user.name "$DOTFILES_GIT_NAME"
    fi
    if [[ -n "${DOTFILES_GIT_EMAIL:-}" ]]; then
        git config --global user.email "$DOTFILES_GIT_EMAIL"
    fi
    if [[ -z "${DOTFILES_GIT_NAME:-}" || -z "${DOTFILES_GIT_EMAIL:-}" ]]; then
        echo "ℹ️  Set DOTFILES_GIT_NAME / DOTFILES_GIT_EMAIL in ~/.bash/config.bash, then re-run \`./install.sh dotfiles\`"
    fi

    if [[ -f "$DOTFILES_REPO_DIR/.ssh/config/config" ]]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        cp -a "$DOTFILES_REPO_DIR/.ssh/config/config" "$HOME/.ssh/config"
        chmod 600 "$HOME/.ssh/config"
        echo "Installed ~/.ssh/config"
    fi

    if [[ "$(uname -s)" == "Darwin" && -f "$DOTFILES_REPO_DIR/install/iterm.bash" ]]; then
        # shellcheck source=install/iterm.bash
        source "$DOTFILES_REPO_DIR/install/iterm.bash"
        _install_iterm_shell_integration
    fi

    echo ""
    echo "Installation completed!"
    echo "If anything went wrong, your old files are in: $temp_backup"

    # Source the newly installed dotfiles so subsequent installations benefit from them
    echo "Sourcing newly installed dotfiles..."
    if [[ -f "$HOME/.bash/prefs.bash" ]]; then
        source "$HOME/.bash/prefs.bash"
        echo "✅ Sourced .bash/prefs.bash"
    fi
    if [[ -f "$HOME/.bash/functions/_loader.bash" ]]; then
        source "$HOME/.bash/functions/_loader.bash"
        echo "✅ Sourced .bash/functions/_loader.bash"
    fi
    echo "Dotfiles sourced successfully!"

    # Ensure a modern `screen` is installed on macOS (the system version is ancient).
    # Checks brew + MacPorts prefixes; system /usr/bin/screen doesn't count.
    if [[ "$(uname -s)" == "Darwin" ]]; then
        local _modern_screen=""
        for _candidate in /opt/homebrew/bin/screen /usr/local/bin/screen /opt/local/bin/screen; do
            [[ -x "$_candidate" ]] && _modern_screen="$_candidate" && break
        done
        if [[ -z "$_modern_screen" ]]; then
            echo "Installing modern screen..."
            _pkg_install screen
        fi
    fi

    # Configure shell and terminal colors
    source "$DOTFILES_REPO_DIR/install/shell.bash"
    configure_shell
}
