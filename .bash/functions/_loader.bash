#!/bin/bash
# Loader for modular bash functions
# Sources all *.bash files in this directory (except itself)

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _dotfiles_functions_dir="${BASH_SOURCE[0]%/*}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
    _dotfiles_functions_dir="${${(%):-%N}:h}"
else
    _dotfiles_functions_dir="$HOME/.bash/functions"
fi

for _f in "$_dotfiles_functions_dir"/*.bash; do
    [[ "$(basename "$_f")" == "_loader.bash" ]] && continue
    [[ " ${DOTFILES_SKIP_MODULES:-} " == *" $(basename "$_f" .bash) "* ]] && continue
    if [[ -f "$_f" ]]; then
        # shellcheck source=/dev/null
        source "$_f"
    fi
done
unset _f _dotfiles_functions_dir
