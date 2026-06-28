#!/bin/bash

# Re-template the live iTerm prefs (which iTerm has been writing directly
# into the dotfiles repo via LoadPrefsFromCustomFolder) back into the
# committed .template file with $HOME swapped for __DOTFILES_HOME__, then
# stage and commit. Use this when you want fork-safe paths captured.
dot-iterm-backup() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-iterm-backup"
        echo "Re-templates the live iTerm prefs (system/iterm2/com.googlecode.iterm2.plist)"
        echo "into com.googlecode.iterm2.plist.template with \$HOME → __DOTFILES_HOME__,"
        echo "then commits and pushes."
        return 0
    fi

    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "This command is macOS-only."
        return 0
    fi

    local dotfiles_dir="${DOTFILES_DIR:-$HOME/Code/dotfiles}"
    local live_plist="$dotfiles_dir/system/iterm2/com.googlecode.iterm2.plist"
    local tmpl="$dotfiles_dir/system/iterm2/com.googlecode.iterm2.plist.template"

    if [[ ! -d "$dotfiles_dir" ]]; then
        echo "Error: dotfiles directory not found at $dotfiles_dir"
        return 1
    fi
    if [[ ! -f "$live_plist" ]]; then
        echo "Error: live iTerm prefs not found at $live_plist"
        echo "       (Has iTerm been pointed at the custom folder yet? Run ./install.sh iterm)"
        return 1
    fi

    # Convert binary plist (iTerm may have rewritten it as binary) → XML
    # so the diff is reviewable and the sed templating works.
    local tmp
    tmp=$(mktemp)
    if ! /usr/bin/plutil -convert xml1 -o "$tmp" "$live_plist"; then
        echo "Error: failed to convert live plist to XML"
        rm -f "$tmp"
        return 1
    fi
    sed "s|$HOME|__DOTFILES_HOME__|g" "$tmp" > "$tmpl"
    rm -f "$tmp"

    if ! /usr/bin/plutil -lint "$tmpl" >/dev/null; then
        echo "Error: re-templated plist failed lint"
        return 1
    fi

    echo "Re-templated iTerm prefs to $tmpl"

    cd "$dotfiles_dir" || return 1
    git pull || echo "Warning: git pull failed (continuing)"
    if git add system/iterm2/com.googlecode.iterm2.plist.template && \
       git commit -m "iterm: re-template preferences"; then
        git push || echo "Warning: git push failed"
    else
        echo "No iTerm preference changes to commit"
    fi
}
