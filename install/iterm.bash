#!/bin/bash

# iTerm2 install: cask + point iTerm at our custom prefs folder so the
# repo *is* its preference store. iTerm reads from and writes back to
# system/iterm2/com.googlecode.iterm2.plist, picked up live via cfprefsd —
# no quit-and-overwrite dance needed.

function install_iterm {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "iTerm2 is macOS-only — skipping"
        return 0
    fi

    _ensure_brew || return 1
    _brew_cask_install iterm2

    _render_iterm_plist || return 1
    _configure_iterm_shell_integration_prefs
    _install_iterm_shell_integration
    _point_iterm_at_custom_folder
    _set_default_terminal_iterm
}

function _install_iterm_shell_integration {
    local src="$DOTFILES_REPO_DIR/system/iterm2/iterm2_shell_integration.bash"
    local dest="$HOME/.iterm2_shell_integration.bash"

    if [[ ! -f "$src" ]]; then
        echo "WARNING: iTerm shell integration script missing at $src"
        return 0
    fi

    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        echo "iTerm shell integration already installed at $dest"
        return 0
    fi

    cp -a "$src" "$dest"
    echo "Installed iTerm shell integration → $dest"
}

function _configure_iterm_shell_integration_prefs {
    local plist="$DOTFILES_REPO_DIR/system/iterm2/com.googlecode.iterm2.plist"
    if [[ ! -f "$plist" ]]; then
        return 0
    fi

    local key value
    for entry in \
        "Load Shell Integration Automatically:true" \
        "Movement Keys Scroll Outside Interactive Apps:true"; do
        key="${entry%%:*}"
        value="${entry#*:}"
        if /usr/libexec/PlistBuddy -c "Print :'New Bookmarks':0:'${key}'" "$plist" >/dev/null 2>&1; then
            /usr/libexec/PlistBuddy -c "Set :'New Bookmarks':0:'${key}' ${value}" "$plist"
        else
            /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'${key}' bool ${value}" "$plist"
        fi
    done
    echo "Enabled iTerm shell integration + movement-scroll prefs in profile"
}

function _render_iterm_plist {
    # Render the committed template (with __DOTFILES_HOME__ placeholders)
    # into the live plist that iTerm reads. The rendered file is gitignored
    # — once iTerm starts writing changes back to it (after the LoadPrefs
    # switch), we don't want to clobber those on subsequent installs.
    local tmpl="$DOTFILES_REPO_DIR/system/iterm2/com.googlecode.iterm2.plist.template"
    local rendered="$DOTFILES_REPO_DIR/system/iterm2/com.googlecode.iterm2.plist"

    if [[ ! -f "$tmpl" ]]; then
        echo "WARNING: iTerm prefs template missing at $tmpl — skipping render"
        return 0
    fi

    if [[ -f "$rendered" ]]; then
        echo "iTerm prefs already rendered at $rendered — leaving as-is"
        echo "  (delete it and re-run if you want to re-render from the template)"
        return 0
    fi

    sed "s|__DOTFILES_HOME__|$HOME|g" "$tmpl" > "$rendered"
    if ! /usr/bin/plutil -lint "$rendered" >/dev/null 2>&1; then
        echo "❌ Rendered iTerm plist failed lint — removing"
        rm -f "$rendered"
        return 1
    fi
    echo "Rendered iTerm prefs to $rendered"
}

function _point_iterm_at_custom_folder {
    # Tell iTerm to load (and write back) preferences from the dotfiles
    # repo. Once these two keys are set, edits in iTerm GUI flow into
    # system/iterm2/com.googlecode.iterm2.plist; commit them with `git add`
    # when you're ready (or use dot-iterm-backup to also re-template).
    local target="$DOTFILES_REPO_DIR/system/iterm2"
    local current_folder current_load
    current_folder=$(/usr/bin/defaults read com.googlecode.iterm2 PrefsCustomFolder 2>/dev/null || true)
    current_load=$(/usr/bin/defaults read com.googlecode.iterm2 LoadPrefsFromCustomFolder 2>/dev/null || true)

    if [[ "$current_folder" == "$target" && "$current_load" == "1" ]]; then
        echo "iTerm2 already pointed at $target — no prefs change needed"
        return 0
    fi

    /usr/bin/defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$target"
    /usr/bin/defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
    # Suppress the "save changes to custom folder?" prompt on quit — we
    # want iTerm to write back automatically.
    /usr/bin/defaults write com.googlecode.iterm2 NoSyncNeverRemindPrefsChangesLost -bool true
    echo "Pointed iTerm2 at custom prefs folder: $target"
    if pgrep -x iTerm2 >/dev/null 2>&1; then
        echo "  iTerm2 will pick up the new prefs folder on next launch."
    fi
}

function _set_default_terminal_iterm {
    # macOS routes "default terminal" through private LaunchServices APIs that
    # are only invoked by iTerm's "Make iTerm2 Default Term" menu item — there
    # is no clean `defaults write` for it. Detect prior registration via the
    # LaunchServices secure plist; if absent, prompt the user (Chrome-style).
    local ls_plist="$HOME/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
    if [[ -f "$ls_plist" ]] && \
       /usr/bin/plutil -convert xml1 -o - "$ls_plist" 2>/dev/null | \
       grep -q "com.googlecode.iterm2"; then
        echo "iTerm2 already registered as default terminal — skipping prompt"
        return 0
    fi

    if [[ ! -e /dev/tty ]]; then
        echo "WARNING: no TTY available — skipping iTerm default-terminal prompt"
        return 0
    fi

    open -a iTerm 2>/dev/null || {
        echo "WARNING: could not open iTerm2 — skipping default-terminal prompt"
        return 0
    }
    {
        echo ""
        echo "==> Set iTerm2 as your default terminal."
        echo "    In iTerm2's menu bar: iTerm2 → Make iTerm2 Default Term"
        echo "    (one-time click; macOS has no CLI for this)."
        echo "    Then return here and press ENTER to continue."
    } > /dev/tty
    read -r -p "Press ENTER once iTerm2 is set as default terminal... " _ < /dev/tty > /dev/tty
}
