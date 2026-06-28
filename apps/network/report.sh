#!/bin/bash

# Network host reporting script
# Gathers host information and sends it to configured upstream service

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"
LOG_FILE="${SCRIPT_DIR}/network-report.log"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Error: Configuration file not found at $CONFIG_FILE"
    echo "Please run the install script first to set up configuration."
    exit 1
fi

# Check if upstream URL is configured
if [[ -z "${UPSTREAM_URL:-}" ]]; then
    echo "Error: UPSTREAM_URL not configured in $CONFIG_FILE"
    exit 1
fi

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to get local IP address
get_local_ip() {
    # Try different methods to get local IP
    local ip=""
    
    # Method 1: route to default gateway
    if command -v route >/dev/null 2>&1; then
        ip=$(route get default 2>/dev/null | grep interface | awk '{print $2}' | xargs ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
    fi
    
    # Method 2: ifconfig (fallback)
    if [[ -z "$ip" ]] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
    fi
    
    # Method 3: ip command (Linux)
    if [[ -z "$ip" ]] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    fi
    
    echo "${ip:-unknown}"
}

# Function to get external IP address
get_external_ip() {
    # Try multiple services for reliability
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
    )
    
    for service in "${services[@]}"; do
        if command -v curl >/dev/null 2>&1; then
            local ip=$(curl -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | tr -d '\n\r' | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
            if [[ -n "$ip" ]]; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    echo "unknown"
}

# Function to get system information
get_system_info() {
    local os_type=""
    local os_version=""
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macOS"
        os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="Linux"
        if [[ -f /etc/os-release ]]; then
            os_version=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "unknown")
        elif command -v lsb_release >/dev/null 2>&1; then
            os_version=$(lsb_release -d 2>/dev/null | cut -f2 || echo "unknown")
        else
            os_version=$(uname -r)
        fi
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        os_type="FreeBSD"
        os_version=$(freebsd-version 2>/dev/null || uname -r)
    else
        os_type="Unix"
        os_version=$(uname -r)
    fi
    
    echo "$os_type|$os_version"
}

# Main function
main() {
    log "Starting network host report"
    
    # Gather host information
    local hostname=$(hostname)
    local local_ip=$(get_local_ip)
    local external_ip=$(get_external_ip)
    local system_info=$(get_system_info)
    local os_type=$(echo "$system_info" | cut -d'|' -f1)
    local os_version=$(echo "$system_info" | cut -d'|' -f2)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Create JSON payload
    local json_payload=$(cat <<EOF
{
    "hostname": "$hostname",
    "local_ip": "$local_ip",
    "external_ip": "$external_ip",
    "os_type": "$os_type",
    "os_version": "$os_version",
    "timestamp": "$timestamp",
    "uptime": $(uptime | awk '{print $3}' | sed 's/,//' || echo "null")
}
EOF
)
    
    log "Host information gathered:"
    log "  Hostname: $hostname"
    log "  Local IP: $local_ip"
    log "  External IP: $external_ip"
    log "  OS: $os_type $os_version"
    
    # Send to upstream service
    if command -v curl >/dev/null 2>&1; then
        log "Sending data to upstream service: $UPSTREAM_URL"
        
        local response=$(curl -s -w "\n%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -d "$json_payload" \
            --connect-timeout 10 \
            --max-time 30 \
            "$UPSTREAM_URL" 2>&1)
        
        local http_code=$(echo "$response" | tail -1)
        local response_body=$(echo "$response" | head -n -1)
        
        if [[ "$http_code" =~ ^[2-3][0-9][0-9]$ ]]; then
            log "Successfully sent data to upstream service (HTTP $http_code)"
            if [[ -n "$response_body" ]]; then
                log "Response: $response_body"
            fi
        else
            log "Failed to send data to upstream service (HTTP $http_code)"
            log "Response: $response_body"
            exit 1
        fi
    else
        log "Error: curl not found. Cannot send data to upstream service."
        exit 1
    fi
    
    log "Network host report completed successfully"
}

# Run main function
main "$@"

