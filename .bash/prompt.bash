#!/usr/bin/env bash

# Color definitions - using simpler format
export COLOR_NC='\[\e[0m\]'
export COLOR_WHITE='\[\e[1;37m\]'
export COLOR_BLACK='\[\e[0;30m\]'
export COLOR_BLUE='\[\e[0;34m\]'
export COLOR_LIGHT_BLUE='\[\e[1;34m\]'
export COLOR_GREEN='\[\e[0;32m\]'
export COLOR_LIGHT_GREEN='\[\e[1;32m\]'
export COLOR_CYAN='\[\e[0;36m\]'
export COLOR_LIGHT_CYAN='\[\e[1;36m\]'
export COLOR_RED='\[\e[0;31m\]'
export COLOR_LIGHT_RED='\[\e[1;31m\]'
export COLOR_PURPLE='\[\e[0;35m\]'
export COLOR_LIGHT_PURPLE='\[\e[1;35m\]'
export COLOR_BROWN='\[\e[0;33m\]'
export COLOR_YELLOW='\[\e[1;33m\]'
export COLOR_GRAY='\[\e[0;30m\]'
export COLOR_LIGHT_GRAY='\[\e[0;37m\]'

# Simple git status function with error handling
_git_status() {
    # Check if we're in a git repo - return empty string if not (don't return error code)
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        return 0  # Not an error, just not a git repo
    fi

    # Get branch name safely
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    
    # If we couldn't get branch name, return empty (not an error for prompt purposes)
    if [[ -z "$branch" ]]; then
        return 0
    fi

    # Check if working directory is dirty.
    # git diff-index uses cached stat info; refresh so we see edits without running git diff.
    git update-index -q --refresh 2>/dev/null
    local status
    if git diff-index --quiet HEAD -- 2>/dev/null; then
        status="${COLOR_GREEN}✓${COLOR_NC}"
    else
        status="${COLOR_RED}✗${COLOR_NC}"
    fi

    echo "[${COLOR_WHITE}±${COLOR_NC}][${COLOR_CYAN}${branch}${COLOR_NC}${status}]"
    return 0  # Always return success - git status display shouldn't affect prompt error state
}

# Git branch only — no dirty check (used when DOTFILES_FAST_PROMPT=1)
_git_branch_only() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        return 0
    fi
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    [[ -z "$branch" ]] && return 0
    echo "[${COLOR_WHITE}±${COLOR_NC}][${COLOR_CYAN}${branch}${COLOR_NC}]"
    return 0
}

# Simple SCM detection
_scm_info() {
    if [[ "${DOTFILES_FAST_PROMPT:-0}" == "1" ]]; then
        _git_branch_only
        return 0
    fi
    # Check for git first (most common)
    if git rev-parse --git-dir >/dev/null 2>&1; then
        _git_status
        return 0
    fi

    # Could add other SCM systems here if needed
    # For now, return empty string if no SCM found
    # Return 0 (success) since not finding SCM is not an error
    return 0
}

# Virtual environment display
_venv_info() {
    if [[ -n "$VIRTUAL_ENV" ]]; then
        local venv_name
        venv_name=$(basename "$VIRTUAL_ENV")
        echo "[${COLOR_PURPLE}🐍${COLOR_NC}${COLOR_LIGHT_PURPLE}${venv_name}${COLOR_NC}]"
    fi
}

# Main prompt function - much simpler and more robust
_prompt() {
    # Capture exit code FIRST before any other commands
    # This must be the very first line to preserve the exit code of the last command
    local exit_code=$?
    
    # Now we can safely run helper functions without affecting the captured exit code
    local scm_info
    local venv_info

    # Get SCM info safely - suppress errors to prevent affecting exit code
    scm_info=$(_scm_info 2>/dev/null) || scm_info=""

    # Get virtual environment info - suppress errors to prevent affecting exit code
    venv_info=$(_venv_info 2>/dev/null) || venv_info=""

    # Build prompt based on the captured exit code (not current $?)
    # Use the local variable, not $? directly, to ensure we're using the original exit code
    if [[ $exit_code -eq 0 ]]; then
        PS1="[${COLOR_YELLOW}\h${COLOR_NC}]${scm_info}${venv_info}[${COLOR_CYAN}\W${COLOR_NC}]
💀::> "
    else
        PS1="[${COLOR_YELLOW}\h${COLOR_NC}]${scm_info}${venv_info}[${COLOR_CYAN}\W${COLOR_NC}]
💀::${COLOR_RED}>${COLOR_NC} "
    fi
    
    # Explicitly return success to prevent prompt function from affecting future commands
    return 0
}

# Update screen window title with git branch + cwd (no-op outside screen)
# Uses `screen -X title` which bypasses defdynamictitle, so our title persists
# even when programs like Claude Code try to override it via escape sequences
_screen_status() {
    [[ -z "$STY" ]] && return 0
    local info
    if [[ "${DOTFILES_FAST_PROMPT:-0}" == "1" ]]; then
        info="${PWD/#$HOME/\~}"
    else
        local branch
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
        info=""
        [[ -n "$branch" ]] && info="git:${branch} "
        info+="${PWD/#$HOME/\~}"
    fi
    screen -X title "$info"
}

# Set up prompt command
PROMPT_COMMAND="_prompt; _screen_status"

# Secondary prompts
PS2=">> "
PS3=">? "
PS4="++ "
