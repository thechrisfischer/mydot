# Source bash configuration for compatibility
if [[ -f "$HOME/.bash/prefs.bash" ]]; then
    source "$HOME/.bash/prefs.bash"
fi

if [[ -f "$HOME/.bash/functions/_loader.bash" ]]; then
    source "$HOME/.bash/functions/_loader.bash"
fi

# Zsh-specific settings
setopt APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# History settings
HISTSIZE=10000
SAVEHIST=20000
HISTFILE=~/.zsh_history

# Enable vi mode
bindkey -v

# Better tab completion
autoload -U compinit
compinit

# Enable ** globbing
setopt GLOB_STAR_SHORT
setopt EXTENDED_GLOB
