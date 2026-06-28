#!/bin/bash

function _cursor_settings_dir {
    case "$(uname -s)" in
        Darwin) printf '%s\n' "$HOME/Library/Application Support/Cursor/User" ;;
        Linux)  printf '%s\n' "$HOME/.config/Cursor/User" ;;
        *)      return 1 ;;
    esac
}

function _cursor_app_available {
    case "$(uname -s)" in
        Darwin) [[ -d "/Applications/Cursor.app" ]] ;;
        Linux) [[ -n "$(_cursor_ide_bin_path)" || -n "$(_agent_bin_path cursor-agent)" ]] ;;
        *) return 1 ;;
    esac
}

function _read_cursor_extension_allowlist {
    local list_file="$1"
    local extension

    while IFS= read -r extension; do
        [[ -n "$extension" && ! "$extension" =~ ^[[:space:]]*# ]] || continue
        extension="${extension%%#*}"
        extension="${extension#"${extension%%[![:space:]]*}"}"
        extension="${extension%"${extension##*[![:space:]]}"}"
        [[ -n "$extension" ]] && printf '%s\n' "$extension"
    done < "$list_file"
}

function _sync_cursor_extensions_from_list {
    local list_file="$1"
    local cursor_bin installed_extensions extension

    [[ -f "$list_file" ]] || return 0

    cursor_bin=$(_cursor_ide_bin_path)
    if [[ -z "$cursor_bin" ]]; then
        echo "⚠️  Cursor CLI not found — install Cursor.app (macOS) or cursor CLI, then re-run"
        return 0
    fi

    installed_extensions=$("$cursor_bin" --list-extensions 2>/dev/null || true)

    local allowlist_tmp
    allowlist_tmp=$(mktemp)
    _read_cursor_extension_allowlist "$list_file" > "$allowlist_tmp"

    if [[ "${DOTFILES_CURSOR_SKIP_EXTENSION_PRUNE:-0}" != 1 ]]; then
        while IFS= read -r extension; do
            [[ -n "$extension" ]] || continue
            if ! grep -Fqx "$extension" "$allowlist_tmp"; then
                _install_progress "Cursor extension $extension: removing (not in extensions.txt)"
                "$cursor_bin" --uninstall-extension "$extension" 2>/dev/null \
                    || echo "Failed to uninstall: $extension"
            fi
        done <<< "$installed_extensions"
    fi

    while IFS= read -r extension; do
        [[ -n "$extension" ]] || continue
        if printf '%s\n' "$installed_extensions" | grep -ixq "$extension"; then
            _install_progress "Cursor extension $extension: already installed"
        else
            _install_progress "Cursor extension $extension: installing"
            "$cursor_bin" --install-extension "$extension" 2>/dev/null \
                || echo "Failed to install: $extension"
        fi
    done < "$allowlist_tmp"

    rm -f "$allowlist_tmp"

    echo "✅ Cursor extensions synced from extensions.txt"
}

function install_cursor {
    echo "Installing Cursor configuration..."

    if ! command -v jq &>/dev/null; then
        echo "❌ jq not found — run './install.sh packages' first"
        return 1
    fi

    if ! _cursor_app_available; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
            echo "⚠️  Cursor.app not found in /Applications"
            echo "Please install Cursor first (./install.sh apps), then run this again"
            return 1
        fi
        echo "⚠️  Cursor CLI/agent not found; installing settings only"
    fi

    local cursor_settings_dir
    cursor_settings_dir=$(_cursor_settings_dir) || {
        echo "❌ Unsupported OS for Cursor configuration: $(uname -s)"
        return 1
    }
    local script_dir="$DOTFILES_REPO_DIR/ide/cursor"

    local backup_timestamp backup_dir
    backup_timestamp=$(timestamp)
    backup_dir="/tmp/cursor_backup_$backup_timestamp"
    mkdir -p "$backup_dir"

    if [[ -f "$cursor_settings_dir/settings.json" ]]; then
        cp "$cursor_settings_dir/settings.json" "$backup_dir/"
        echo "Backed up existing Cursor settings to $backup_dir"
    fi

    mkdir -p "$cursor_settings_dir"

    local settings_file="$cursor_settings_dir/settings.json"
    local source_settings="$script_dir/settings.json"
    if [[ ! -f "$source_settings" ]]; then
        echo "❌ Cursor settings file not found at $source_settings"
        return 1
    fi

    if [[ -f "$settings_file" ]]; then
        local tmp_settings
        tmp_settings=$(mktemp)
        if jq -s '.[0] * .[1]' "$settings_file" "$source_settings" > "$tmp_settings"; then
            mv "$tmp_settings" "$settings_file"
            echo "✅ Merged Cursor settings"
        else
            rm -f "$tmp_settings"
            echo "❌ Failed to merge Cursor settings"
            return 1
        fi
    else
        cp "$source_settings" "$settings_file"
        echo "✅ Installed Cursor settings"
    fi

    if [[ -f "$script_dir/keybindings.json" ]]; then
        cp "$script_dir/keybindings.json" "$cursor_settings_dir/"
        echo "✅ Installed Cursor keybindings"
    fi

    if [[ -d "$script_dir/snippets" ]]; then
        mkdir -p "$cursor_settings_dir/snippets"
        cp -r "$script_dir/snippets"/* "$cursor_settings_dir/snippets/"
        echo "✅ Installed user snippets"
    fi

    if [[ -f "$script_dir/extensions.txt" ]]; then
        _install_progress "Cursor extensions: syncing from extensions.txt"
        _sync_cursor_extensions_from_list "$script_dir/extensions.txt"
    fi

    if _is_macos && [[ -d "/Applications/Cursor.app" ]] && [[ "${DOTFILES_CURSOR_SKIP_CLI_LINK:-0}" != 1 ]]; then
        _link_cursor_cli && echo "✅ Linked cursor CLI to Cursor.app" || true
    fi

    echo "Backup location: $backup_dir"
    echo "Cursor configuration completed!"
    echo "⚠️  Please restart Cursor for changes to take effect"
}
