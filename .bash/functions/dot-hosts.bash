#!/bin/bash

# Function to interact with host registry API
dot-hosts() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-hosts <command> [options]"
        echo ""
        echo "Commands:"
        echo "  ping <hostname>     Lookup hostname and ping its IP address"
        echo "  lookup [hostname]   Display host information (all hosts if no hostname)"
        echo "  sync [--dry-run]    Sync online hosts to /etc/hosts (requires sudo)"
        echo "  clear               Remove all dot-hosts managed entries from /etc/hosts (requires sudo)"
        echo ""
        echo "Examples:"
        echo "  dot-hosts ping hades"
        echo "  dot-hosts lookup"
        echo "  dot-hosts lookup hades"
        echo "  dot-hosts sync"
        echo "  dot-hosts sync --dry-run"
        echo "  dot-hosts clear"
        return 0
    fi

    local command="$1"
    shift

    case "$command" in
        ping)
            _dot-hosts-ping "$@"
            ;;
        lookup)
            _dot-hosts-lookup "$@"
            ;;
        sync)
            _dot-hosts-sync "$@"
            ;;
        clear)
            _dot-hosts-clear "$@"
            ;;
        "")
            echo "Error: No command specified"
            echo "Use 'dot-hosts --help' for usage information"
            return 1
            ;;
        *)
            echo "Error: Unknown command '$command'"
            echo "Use 'dot-hosts --help' for usage information"
            return 1
            ;;
    esac
}

# Helper function to fetch host registry data
_dot-hosts-fetch-data() {
    local api_url="${DOTFILES_HOSTS_API_URL:-}"

    if [[ -z "$api_url" ]]; then
        echo "Error: DOTFILES_HOSTS_API_URL is not set" >&2
        echo "Set it in ~/.bash/config.bash or export it in your shell" >&2
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    if ! curl -s -f "$api_url" > "$temp_file" 2>/dev/null; then
        echo "Error: Failed to fetch host registry data from $api_url" >&2
        rm -f "$temp_file"
        return 1
    fi

    # Check if jq is available
    if command -v jq &>/dev/null; then
        cat "$temp_file"
        rm -f "$temp_file"
        return 0
    else
        # Fallback: return raw JSON (caller will need to parse differently)
        cat "$temp_file"
        rm -f "$temp_file"
        return 0
    fi
}

# Helper function to find host by hostname
_dot-hosts-find-host() {
    local search_hostname="$1"
    local json_data="$2"

    if command -v jq &>/dev/null; then
        # Use jq for JSON parsing
        echo "$json_data" | jq -r --arg hostname "$search_hostname" '
            .hosts[] |
            select(.hostname | ascii_downcase | contains($hostname | ascii_downcase)) |
            "\(.hostname)|\(.ip)|\(.mac)|\(.router)|\(.connection_type)|\(.online)"
        ' | head -1
    else
        # Fallback: use grep and awk (less reliable but works)
        echo "$json_data" | grep -i "\"hostname\".*$search_hostname" -A 5 | \
            grep -E "(hostname|ip|mac|router|connection_type|online)" | \
            awk -F'"' '{print $4}' | tr '\n' '|' | sed 's/|$//'
    fi
}

# Helper function to check sudo
_dot-hosts-check-sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo "This operation requires sudo privileges."
        if ! sudo -n true 2>/dev/null; then
            echo "Please enter your password:"
            sudo -v
        fi
        return 0
    fi
    return 0
}

# Helper function to backup /etc/hosts
_dot-hosts-backup-file() {
    local hosts_file="/etc/hosts"
    local backup_dir="/tmp"
    local backup_file
    backup_file="$backup_dir/dot-hosts-backup-$(date +%Y%m%d-%H%M%S)"

    if [[ ! -f "$hosts_file" ]]; then
        echo "Error: $hosts_file not found" >&2
        return 1
    fi

    if cp "$hosts_file" "$backup_file" 2>/dev/null; then
        echo "$backup_file"
        return 0
    else
        echo "Error: Failed to create backup" >&2
        return 1
    fi
}

