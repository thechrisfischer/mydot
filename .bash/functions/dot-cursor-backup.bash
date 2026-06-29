#!/bin/bash

_dot_cursor_config_root() {
    case "$(uname -s)" in
        Darwin) printf '%s\n' "$HOME/Library/Application Support/Cursor" ;;
        Linux)  printf '%s\n' "$HOME/.config/Cursor" ;;
        *)      return 1 ;;
    esac
}

# Function to backup Cursor settings and configurations
dot-cursor-backup() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-cursor-backup"
        echo "Backs up Cursor settings, extensions, and configurations to dotfiles repository"
        return 0
    fi

    local dotfiles_dir="${DOTFILES_DIR:-$HOME/Code/mydot}"
    local cursor_app_dir
    cursor_app_dir=$(_dot_cursor_config_root) || {
        echo "Error: Unsupported OS for Cursor backup: $(uname -s)"
        return 1
    }
    local cursor_user_dir="$cursor_app_dir/User"
    local cursor_snippets_dir="$cursor_user_dir/snippets"
    local cursor_workspace_dir="$cursor_user_dir/workspaceStorage"

    # Check if dotfiles directory exists
    if [[ ! -d "$dotfiles_dir" ]]; then
        echo "Error: Dotfiles directory not found at $dotfiles_dir"
        return 1
    fi

    # Check if Cursor is installed
    if [[ ! -d "$cursor_app_dir" ]]; then
        echo "Error: Cursor not found at $cursor_app_dir"
        echo "Please install Cursor first"
        return 1
    fi

    echo "🔄 Backing up Cursor configuration..."

    # Create ide/cursor directory in dotfiles if it doesn't exist
    local cursor_backup_dir="$dotfiles_dir/ide/cursor"
    mkdir -p "$cursor_backup_dir"

    # Backup settings.json
    if [[ -f "$cursor_user_dir/settings.json" ]]; then
        cp "$cursor_user_dir/settings.json" "$cursor_backup_dir/"
        echo "✅ Backed up settings.json"
    else
        echo "⚠️  No settings.json found"
    fi

    # Backup keybindings.json
    if [[ -f "$cursor_user_dir/keybindings.json" ]]; then
        cp "$cursor_user_dir/keybindings.json" "$cursor_backup_dir/"
        echo "✅ Backed up keybindings.json"
    else
        echo "⚠️  No keybindings.json found"
    fi

    # Backup user snippets
    if [[ -d "$cursor_snippets_dir" ]]; then
        mkdir -p "$cursor_backup_dir/snippets"
        cp -r "$cursor_snippets_dir"/* "$cursor_backup_dir/snippets/" 2>/dev/null
        echo "✅ Backed up user snippets"
    else
        echo "⚠️  No user snippets found"
    fi

    # Backup installed extensions list
    local cursor_bin=""
    if [[ -f "$dotfiles_dir/install/_helpers.bash" ]]; then
        DOTFILES_REPO_DIR="$dotfiles_dir"
        # shellcheck source=/dev/null
        source "$dotfiles_dir/install/_helpers.bash"
        cursor_bin=$(_cursor_ide_bin_path)
    fi
    if [[ -n "$cursor_bin" ]]; then
        echo "📦 Exporting installed extensions..."
        if "$cursor_bin" --list-extensions > "$cursor_backup_dir/extensions.txt" 2>/dev/null; then
            echo "✅ Backed up extensions list"
        else
            echo "⚠️  Could not export extensions list (Cursor CLI not available)"
        fi
    elif command -v cursor &> /dev/null; then
        echo "📦 Exporting installed extensions..."
        if command cursor --list-extensions > "$cursor_backup_dir/extensions.txt" 2>/dev/null; then
            echo "✅ Backed up extensions list"
        else
            echo "⚠️  Could not export extensions list (Cursor CLI not available)"
        fi
    else
        echo "⚠️  Cursor CLI not found, skipping extensions export"
    fi

    # Backup workspace settings if they exist
    if [[ -d "$cursor_workspace_dir" ]]; then
        mkdir -p "$cursor_backup_dir/workspaceStorage"
        # Only backup non-sensitive workspace files
        find "$cursor_workspace_dir" -name "*.json" -not -path "*/secrets/*" -exec cp --parents {} "$cursor_backup_dir/workspaceStorage/" \; 2>/dev/null
        echo "✅ Backed up workspace settings"
    fi

    echo "✅ Backup files created"

    # Move to repo and commit changes
    cd "$dotfiles_dir" || exit 1

    # Pull in any upstream changes
    if git pull; then
        echo "Pulled latest changes"
    else
        echo "Warning: Failed to pull latest changes"
    fi

    # Make the commit and push upstream
    if git add ide/cursor/ && git commit -m "cursor settings backed up"; then
        if git push; then
            echo "Changes pushed successfully"
        else
            echo "Warning: Failed to push changes"
        fi
    else
        echo "Warning: No changes to commit"
    fi

    echo "🎉 Cursor backup completed successfully!"
    echo "📁 Backup location: $cursor_backup_dir"
}
