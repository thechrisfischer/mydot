#!/bin/bash
# Bootstrap a brand-new Mac before dotfiles exists locally.
#
# Fetches this script over HTTPS (no SSH key required). Installs Xcode CLT,
# Homebrew, and GitHub CLI, then clones the repo over public HTTPS with no
# GitHub login (browser `gh` auth is only a fallback for private/forked
# repos), and hands off to ./install.sh.
#
# Usage (on a fresh Mac):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap-macos.sh)"
#
# Optional env vars:
#   DOTFILES_REPO=~/Code/mydot        clone destination
#   DOTFILES_GITHUB=thechrisfischer/mydot
#   DOTFILES_SKIP_INSTALL_ALL=1       stop after clone (don't run install.sh all)
#   GITHUB_TOKEN=...                  non-interactive gh auth (CI / headless)
#
# After clone, bootstrap runs ./install.sh ssh (SSH config), then ./install.sh all.

set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-$HOME/Code/mydot}"
DOTFILES_GITHUB="${DOTFILES_GITHUB:-thechrisfischer/mydot}"
DOTFILES_RAW_BASE="${DOTFILES_RAW_BASE:-https://raw.githubusercontent.com/thechrisfischer/mydot/main}"

_is_apple_silicon() {
    [[ "$(uname -m)" == "arm64" ]]
}

_ensure_xcode_clt() {
    if xcode-select -p &>/dev/null; then
        echo "✅ Xcode Command Line Tools"
        return 0
    fi

    echo "→ Installing Xcode Command Line Tools (accept the macOS dialog)..."
    xcode-select --install 2>/dev/null || true

    local waited=0
    until xcode-select -p &>/dev/null; do
        sleep 5
        waited=$((waited + 5))
        if (( waited >= 1800 )); then
            echo "❌ Timed out waiting for Command Line Tools (30 min)" >&2
            exit 1
        fi
    done
    echo "✅ Xcode Command Line Tools ready"
}

_ensure_homebrew() {
    if command -v brew &>/dev/null; then
        echo "✅ Homebrew on PATH"
        return 0
    fi

    local brew_path
    if _is_apple_silicon; then
        brew_path="/opt/homebrew/bin/brew"
    else
        brew_path="/usr/local/bin/brew"
    fi

    if [[ -x "$brew_path" ]]; then
        # shellcheck disable=SC1090
        eval "$("$brew_path" shellenv)"
        echo "✅ Homebrew at $brew_path"
        return 0
    fi

    echo "→ Installing Homebrew (sudo password required)..."
    local installer
    installer=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
    if _is_apple_silicon; then
        NONINTERACTIVE=1 /usr/bin/arch -arm64 /bin/bash -c "$installer"
        # shellcheck disable=SC1091
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        NONINTERACTIVE=1 /bin/bash -c "$installer"
        # shellcheck disable=SC1091
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    echo "✅ Homebrew installed"
}

_ensure_gh_packages() {
    echo "→ Installing gh, git, curl, jq..."
    brew install gh git curl jq
}

_ensure_github_auth() {
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        printf '%s\n' "$GITHUB_TOKEN" | gh auth login -h github.com --with-token
        echo "✅ GitHub authenticated via GITHUB_TOKEN"
        return 0
    fi

    if gh auth status &>/dev/null 2>&1; then
        echo "✅ GitHub already authenticated"
        return 0
    fi

    echo "→ GitHub login (browser — use GitHub username/password or SSO; no SSH key required)"
    gh auth login -h github.com -p https -w
    gh auth setup-git
    echo "✅ GitHub authenticated"
}

_optional_ssh_key() {
    : # Generate your own key with ssh-keygen and add it to GitHub if you want git@ remotes.
}

_clone_dotfiles() {
    mkdir -p "$(dirname "$DOTFILES_REPO")"
    if [[ -d "$DOTFILES_REPO/.git" ]]; then
        echo "→ Updating existing dotfiles at $DOTFILES_REPO"
        git -C "$DOTFILES_REPO" pull --ff-only
    else
        echo "→ Cloning $DOTFILES_GITHUB → $DOTFILES_REPO"
        if ! git clone "https://github.com/$DOTFILES_GITHUB.git" "$DOTFILES_REPO" 2>/dev/null; then
            echo "  public clone failed — authenticating with gh and retrying"
            _ensure_github_auth
            gh repo clone "$DOTFILES_GITHUB" "$DOTFILES_REPO"
        fi
    fi
    echo "✅ Dotfiles at $DOTFILES_REPO"
}

_main() {
    [[ "$(uname -s)" == "Darwin" ]] || {
        echo "This bootstrap script is for macOS only." >&2
        exit 1
    }

    echo "=== dotfiles macOS bootstrap ==="
    _ensure_xcode_clt
    _ensure_homebrew
    _ensure_gh_packages
    _optional_ssh_key
    _clone_dotfiles

    cd "$DOTFILES_REPO"

    echo "→ SSH config"
    ./install.sh ssh || echo "⚠️  install.sh ssh failed (non-fatal)"

    if [[ "${DOTFILES_SKIP_INSTALL_ALL:-0}" == 1 ]]; then
        echo "=== Bootstrap complete (DOTFILES_SKIP_INSTALL_ALL=1) ==="
        echo "Next: cd $DOTFILES_REPO && ./install.sh all"
        exit 0
    fi

    echo "→ Running ./install.sh all"
    ./install.sh all
    echo "=== Bootstrap complete ==="
}

_main "$@"
