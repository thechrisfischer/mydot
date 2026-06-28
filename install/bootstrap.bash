#!/bin/bash

function install_bootstrap {
    echo "Dotfiles bootstrap (in-repo prerequisites)..."

    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "❌ install bootstrap is macOS-only — on Linux use package manager + gh auth login"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$DOTFILES_REPO_DIR/install/_helpers.bash"

    _ensure_xcode_clt || return 1
    _ensure_sudo_cached || return 1
    _ensure_brew || return 1

    _install_progress "bootstrap: installing gh git curl jq"
    brew install gh git curl jq || return 1

    _dotfiles_ensure_github_auth || return 1

    echo ""
    echo "✅ Prerequisites ready."
    echo "Next steps:"
    echo "  ./install.sh ssh          # install SSH config"
    echo "  ./install.sh all"
    echo ""
    echo "Fresh Mac one-liner (before dotfiles exists): docs/fresh-mac-bootstrap.md"
}
