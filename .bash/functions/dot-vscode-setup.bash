#!/bin/bash

_dot_vscode_code_path() {
    case "$(uname -s)" in
        Darwin)
            if [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
                printf '%s\n' "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
                return 0
            fi
            ;;
        Linux)
            if command -v code &>/dev/null; then
                command -v code
                return 0
            fi
            for _candidate in /usr/bin/code /usr/local/bin/code /snap/bin/code; do
                if [[ -x "$_candidate" ]]; then
                    printf '%s\n' "$_candidate"
                    return 0
                fi
            done
            ;;
    esac
    return 1
}

dot-vscode-setup() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-vscode-setup"
        echo "Creates a symlink for VS Code in ~/bin/vscode"
        return 0
    fi

    local vscode_path
    local target_dir="$HOME/bin"

    if ! vscode_path=$(_dot_vscode_code_path); then
        echo "Error: VS Code CLI not found"
        return 1
    fi

    # Create bin directory if it doesn't exist
    mkdir -p "$target_dir"

    # Create symlink
    if ln -sf "$vscode_path" "$target_dir/vscode"; then
        echo "VS Code symlink created at $target_dir/vscode"
    else
        echo "Error: Failed to create symlink"
        return 1
    fi
}
