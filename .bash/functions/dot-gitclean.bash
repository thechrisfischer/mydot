#!/bin/bash

# Function to cleanup old branches in git
dot-gitclean() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-gitclean"
        echo "Deletes merged branches and prunes remote branches"
        return 0
    fi

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    # Get the main branch name (could be main or master)
    local main_branch
    main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [[ -z "$main_branch" ]]; then
        main_branch="master"  # fallback
    fi

    # Find merged branches
    local merged_branches
    merged_branches=$(git branch --merged | grep -v "$main_branch" | sed 's/^[[:space:]]*//')

    if [[ -z "$merged_branches" ]]; then
        echo "No merged branches to clean up"
    else
        echo "Branches to delete:"
        echo "$merged_branches"
        read -rp "Delete these merged branches? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "$merged_branches" | xargs -I {} git branch -d {}
        else
            echo "Aborted."
        fi
    fi

    # Prune remote branches
    echo "Pruning remote branches..."
    git remote prune origin
}
