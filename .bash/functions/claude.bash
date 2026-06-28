#!/bin/bash
# Wrapper for Claude Code with convenience subcommands
#   claude yolo  — runs claude --dangerously-skip-permissions
#   claude       — passes --chrome by default (Claude in Chrome integration)
#   claude --no-chrome — skip Claude in Chrome for this session
#   DOTFILES_CLAUDE_SKIP_CHROME=1 — disable default --chrome

_dot_claude_command() {
    local claude_bin
    claude_bin=$(type -P claude)

    if [[ -z "$claude_bin" ]]; then
        echo "claude: command not found" >&2
        return 127
    fi

    if [[ "$(uname -s)" == "Darwin" && -n "${TMUX:-}" ]] && command -v reattach-to-user-namespace &>/dev/null; then
        reattach-to-user-namespace "$claude_bin" "$@"
    else
        "$claude_bin" "$@"
    fi
}

_dot_claude_wants_chrome() {
    [[ "${DOTFILES_CLAUDE_SKIP_CHROME:-0}" == 1 ]] && return 1

    local arg
    for arg in "$@"; do
        case "$arg" in
            --no-chrome) return 1 ;;
            --chrome) return 0 ;;
        esac
    done

    return 0
}

_dot_claude_has_chrome_flag() {
    local arg
    for arg in "$@"; do
        [[ "$arg" == "--chrome" ]] && return 0
    done
    return 1
}

claude() {
    local -a extra=()

    if [[ "${1:-}" == "yolo" ]]; then
        shift
        extra=(--dangerously-skip-permissions)
    fi

    if _dot_claude_wants_chrome "$@" && ! _dot_claude_has_chrome_flag "$@"; then
        if ((${#extra[@]})); then
            _dot_claude_command --chrome "${extra[@]}" "$@"
        else
            _dot_claude_command --chrome "$@"
        fi
    elif ((${#extra[@]})); then
        _dot_claude_command "${extra[@]}" "$@"
    else
        _dot_claude_command "$@"
    fi
}