# Helper function to validate hosts file syntax
_dot-hosts-validate-file() {
    local hosts_file="$1"

    # Check that file exists and is readable
    if [[ ! -r "$hosts_file" ]]; then
        echo "Error: Cannot read $hosts_file" >&2
        return 1
    fi

    # Check that file is not empty
    if [[ ! -s "$hosts_file" ]]; then
        echo "Error: $hosts_file is empty" >&2
        return 1
    fi

    # Basic syntax check: verify each non-comment, non-blank line has an IP address
    # This is a simple validation - more complex validation could be added
    local invalid_lines
    invalid_lines=$(grep -v '^[[:space:]]*#' "$hosts_file" | grep -v '^[[:space:]]*$' | \
        grep -vEc '^[[:space:]]*[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}[[:space:]]' || true)
    invalid_lines=${invalid_lines:-0}

    if [[ "$invalid_lines" -gt 0 ]]; then
        echo "Warning: Found $invalid_lines potentially invalid lines in $hosts_file" >&2
        # Don't fail on warnings, but log them
    fi

    return 0
}

# Ping subcommand
_dot-hosts-ping() {
    if [[ -z "$1" ]]; then
        echo "Error: Hostname required"
        echo "Usage: dot-hosts ping <hostname>"
        return 1
    fi

    local hostname="$1"
    local json_data
    if ! json_data=$(_dot-hosts-fetch-data); then
        return 1
    fi

    local host_info
    host_info=$(_dot-hosts-find-host "$hostname" "$json_data")

    if [[ -z "$host_info" ]]; then
        echo "Error: Host '$hostname' not found in registry"
        return 1
    fi

    # Parse host info (format: hostname|ip|mac|router|connection_type|online)
    IFS='|' read -r found_hostname ip mac router conn_type online <<< "$host_info"

    echo "Host: $found_hostname"
    echo "IP: $ip"
    echo "Router: $router"
    echo "Connection: $conn_type"
    echo "Status: $([ "$online" == "true" ] && echo "Online" || echo "Offline")"
    echo ""
    echo "Pinging $ip..."

    # Ping with platform-specific options
    local os_type
    os_type=$(uname -s | tr '[:upper:]' '[:lower:]')

    if [[ "$os_type" == "darwin" ]]; then
        # macOS ping
        ping -c 4 "$ip"
    else
        # Linux ping
        ping -c 4 "$ip"
    fi
}

# Lookup subcommand
_dot-hosts-lookup() {
    local json_data
    if ! json_data=$(_dot-hosts-fetch-data); then
        return 1
    fi

    if [[ -z "$1" ]]; then
        # Show all hosts
        if command -v jq &>/dev/null; then
            echo "Host Registry - All Hosts"
            echo "========================"
            echo ""
            printf "%-25s %-18s %-15s %-12s %-8s\n" "Hostname" "IP Address" "Router" "Connection" "Status"
            echo "--------------------------------------------------------------------------------"

            echo "$json_data" | jq -r '.hosts[] |
                "\(.hostname)|\(.ip)|\(.router)|\(.connection_type)|\(if .online then "Online" else "Offline" end)"
            ' | while IFS='|' read -r hostname ip router conn_type status; do
                printf "%-25s %-18s %-15s %-12s %-8s\n" "$hostname" "$ip" "$router" "$conn_type" "$status"
            done

            local total
            total=$(echo "$json_data" | jq '.hosts | length')
            echo ""
            echo "Total: $total hosts"
        else
            echo "Error: jq is required for listing all hosts"
            echo "Install jq: sudo port install jq (MacPorts) / brew install jq (macOS) / apt-get install jq (Linux)"
            return 1
        fi
    else
        # Search for specific hostname
        local hostname="$1"
        local host_info
        host_info=$(_dot-hosts-find-host "$hostname" "$json_data")

        if [[ -z "$host_info" ]]; then
            echo "Error: Host '$hostname' not found in registry"
            return 1
        fi

        # Parse host info
        IFS='|' read -r found_hostname ip mac router conn_type online <<< "$host_info"

        echo "Host Information"
        echo "================"
        echo "Hostname:      $found_hostname"
        echo "IP Address:    $ip"
        echo "MAC Address:   $mac"
        echo "Router:        $router"
        echo "Connection:    $conn_type"
        echo "Status:        $([ "$online" == "true" ] && echo "Online" || echo "Offline")"
    fi
}

