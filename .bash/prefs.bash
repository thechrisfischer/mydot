#!/bin/bash

# Source user config if it exists
if [[ -f "$HOME/.bash/config.bash" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.bash/config.bash"
fi

# PATH setup
if [[ "$(uname -s)" == "Darwin" ]]; then
    export PATH="$HOME/bin:$HOME/sbin:$HOME/.local/bin:/opt/local/bin:/opt/local/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"
elif [[ "$(uname -s)" == "Linux" ]]; then
    if [[ -d /home/linuxbrew/.linuxbrew ]]; then
        export PATH="$HOME/bin:$HOME/sbin:$HOME/.local/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"
    else
        export PATH="$HOME/bin:$HOME/sbin:$HOME/.local/bin:/usr/local/bin:/usr/local/sbin:$PATH"
    fi
fi

# Shell options for better behavior
# set -o vi                    # Vi mode (disabled - prefer emacs mode)

# Bash-specific options (only set if using bash)
if [[ -n "$BASH_VERSION" ]]; then
    shopt -s histappend          # Append to history instead of overwriting
    shopt -s checkwinsize        # Check window size after each command
    shopt -s extglob             # Extended globbing
    # Only enable globstar if supported (bash >= 4)
    if shopt -q globstar 2>/dev/null; then
        shopt -s globstar 2>/dev/null
    fi
elif [[ -n "$ZSH_VERSION" ]]; then
    # Zsh equivalent options
    setopt APPEND_HISTORY        # Append to history instead of overwriting
    setopt EXTENDED_GLOB         # Extended globbing
    setopt GLOB_STAR_SHORT       # ** globbing
fi

# History settings
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups

# AWS defaults. Set DOTFILES_AWS_PROFILE in config.bash to pick a default profile.
export AWS_SDK_LOAD_CONFIG=1
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-2}"
if [[ -n "${DOTFILES_AWS_PROFILE:-}" && -z "${AWS_PROFILE:-}" ]]; then
    export AWS_PROFILE="$DOTFILES_AWS_PROFILE"
fi

# Colors and display
export CLICOLOR=1
export CLICOLOR_FORCE=1
export LSCOLORS=fxFxCxDxBxegedabagacad

alias code='cd ~/Code/'
alias pp='git pull && git push'
alias listen='sudo lsof -i -P | grep LISTEN'

# Source credentials if they exist (keeps sensitive data separate)
if [[ -f "$HOME/.bash/credentials.bash" ]]; then
    # shellcheck source=/dev/null
    source "$HOME/.bash/credentials.bash"
fi

#setup pipx defaults - using $HOME for portability
export PIPX_HOME="$HOME/.local/pipx"
export PIPX_BIN_DIR="$HOME/.local/bin"
export PIPX_MAN_DIR="$HOME/.local/share/man"
export PIPX_SHARED_LIBS="$HOME/.pipx/shared"
export PIPX_LOCAL_VENVS="$HOME/.pipx/venvs"
export PIPX_LOG_DIR="$HOME/.pipx/logs"
export PIPX_TRASH_DIR="$HOME/.pipx/.trash"
export PIPX_VENV_CACHEDIR="$HOME/.pipx/.cache"
export PIPX_STANDALONE_PYTHON_CACHEDIR="$HOME/.pipx/py"
if [[ -n "${DOTFILES_PIPX_PYTHON:-}" ]]; then
    export PIPX_DEFAULT_PYTHON="$DOTFILES_PIPX_PYTHON"
else
    # On macOS <15, brew has no bottles and we drive CLIs via MacPorts —
    # so prefer MacPorts python. On macOS 15+ and Linux, prefer Homebrew.
    _dotfiles_macos_major=""
    if [[ "$(uname -s)" == "Darwin" ]]; then
        _dotfiles_macos_major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
    fi
    if [[ "$_dotfiles_macos_major" =~ ^[0-9]+$ && "$_dotfiles_macos_major" -lt 15 ]]; then
        if [[ -x "/opt/local/bin/python3" ]]; then
            export PIPX_DEFAULT_PYTHON="/opt/local/bin/python3"
        elif [[ -x "/opt/homebrew/bin/python3" ]]; then
            export PIPX_DEFAULT_PYTHON="/opt/homebrew/bin/python3"
        elif command -v python3 &>/dev/null; then
            PIPX_DEFAULT_PYTHON="$(command -v python3)"
            export PIPX_DEFAULT_PYTHON
        fi
    else
        if [[ -x "/opt/homebrew/bin/python3" ]]; then
            export PIPX_DEFAULT_PYTHON="/opt/homebrew/bin/python3"
        elif [[ -x "/opt/local/bin/python3" ]]; then
            export PIPX_DEFAULT_PYTHON="/opt/local/bin/python3"
        elif command -v python3 &>/dev/null; then
            PIPX_DEFAULT_PYTHON="$(command -v python3)"
            export PIPX_DEFAULT_PYTHON
        fi
    fi
    unset _dotfiles_macos_major
fi
export USE_EMOJI=true
export PIPX_HOME_ALLOW_SPACE=false

#heroku autocomplete (skipped in fast shell mode)
if [[ "${DOTFILES_FAST_SHELL:-0}" != "1" ]]; then
    HEROKU_AC_BASH_SETUP_PATH="${HOME}/Library/Caches/heroku/autocomplete/bash_setup"
    if [[ -f "$HEROKU_AC_BASH_SETUP_PATH" ]]; then
        # shellcheck source=/dev/null
        source "$HEROKU_AC_BASH_SETUP_PATH"
    fi
fi

# Platform-specific aliases and settings
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    alias ll='ls -hl --color=auto'
    alias ls='ls --color=auto'
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS specific aliases
    alias ll='ls -hl --color=auto'
    alias ls='ls --color=auto'
    alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
    alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
    
    # Cursor terminal fixes for command wrapping issues
    if [[ "$TERM_PROGRAM" == "Cursor" || "$TERM_PROGRAM" == "vscode" ]]; then
        # Unalias potentially problematic commands that might interfere with output
        unalias head 2>/dev/null
        unalias cat 2>/dev/null
        unalias less 2>/dev/null
        unalias more 2>/dev/null
        
        # Force use of actual binaries instead of aliases
        alias head='/usr/bin/head'
        alias cat='/bin/cat'
        alias less='/usr/bin/less'
        alias more='/usr/bin/more'
        
        # Disable pager for certain commands in Cursor
        export PAGER='cat'
        export MANPAGER='cat'
        
        # Set terminal type for better compatibility
        export TERM='xterm-256color'
        
        # Additional fix for pipe issues - ensure commands work in pipes
        function head() {
            /usr/bin/head "$@"
        }
        
        function cat() {
            /bin/cat "$@"
        }
        
        # Export functions so they work in Bash subshells.
        if [[ -n "${BASH_VERSION:-}" ]]; then
            export -f head cat
        fi
        
        # AWS CLI specific fixes for Cursor terminal. `command aws` runs the
        # real binary (skipping this function) without hardcoding its path.
        function aws() {
            # Ensure AWS CLI output is properly handled
            if [[ "$*" == *"--output"* ]]; then
                # If user specified output format, respect it
                command aws "$@"
            else
                # Force JSON output for better parsing and piping
                command aws "$@" --output json
            fi
        }
        
        # Export AWS function for Bash subshells.
        if [[ -n "${BASH_VERSION:-}" ]]; then
            export -f aws
        fi
    fi
fi

# Common development aliases
alias gst='git status'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gp='git push'
alias gl='git pull'
alias gc='git commit'
alias ga='git add'
alias gd='git diff'
alias glog='git log --oneline'

# LLM-powered commit aliases
alias gcl='dot-commit-llm'  # git commit with LLM
alias gcll='dot-commit-llm' # alternative alias

# System aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ports='lsof -i -P | grep LISTEN'
alias myip='curl -s ifconfig.me'
alias weather='curl -s wttr.in'

# Python aliases
alias py='python3'
alias pip='pip3'
alias venv='python3 -m venv'

# Google Cloud SDK setup (skipped in fast shell mode — path + completion can be slow)
if [[ "${DOTFILES_FAST_SHELL:-0}" != "1" ]]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        GCLOUD_SDK_PATH="${HOME}/Downloads/google-cloud-sdk"
        if [[ -f "${GCLOUD_SDK_PATH}/path.bash.inc" ]]; then
            # shellcheck source=/dev/null
            source "${GCLOUD_SDK_PATH}/path.bash.inc" 2>/dev/null
        fi
        if [[ -f "${GCLOUD_SDK_PATH}/completion.bash.inc" ]]; then
            # shellcheck source=/dev/null
            source "${GCLOUD_SDK_PATH}/completion.bash.inc" 2>/dev/null
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        for GCLOUD_SDK_PATH in "${HOME}/google-cloud-sdk" "/opt/google-cloud-sdk" "/usr/lib/google-cloud-sdk"; do
            if [[ -f "${GCLOUD_SDK_PATH}/path.bash.inc" ]]; then
                # shellcheck source=/dev/null
                source "${GCLOUD_SDK_PATH}/path.bash.inc" 2>/dev/null
                break
            fi
        done
        for GCLOUD_SDK_PATH in "${HOME}/google-cloud-sdk" "/opt/google-cloud-sdk" "/usr/lib/google-cloud-sdk"; do
            if [[ -f "${GCLOUD_SDK_PATH}/completion.bash.inc" ]]; then
                # shellcheck source=/dev/null
                source "${GCLOUD_SDK_PATH}/completion.bash.inc" 2>/dev/null
                break
            fi
        done
    fi
fi
