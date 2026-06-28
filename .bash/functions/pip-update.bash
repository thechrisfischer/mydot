#!/bin/bash

pip-update() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: pip-update"
        echo "Updates all outdated pip packages"
        return 0
    fi

    # Update all packages installed with pip
    local outdated_packages
    outdated_packages=$(pip list --format=columns --outdated 2>/dev/null | awk '!/Package|---/{ print $1}')

    if [[ -z "$outdated_packages" ]]; then
        echo "No outdated packages found"
        return 0
    fi

    echo "Updating packages: $outdated_packages"
    pip install -U "$outdated_packages"
}
