#!/bin/bash

# Function to backup local bash config and move to repo
bash-backup() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: bash-backup"
        echo "Backs up bash config files to dotfiles repository"
        return 0
    fi

    local dotfiles_dir="${DOTFILES_DIR:-$HOME/Code/dotfiles}"

    # Check if dotfiles directory exists
    if [[ ! -d "$dotfiles_dir" ]]; then
        echo "Error: Dotfiles directory not found at $dotfiles_dir"
        return 1
    fi

    # move local files to dotfiles repo
    if cp -va ~/.bash/* "$dotfiles_dir/.bash/"; then
        echo "Bash files backed up successfully"
    else
        echo "Error: Failed to backup bash files"
        return 1
    fi

    # move to repo and die if repo does not exist
    cd "$dotfiles_dir" || exit 1

    # pull in any upstream changes
    if git pull; then
        echo "Pulled latest changes"
    else
        echo "Warning: Failed to pull latest changes"
    fi

    # make the commit and push upstream
    if git commit -am "bash settings backed up"; then
        if git push; then
            echo "Changes pushed successfully"
        else
            echo "Warning: Failed to push changes"
        fi
    else
        echo "Warning: No changes to commit"
    fi
}
