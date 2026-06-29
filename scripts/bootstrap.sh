#!/bin/bash
# Universal bootstrap for a brand-new machine (macOS modern/legacy, Debian/Ubuntu).
#
# Installs nothing it doesn't have to: on macOS it ensures only the Xcode
# Command Line Tools (which provide git + curl); on Linux/apt it ensures git.
# It primes sudo via /dev/tty (so `curl | bash` works), clones over public
# HTTPS, then hands off to ./install.sh all — which already prefers MacPorts on
# macOS <15, Homebrew on macOS 15+, and apt on Linux. gh/jq are installed only
# if a public clone fails (private/fork).
#
# Usage (works piped or via -c):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap.sh)"
#   curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap.sh | bash
#
# Env: DOTFILES_REPO, DOTFILES_GITHUB, DOTFILES_SKIP_INSTALL_ALL, GITHUB_TOKEN,
#      DOTFILES_SUDO_PASSWORD (headless sudo).

DOTFILES_REPO="${DOTFILES_REPO:-$HOME/Code/mydot}"
DOTFILES_GITHUB="${DOTFILES_GITHUB:-thechrisfischer/mydot}"

_bootstrap_os() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)  echo linux ;;
        *)      echo unsupported ;;
    esac
}

_bootstrap_macos_pkg_strategy() {
    # Echo the package manager install.sh will prefer, from a version string.
    # macOS <15 → macports (no Homebrew bottles), 15+ → homebrew. Informational
    # only (install.sh makes the real choice); used for the bootstrap banner.
    local pv="$1" major
    major="${pv%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || { echo homebrew; return 0; }
    if [[ "$major" -lt 15 ]]; then echo macports; else echo homebrew; fi
}

# Read sudo password from /dev/tty even under `curl | bash`. No-op if already cached.
_bootstrap_prime_sudo() {
    command -v sudo >/dev/null 2>&1 || return 0
    sudo -n -v 2>/dev/null && return 0
    if [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
        printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S -v 2>/dev/null && return 0
    fi
    if { [ -w /dev/tty ]; } 2>/dev/null; then
        echo "→ Caching sudo (you'll be prompted once)..." > /dev/tty
        sudo -v < /dev/tty > /dev/tty 2>&1 || { echo "⚠️  sudo not cached — some steps may prompt or fail" >&2; return 1; }
        return 0
    fi
    echo "⚠️  no TTY for sudo — set DOTFILES_SUDO_PASSWORD or run from a terminal" >&2
    return 1
}

_ensure_xcode_clt() {
    xcode-select -p &>/dev/null && { echo "✅ Xcode Command Line Tools"; return 0; }
    echo "→ Installing Xcode Command Line Tools (accept the macOS dialog)..."
    xcode-select --install 2>/dev/null || true
    local waited=0
    until xcode-select -p &>/dev/null; do
        sleep 5; waited=$((waited + 5))
        (( waited >= 1800 )) && { echo "❌ Timed out waiting for CLT (30 min)" >&2; exit 1; }
    done
    echo "✅ Xcode Command Line Tools ready"
}

_ensure_git_linux() {
    command -v git &>/dev/null && { echo "✅ git present"; return 0; }
    if command -v apt-get &>/dev/null; then
        _bootstrap_prime_sudo || true
        sudo apt-get update && sudo apt-get install -y git
    else
        echo "❌ Only Debian/Ubuntu (apt) is supported by this bootstrap. Install git manually, then re-run." >&2
        exit 1
    fi
}

_clone_dotfiles() {
    mkdir -p "$(dirname "$DOTFILES_REPO")"
    if [[ -d "$DOTFILES_REPO/.git" ]]; then
        echo "→ Updating existing checkout at $DOTFILES_REPO"
        git -C "$DOTFILES_REPO" pull --ff-only || true
        return 0
    fi
    echo "→ Cloning $DOTFILES_GITHUB → $DOTFILES_REPO"
    git clone "https://github.com/$DOTFILES_GITHUB.git" "$DOTFILES_REPO" 2>/dev/null && return 0
    echo "  public clone failed — authenticating with gh (private/fork) and retrying"
    if ! command -v gh &>/dev/null; then
        if [[ "$(_bootstrap_os)" == macos ]] && command -v brew &>/dev/null; then brew install gh
        elif command -v apt-get &>/dev/null; then _bootstrap_prime_sudo || true; sudo apt-get install -y gh || true
        fi
    fi
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then printf '%s\n' "$GITHUB_TOKEN" | gh auth login -h github.com --with-token
    else gh auth login -h github.com -p https -w; fi
    gh repo clone "$DOTFILES_GITHUB" "$DOTFILES_REPO"
}

_main() {
    set -euo pipefail
    local os; os="$(_bootstrap_os)"
    echo "=== mydot bootstrap ($os) ==="
    case "$os" in
        macos)
            local pv; pv="$(/usr/bin/sw_vers -productVersion 2>/dev/null || echo '')"
            [[ -n "$pv" ]] && echo "→ macOS $pv → install.sh will prefer: $(_bootstrap_macos_pkg_strategy "$pv")"
            _ensure_xcode_clt
            _bootstrap_prime_sudo || true
            ;;
        linux)
            _ensure_git_linux
            _bootstrap_prime_sudo || true
            ;;
        *)  echo "❌ Unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac
    _clone_dotfiles
    cd "$DOTFILES_REPO"
    echo "→ SSH config"; ./install.sh ssh || echo "⚠️  install.sh ssh failed (non-fatal)"
    if [[ "${DOTFILES_SKIP_INSTALL_ALL:-0}" == 1 ]]; then
        echo "=== Bootstrap complete (DOTFILES_SKIP_INSTALL_ALL=1) ==="
        echo "Next: cd $DOTFILES_REPO && ./install.sh all"; exit 0
    fi
    echo "→ Running ./install.sh all"; ./install.sh all
    echo "=== Bootstrap complete ==="
}

# Allow `source bootstrap.sh --source-only` for unit tests (defines functions, no run).
if [[ "${1:-}" == "--source-only" ]]; then return 0 2>/dev/null || exit 0; fi
_main "$@"
