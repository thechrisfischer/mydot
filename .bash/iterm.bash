#!/usr/bin/env bash
# iTerm2 shell integration — load after prompt.bash so PROMPT_COMMAND is set first.
# Lets iTerm detect/fix stuck mouse reporting after SSH/tmux disconnects.

[[ "$(uname -s)" == "Darwin" ]] || return 0
[[ $- == *i* ]] || return 0

# Mouse-state cleanup still works inside tmux/screen even though marks/history do not.
export ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX=1

_iterm_si="${HOME}/.iterm2_shell_integration.bash"
if [[ ! -f "$_iterm_si" && -n "${DOTFILES_DIR:-}" ]]; then
    _iterm_si="${DOTFILES_DIR}/system/iterm2/iterm2_shell_integration.bash"
fi
if [[ -f "$_iterm_si" ]]; then
    # shellcheck source=/dev/null
    source "$_iterm_si"
fi
unset _iterm_si
