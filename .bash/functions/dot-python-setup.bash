#!/bin/bash

dot-python-setup() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-python-setup"
        echo "Creates a Python virtual environment and requirements.txt file"
        return 0
    fi

    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 not found"
        return 1
    fi

    # Create virtual environment
    if python3 -m venv ./venv; then
        echo "Virtual environment created successfully"
        touch requirements.txt
        echo "requirements.txt created"
        echo "To activate: source venv/bin/activate"
    else
        echo "Error: Failed to create virtual environment"
        return 1
    fi
}
