#!/bin/bash

# Function to add back search functionality to pip
function pip() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: pip [options]"
        echo "Enhanced pip with search functionality restored"
        echo "Use 'pip search <package>' to search packages"
        return 0
    fi

    if [[ $1 == "search" ]]; then
        command pip_search "${@:2}" | more
    else
        command pip "$@"
    fi
}