# Sync subcommand
_dot-hosts-sync() {
    local dry_run=false

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                echo "Error: Unknown option '$1'"
                echo "Usage: dot-hosts sync [--dry-run]"
                return 1
                ;;
        esac
    done

    if [[ "$dry_run" == false ]]; then
        _dot-hosts-check-sudo || return 1
    fi

    local json_data
    if ! json_data=$(_dot-hosts-fetch-data); then
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for sync operation"
        echo "Install jq: sudo port install jq (MacPorts) / brew install jq (macOS) / apt-get install jq (Linux)"
        return 1
    fi

    local hosts_file="/etc/hosts"
    local backup_file=""

    if [[ "$dry_run" == false ]]; then
        if ! backup_file=$(_dot-hosts-backup-file); then
            return 1
        fi
        echo "Backup created: $backup_file"
    fi

    # Extract online hosts and write /etc/hosts entries.
    #
    # Notes:
    # - Avoid bash associative arrays for macOS /bin/bash 3.2 compatibility.
    # - If the registry contains duplicate hostnames across routers, prefer the
    #   entry in the same /24 subnet as the current machine when possible.
    local temp_hosts
    temp_hosts=$(mktemp)
    # Detect local /24 prefix for best-match selection
    local current_ip=""
    local network_prefix=""
    local interface=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        interface=$(route -n get 8.8.8.8 2>/dev/null | awk '/interface:/{print $2}' | head -1)
        if [[ -n "$interface" ]]; then
            current_ip=$(ipconfig getifaddr "$interface" 2>/dev/null || true)
        fi
        network_prefix=$(echo "$current_ip" | cut -d. -f1-3)
    else
        current_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
        network_prefix=$(echo "$current_ip" | cut -d. -f1-3)
    fi

    # If we couldn't detect a valid IP, fall back to no preference.
    if [[ -z "$current_ip" || "$current_ip" == "127.0.0.1" || "$network_prefix" == "$current_ip" ]]; then
        network_prefix=""
    fi

    # Warn on hostname conflicts, but don't fail: we will choose the best match.
    local duplicate_check=""
    duplicate_check=$(echo "$json_data" | jq -r '.hosts[] | select(.online == true) | "\(.hostname)|\(.ip)"' | \
        awk -F'|' '
            $1 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { next }
            { if (seen[$1] && seen[$1] != $2) conflicts[$1]=seen[$1] " vs " $2; if (!seen[$1]) seen[$1]=$2 }
            END{ for (h in conflicts) print h " (IP conflict: " conflicts[h] ")" }
        ' | sort)

    if [[ -n "$duplicate_check" ]]; then
        if [[ -n "$network_prefix" ]]; then
            echo "Warning: Duplicate hostnames found with different IPs."
            echo "Choosing the best match for your local subnet ($network_prefix.0/24)."
        else
            echo "Warning: Duplicate hostnames found with different IPs."
            echo "Choosing an arbitrary match (could not detect local subnet)."
        fi
        echo "$duplicate_check" | while read -r dup; do
            [[ -n "$dup" ]] && echo "  - $dup"
        done
    fi

    # Select one entry per hostname, preferring the local subnet when possible.
    local selected_hosts=""
    selected_hosts=$(echo "$json_data" | jq -r '.hosts[] | select(.online == true) | "\(.hostname)|\(.ip)|\(.router)"' | \
        awk -F'|' -v pref="$network_prefix" '
            {
                h=$1; ip=$2; r=$3;
                if (h !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) next;
                split(ip,a,"."); p=a[1]"."a[2]"."a[3];
                pr=(pref!="" && p==pref) ? 0 : 1;
                if (!(h in best) || pr < best_pr[h]) { best[h]=$0; best_pr[h]=pr; }
            }
            END { for (h in best) print best[h]; }
        ' | sort)

    echo "$selected_hosts" | while IFS='|' read -r hostname ip router; do
        [[ -z "$hostname" || -z "$ip" ]] && continue
        echo "$ip    $hostname    # dot-hosts: $router" >> "$temp_hosts"
    done

    local host_count
    host_count=$(wc -l < "$temp_hosts" | tr -d ' ')

    if [[ "$dry_run" == true ]]; then
        echo "Dry run: Would add $host_count hosts to $hosts_file"
        echo ""
        echo "Entries that would be added:"
        echo "============================="
        cat "$temp_hosts"
        echo ""
        echo "To actually sync, run: dot-hosts sync"
        rm -f "$temp_hosts"
        return 0
    fi

    # Read existing /etc/hosts and clear previous managed section
    local temp_merged
    temp_merged=$(mktemp)
    local in_managed_section=false
    local begin_marker="# BEGIN dot-hosts managed entries"
    local end_marker="# END dot-hosts managed entries"

    # Clear any existing managed sections before adding new one
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$begin_marker" ]]; then
            in_managed_section=true
            # Skip this line and all lines until end marker
            continue
        fi

        if [[ "$line" == "$end_marker" ]]; then
            in_managed_section=false
            # Skip the end marker line
            continue
        fi

        # Only write lines that are not in a managed section
        if [[ "$in_managed_section" == false ]]; then
            echo "$line" >> "$temp_merged"
        fi
    done < "$hosts_file"

    # Add new managed section
    {
        echo "$begin_marker"
        cat "$temp_hosts"
        echo "$end_marker"
    } >> "$temp_merged"

    # Write back to /etc/hosts
    if sudo cp "$temp_merged" "$hosts_file"; then
        # Validate the written file
        if ! _dot-hosts-validate-file "$hosts_file"; then
            echo "Error: Hosts file validation failed after write" >&2
            if [[ -n "$backup_file" && -f "$backup_file" ]]; then
                echo "Restoring from backup: $backup_file" >&2
                if sudo cp "$backup_file" "$hosts_file"; then
                    echo "Backup restored successfully" >&2
                else
                    echo "Error: Failed to restore backup" >&2
                fi
            fi
            rm -f "$temp_hosts" "$temp_merged"
            return 1
        fi

        echo "Successfully synced $host_count hosts to $hosts_file"
        if [[ -n "$backup_file" ]]; then
            echo "Backup saved at: $backup_file"
        fi
    else
        echo "Error: Failed to write to $hosts_file" >&2
        rm -f "$temp_hosts" "$temp_merged"
        return 1
    fi

    rm -f "$temp_hosts" "$temp_merged"
}

# Clear subcommand
_dot-hosts-clear() {
    _dot-hosts-check-sudo || return 1

    local hosts_file="/etc/hosts"
    local backup_file
    if ! backup_file=$(_dot-hosts-backup-file); then
        return 1
    fi

    echo "Backup created: $backup_file"

    local begin_marker="# BEGIN dot-hosts managed entries"
    local end_marker="# END dot-hosts managed entries"
    local temp_cleaned
    temp_cleaned=$(mktemp)
    local in_managed_section=false
    local removed_count=0

    while IFS= read -r line; do
        if [[ "$line" == "$begin_marker" ]]; then
            in_managed_section=true
            removed_count=$((removed_count + 1))
            continue
        fi

        if [[ "$line" == "$end_marker" ]]; then
            in_managed_section=false
            removed_count=$((removed_count + 1))
            continue
        fi

        if [[ "$in_managed_section" == false ]]; then
            echo "$line" >> "$temp_cleaned"
        else
            removed_count=$((removed_count + 1))
        fi
    done < "$hosts_file"

    # Write back to /etc/hosts
    if sudo cp "$temp_cleaned" "$hosts_file"; then
        echo "Successfully removed $removed_count lines from $hosts_file"
        echo "Backup saved at: $backup_file"
    else
        echo "Error: Failed to write to $hosts_file" >&2
        rm -f "$temp_cleaned"
        return 1
    fi

    rm -f "$temp_cleaned"
}
