#!/bin/bash
# shellcheck disable=SC1091

DOTFILES_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_REPO_DIR

# Strip flags (--verbose / -v / --mcp) so $1 is always the subcommand
args=()
for arg in "$@"; do
  [[ "$arg" == --verbose || "$arg" == -v ]] && continue
  args+=("$arg")
done

source "$DOTFILES_REPO_DIR/install/_helpers.bash"
_maybe_reexec_arm64 "$0" "$@"

case "${args[0]:-}" in
    --help|-h|help)
        print_usage
        exit 0
        ;;
    dotfiles)
        _verify_repo_complete || exit 1
        if [[ "$(uname -s)" == "Darwin" ]]; then
            _ensure_sudo_cached || exit 1
        fi
        source "$DOTFILES_REPO_DIR/install/dotfiles.bash"
        _section_run "dotfiles" install_dotfiles
        ;;
    ssh-keys)
        source "$DOTFILES_REPO_DIR/install/ssh-keys.bash"
        _section_run "ssh-keys" install_ssh_keys
        ;;
    bootstrap)
        source "$DOTFILES_REPO_DIR/install/bootstrap.bash"
        _section_run "bootstrap" install_bootstrap
        ;;
    ssh)
        source "$DOTFILES_REPO_DIR/install/ssh.bash"
        _section_run "ssh" install_ssh
        ;;
    vim)
        source "$DOTFILES_REPO_DIR/install/vim.bash"
        _section_run "vim" install_vim
        ;;
    packages)
        source "$DOTFILES_REPO_DIR/install/packages.bash"
        _ensure_sudo_cached || exit 1
        if [[ "$(uname -s)" == "Darwin" ]]; then
            # _ensure_brew best-effort — install_packages handles MacPorts on macOS <15
            _ensure_brew || echo "⚠️  brew unavailable — casks will be skipped"
        fi
        _section_run "packages" install_packages
        ;;
    apps)
        source "$DOTFILES_REPO_DIR/install/apps.bash"
        if [[ "$(uname -s)" == "Darwin" ]]; then
            # brew required — casks have no MacPorts equivalent
            _ensure_sudo_cached || _install_progress "sudo not cached — apps needing root may fail"
            _ensure_brew || exit 1
        else
            _ensure_sudo_cached || _install_progress "sudo not cached — apps needing root may fail"
        fi
        _section_run "apps" install_apps
        ;;
    dictation)
        source "$DOTFILES_REPO_DIR/install/dictation.bash"
        _ensure_sudo_cached || exit 1
        _section_run "dictation" install_dictation
        ;;
    iterm)
        source "$DOTFILES_REPO_DIR/install/iterm.bash"
        _ensure_sudo_cached || exit 1
        _section_run "iterm" install_iterm
        ;;
    cursor)
        source "$DOTFILES_REPO_DIR/install/cursor.bash"
        _section_run "cursor" install_cursor
        ;;
    claude)
        source "$DOTFILES_REPO_DIR/install/claude.bash"
        _section_run "claude" install_claude
        ;;
    codex)
        source "$DOTFILES_REPO_DIR/install/codex.bash"
        _section_run "codex" install_codex
        ;;
    agents-doctor|doctor)
        source "$DOTFILES_REPO_DIR/install/agents-doctor.bash"
        install_agents_doctor
        ;;
    mcp)
        source "$DOTFILES_REPO_DIR/mcp/install.bash"
        _section_run "mcp" install_mcp
        ;;
    composio)
        source "$DOTFILES_REPO_DIR/mcp/composio.bash"
        _section_run "composio" install_composio
        ;;
    composio-auth)
        # shellcheck source=/dev/null
        source "$DOTFILES_REPO_DIR/.bash/functions/dot-composio-auth.bash"
        dot-composio-auth "${args[1]:-login}"
        ;;
    grepler)
        source "$DOTFILES_REPO_DIR/mcp/grepler.bash"
        _section_run "grepler" install_grepler
        ;;
    playwright)
        source "$DOTFILES_REPO_DIR/mcp/playwright.bash"
        _section_run "playwright" install_playwright
        ;;
    grepler-agent)
        source "$DOTFILES_REPO_DIR/install/grepler-agent.bash"
        _section_run "grepler-agent" install_grepler_agent
        ;;
    hostname)
        source "$DOTFILES_REPO_DIR/install/hostname.bash"
        configure_hostname
        ;;
    shell)
        source "$DOTFILES_REPO_DIR/install/shell.bash"
        _section_run "shell" configure_shell
        ;;
    backup)
        backup_dir="/tmp/dotfiles_backup_$(timestamp)"
        _section_run "backup" backup "$backup_dir"
        ;;
    all)
        # Fail fast on an incomplete copy before doing any slow work (package
        # builds, casks). Cheaper than discovering mid-run that nothing sources.
        _verify_repo_complete || exit 1

        # Cache sudo before captured sections run, so the password prompt
        # appears on its own line up top instead of mid-output. Non-fatal: a
        # missing sudo cache only affects the sudo-dependent sections, which
        # report their own failure in the end-of-run summary — it should not
        # abort the whole hands-off run.
        _ensure_sudo_cached || _install_progress "sudo not cached — sudo-dependent sections may prompt or fail"

        # Every section below runs via _all_run, which records failures and
        # keeps going instead of aborting the run. A summary at the very end
        # lists anything that failed and how to re-run it.

        backup_dir="/tmp/dotfiles_backup_$(timestamp)"
        _all_run "backup" "" backup "$backup_dir"

        # Hostname sync is cosmetic and prompts interactively, which stalls an
        # otherwise hands-off `all` run mid-stream. Skip it here by default;
        # run `./install.sh hostname` (or set DOTFILES_SYNC_HOSTNAME=1) to sync.
        if [[ "$(uname -s)" == "Darwin" && "${DOTFILES_SYNC_HOSTNAME:-0}" == 1 ]]; then
            source "$DOTFILES_REPO_DIR/install/hostname.bash"
            configure_hostname || _DOTFILES_ALL_FAILED+=("hostname")
        fi

        _all_run "dotfiles" "install/dotfiles.bash" install_dotfiles

        _all_run "ssh" "install/ssh.bash" install_ssh

        _all_run "vim" "install/vim.bash" install_vim

        source "$DOTFILES_REPO_DIR/install/packages.bash"
        if [[ "$(uname -s)" == "Darwin" ]]; then
            _ensure_sudo_cached || _install_progress "sudo not cached — package installs needing root may fail"
            # _ensure_brew best-effort — install_packages handles MacPorts on macOS <15
            _ensure_brew || echo "⚠️  brew unavailable — casks will be skipped"
        fi
        _all_run "packages" "" install_packages

        _ensure_sudo_cached || _install_progress "sudo not cached — apps needing root may fail"
        _all_run "apps" "install/apps.bash" install_apps

        if [[ "$(uname -s)" == "Linux" ]]; then
            _ensure_sudo_cached || _install_progress "sudo not cached — Linux input setup may fail"
            _all_run "dictation" "install/dictation.bash" install_dictation
        fi

        _all_run "cursor" "install/cursor.bash" install_cursor
        _all_run "claude" "install/claude.bash" install_claude
        _all_run "codex" "install/codex.bash" install_codex
        _all_run "mcp" "mcp/install.bash" install_mcp

        # grepler-agent: per-machine usage daemon (no-op if source repo not cloned)
        _all_run "grepler-agent" "install/grepler-agent.bash" install_grepler_agent

        _all_summary || exit 1
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
