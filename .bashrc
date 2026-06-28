#!/bin/bash
export BASH_SILENCE_DEPRECATION_WARNING=1
for f in "$HOME/.bash/prefs.bash" \
         "$HOME/.bash/functions/_loader.bash" \
         "$HOME/.bash/prompt.bash" \
         "$HOME/.bash/iterm.bash"; do
    [[ -f "$f" ]] && source "$f"
done
unset f
