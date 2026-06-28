#!/bin/bash

activate-venv() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: activate-venv"
        echo "Activates the first virtual environment found in current directory"
        return 0
    fi

    local venv_path
    venv_path=$(find ./ -type f -name activate 2>/dev/null | head -n1)

    if [[ -z "$venv_path" ]]; then
        echo "Error: No virtual environment found in current directory"
        return 1
    fi

    if [[ ! -f "$venv_path" ]]; then
        echo "Error: Virtual environment activate script not found"
        return 1
    fi

    echo "Activating virtual environment: $venv_path"
    # shellcheck source=/dev/null
    source "$venv_path"
}
