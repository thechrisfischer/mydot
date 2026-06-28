#!/bin/bash
# Install / refresh the Grepler Agent daemon on this machine.
#
# Idempotent: re-running this installs/upgrades the agent binary, refreshes the
# service unit, and (re)loads it. It does NOT mint enrollment codes or run
# `grepler-agent enroll <code>` — enrollment is interactive and machine-specific.
# After the installer reports "not enrolled," follow the printed instructions.

# Optional source checkout for a grepler-agent package. Configure per machine via
# GREPLER_AGENT_SOURCE and, if cloning is desired, GREPLER_AGENT_REPO (org/repo
# for gh, git@ URL, or https URL). Dotfiles does not assume a specific product
# repo by default.
DOTFILES_GREPLER_AGENT_SOURCE_DEFAULT="${DOTFILES_GREPLER_AGENT_SOURCE_DEFAULT:-}"
DOTFILES_GREPLER_AGENT_REPO_DEFAULT="${DOTFILES_GREPLER_AGENT_REPO_DEFAULT:-}"

function install_grepler_agent {
    # shellcheck source=/dev/null
    source "$DOTFILES_REPO_DIR/install/_helpers.bash"

    if ! command -v uv >/dev/null 2>&1; then
        _install_step_fail "grepler-agent" "uv not found — run \`./install.sh packages\` first"
        return 1
    fi

    local source="${GREPLER_AGENT_SOURCE:-$DOTFILES_GREPLER_AGENT_SOURCE_DEFAULT}"
    if [[ -z "$source" ]]; then
        _install_progress "grepler-agent: GREPLER_AGENT_SOURCE not set — skipping optional agent install"
        return 0
    fi

    # ── 0. Clone the grepler repo if the source checkout is absent ────────
    if [[ ! -f "$source/pyproject.toml" ]]; then
        if ! command -v git >/dev/null 2>&1 && ! command -v gh >/dev/null 2>&1; then
            _install_step_fail "grepler-agent" "source not found at $source and neither git nor gh is available — clone the agent repo manually or set GREPLER_AGENT_REPO"
            return 1
        fi
        local repo_spec="${GREPLER_AGENT_REPO:-$DOTFILES_GREPLER_AGENT_REPO_DEFAULT}"
        if [[ -z "$repo_spec" ]]; then
            _install_step_fail "grepler-agent" "source not found at $source and GREPLER_AGENT_REPO is not set"
            return 1
        fi
        local clone_dest
        clone_dest="$(dirname "$source")"
        _install_step_start "clone" "clone $repo_spec → $clone_dest"
        local clone_output
        if clone_output=$(_dotfiles_git_clone "$repo_spec" "$clone_dest" 2>&1); then
            _install_step_done_changed "clone" "$clone_dest"
        else
            _install_step_fail "grepler-agent" "clone of $repo_spec failed (run \`gh auth login -h github.com -p https -w\` or add a GitHub SSH key): $clone_output"
            return 1
        fi
        if [[ ! -f "$source/pyproject.toml" ]]; then
            _install_step_fail "grepler-agent" "cloned $repo_spec but no pyproject.toml at $source — repo layout may have changed"
            return 1
        fi
    fi

    # ── 1. Install / upgrade the agent CLI ────────────────────────────────
    _install_step_start "binary" "uv tool install ($source)"
    local install_output
    if install_output=$(uv tool install --reinstall "$source" 2>&1); then
        if grep -q "Reinstalled" <<<"$install_output" || grep -q "Installed" <<<"$install_output"; then
            _install_step_done_changed "binary" "$(command -v grepler-agent)"
        else
            _install_step_done "binary" "$(command -v grepler-agent) (already current)"
        fi
    else
        _install_step_fail "binary" "uv tool install failed: $install_output"
        return 1
    fi

    # Sanity-check the binary is on PATH (uv links into ~/.local/bin which
    # should already be on PATH for any reasonable shell setup).
    if ! command -v grepler-agent >/dev/null 2>&1; then
        _install_step_fail "binary" "grepler-agent not on PATH after install — check ~/.local/bin"
        return 1
    fi

    # ── 2. Write the service unit ─────────────────────────────────────────
    _install_step_start "service unit" "writing"
    if grepler-agent install-service >/dev/null 2>&1; then
        _install_step_done_changed "service unit" "written"
    else
        _install_step_fail "service unit" "grepler-agent install-service failed"
        return 1
    fi

    # ── 3. Load the service (platform-specific) ───────────────────────────
    local os
    os="$(uname -s)"
    if [[ "$os" == "Darwin" ]]; then
        _grepler_agent_reload_launchd
    elif [[ "$os" == "Linux" ]]; then
        _grepler_agent_reload_systemd_user
    else
        _install_progress "service load: unsupported OS ($os) — agent binary installed but not auto-loaded"
    fi

    # ── 4. Enrollment status reminder ─────────────────────────────────────
    if grepler-agent status 2>/dev/null | grep -q "Not enrolled"; then
        cat <<'EOF'

  ⚠  grepler-agent is installed but NOT enrolled on this machine yet.

  To enroll (one-time, per machine), mint an enrollment code from the configured
  agent service, then run:

    grepler-agent --server <SERVER_URL> enroll <CODE>

  Once enrolled, the launchd/systemd-user service will start shipping
  heartbeats + claude-code.plan events on its own.

EOF
    else
        _install_progress "enrollment: $(grepler-agent status 2>/dev/null | awk -F'  +' '/device_id/ {print $2}')"
    fi

    return 0
}

# ── platform-specific service-load helpers ──────────────────────────────────

function _grepler_agent_reload_launchd {
    local plist="$HOME/Library/LaunchAgents/com.grepler.agent.plist"
    if [[ ! -f "$plist" ]]; then
        _install_step_fail "launchd load" "plist missing at $plist"
        return 1
    fi

    _install_step_start "launchd load" "unloading existing if present..."
    launchctl unload "$plist" >/dev/null 2>&1 || true

    if launchctl load -w "$plist" >/dev/null 2>&1; then
        sleep 1
        if launchctl list 2>/dev/null | awk '{print $3}' | grep -qx "com.grepler.agent"; then
            local pid
            pid=$(launchctl list 2>/dev/null | awk '$3 == "com.grepler.agent" {print $1}')
            if [[ "$pid" =~ ^[0-9]+$ ]] && [[ "$pid" != "0" ]]; then
                _install_step_done_changed "launchd load" "loaded (pid $pid)"
            else
                _install_step_done "launchd load" "loaded (waiting for first run)"
            fi
        else
            _install_step_fail "launchd load" "loaded command returned 0 but job not in launchctl list"
            return 1
        fi
    else
        _install_step_fail "launchd load" "launchctl load failed"
        return 1
    fi
}

function _grepler_agent_reload_systemd_user {
    if ! command -v systemctl >/dev/null 2>&1; then
        _install_progress "systemd-user load: systemctl not available — skipping"
        return 0
    fi

    _install_step_start "systemd-user load" "daemon-reload + enable --now"
    if systemctl --user daemon-reload >/dev/null 2>&1 \
        && systemctl --user enable --now grepler-agent.service >/dev/null 2>&1; then
        local state
        state=$(systemctl --user is-active grepler-agent.service 2>/dev/null || echo "unknown")
        if [[ "$state" == "active" ]]; then
            _install_step_done_changed "systemd-user load" "active"
        else
            _install_step_done "systemd-user load" "enabled (state: $state)"
        fi
    else
        _install_step_fail "systemd-user load" "systemctl --user enable --now failed"
        return 1
    fi
}
