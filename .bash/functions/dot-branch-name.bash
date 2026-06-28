#!/bin/bash

# Create a function to recommend branch names
# TODO change timestamp to ticket
dot-branch-name() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-branch-name <feature_name>"
        echo "Generates a recommended branch name with timestamp"
        echo "Example: dot-branch-name add_user_auth"
        return 0
    fi

    # Set a local variable using the first passed argument as feature name
    local original_IFS="$IFS"
    IFS="_"
    local feature="$*"
    # Create a well formatted timestamp local to this function
    local timestamp
    timestamp=$(date +"%m%d")
    # Return the recommended branch name with timestamp
    echo "${DOTFILES_BRANCH_PREFIX:-$(whoami)}/${timestamp}/${feature}"
    IFS=$original_IFS
}
