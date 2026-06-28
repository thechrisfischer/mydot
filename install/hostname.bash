#!/bin/bash

# Verify and sync macOS hostname settings
# macOS has 3 independent hostname values that can drift apart:
#   - ComputerName:  friendly name shown in System Settings / Finder
#   - LocalHostName: Bonjour name (usually the most intentionally set)
#   - HostName:      overrides `hostname` output; if unset, falls back to DHCP/DNS

function configure_hostname {
    local os_type
    os_type=$(uname -s)

    if [[ "$os_type" != "Darwin" ]]; then
        echo "Hostname sync is macOS-only, skipping."
        return 0
    fi

    echo "Checking hostname settings..."

    # Gather all values (scutil returns error + empty if unset)
    local computer_name local_host_name host_name actual_hostname
    computer_name=$(scutil --get ComputerName 2>/dev/null || echo "")
    local_host_name=$(scutil --get LocalHostName 2>/dev/null || echo "")
    host_name=$(scutil --get HostName 2>/dev/null || echo "")
    actual_hostname=$(hostname -s 2>/dev/null || hostname)

    # Determine the canonical hostname: LocalHostName is the most reliable
    local canonical="$local_host_name"

    if [[ -z "$canonical" ]]; then
        echo "No LocalHostName is set. Cannot determine intended hostname."
        echo "  Set one with: sudo scutil --set LocalHostName <name>"
        return 1
    fi

    # Check if everything already matches
    local needs_fix=0

    if [[ "$computer_name" != "$canonical" ]]; then
        needs_fix=1
    fi
    if [[ "$host_name" != "$canonical" ]]; then
        needs_fix=1
    fi
    if [[ "$actual_hostname" != "$canonical" ]]; then
        needs_fix=1
    fi

    if [[ "$needs_fix" -eq 0 ]]; then
        echo "All hostname settings match: $canonical"
        return 0
    fi

    # Show what's out of sync
    echo ""
    echo "  Hostname discrepancy detected:"
    echo "  ────────────────────────────────────────"
    printf "  %-18s %s\n" "LocalHostName:" "$local_host_name"
    printf "  %-18s %s\n" "ComputerName:" "${computer_name:-(not set)}"
    printf "  %-18s %s\n" "HostName:" "${host_name:-(not set)}"
    printf "  %-18s %s\n" "hostname output:" "$actual_hostname"
    echo "  ────────────────────────────────────────"
    echo ""
    echo "  Will set all to: $canonical"
    echo ""

    # Prompt for confirmation (skip if non-interactive)
    if [[ -t 0 ]]; then
        read -r -p "  Proceed? [Y/n] " answer
        case "${answer:-Y}" in
            [Yy]*|"") ;;
            *)
                echo "  Skipped."
                return 0
                ;;
        esac
    fi

    # Apply — requires sudo
    echo "  Setting hostnames (may require sudo)..."
    if declare -f _ensure_sudo_cached &>/dev/null; then
        _ensure_sudo_cached || return 1
    fi
    sudo scutil --set ComputerName "$canonical"
    sudo scutil --set HostName "$canonical"
    sudo scutil --set LocalHostName "$canonical"
    sudo hostname "$canonical"

    echo "  All hostnames set to: $canonical"
}
