#!/bin/bash
# Shim: loads modular function files from .bash/functions/
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _dotfiles_bash_dir="${BASH_SOURCE[0]%/*}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    _dotfiles_bash_dir="${${(%):-%N}:h}"
else
    _dotfiles_bash_dir="$HOME/.bash"
fi

source "$_dotfiles_bash_dir/functions/_loader.bash"
unset _dotfiles_bash_dir
