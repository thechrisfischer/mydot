#!/bin/bash

# Network Host Reporting - Installation Functions
# Functions to be sourced by the main dotfiles install script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the network app directory
NETWORK_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to check if network reporting is enabled
is_network_reporting_enabled() {
    local install_flags="$1"
    
    # Check if network tools are explicitly requested or if "all" is specified
    if [[ "$install_flags" == *"network"* ]] || [[ "$install_flags" == *"all"* ]]; then
        return 0
    fi
    
    return 1
}

# Function to detect platform and return appropriate installation method
detect_platform() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        echo "freebsd"
    else
        echo "unix"
    fi
}

# Function to check dependencies
check_network_dependencies() {
    local missing_deps=()
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    if ! command -v crontab >/dev/null 2>&1; then
        missing_deps+=("cron")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warning: Missing dependencies for network reporting: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}Please install them manually or they will be skipped.${NC}"
        return 1
    fi
    
    return 0
}

# Function to configure network reporting
configure_network_reporting() {
    local config_file="${NETWORK_APP_DIR}/config.conf"
    
    echo -e "${BLUE}Configuring Network Host Reporting...${NC}"
    
    # Check if already configured
    if [[ -f "$config_file" ]] && grep -q '^UPSTREAM_URL=' "$config_file" && [[ -n "$(grep '^UPSTREAM_URL=' "$config_file" | cut -d'=' -f2 | tr -d '"')" ]]; then
        echo -e "${GREEN}Network reporting already configured.${NC}"
        return 0
    fi
    
    # Set default configuration
    cat > "$config_file" <<EOF
# Network host reporting configuration
# Edit this file to configure the upstream service URL and reporting interval

# Upstream service URL - configure this to point to your data collection endpoint
# Example: UPSTREAM_URL="https://your-service.com/api/host-report"
UPSTREAM_URL=""

# Reporting interval in minutes (default: 60 minutes)
# Set to 0 to disable automatic reporting
REPORT_INTERVAL=60

# Additional configuration options
# Set to 1 to enable verbose logging
VERBOSE_LOGGING=0

# Set to 1 to include additional system information
INCLUDE_EXTRA_INFO=0
EOF
    
    echo -e "${YELLOW}Network reporting configured with default settings.${NC}"
    echo -e "${YELLOW}Please edit ${config_file} to set your upstream service URL.${NC}"
}

# Function to install cron job (macOS/Linux)
install_network_cron() {
    local platform="$1"
    local report_script="${NETWORK_APP_DIR}/report.sh"
    
    echo -e "${BLUE}Installing network reporting cron job...${NC}"
    
    # Make sure script is executable
    chmod +x "$report_script"
    
    # Create cron entry
    local cron_entry="*/60 * * * * ${report_script} >> ${NETWORK_APP_DIR}/network-report.log 2>&1"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "$report_script"; then
        echo -e "${YELLOW}Network reporting cron job already exists.${NC}"
        return 0
    fi
    
    # Add cron job
    (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
    
    echo -e "${GREEN}Network reporting cron job installed.${NC}"
}

# Function to install systemd service (Linux)
install_network_systemd() {
    local report_script="${NETWORK_APP_DIR}/report.sh"
    local service_file="/etc/systemd/system/network-reporting.service"
    
    echo -e "${BLUE}Installing network reporting systemd service...${NC}"
    
    # Make sure script is executable
    chmod +x "$report_script"
    
    # Create systemd service file
    sudo tee "$service_file" > /dev/null <<EOF
[Unit]
Description=Network Host Reporting Service
After=network.target

[Service]
Type=oneshot
ExecStart=${report_script}
User=${USER}
WorkingDirectory=${NETWORK_APP_DIR}

[Timer]
OnCalendar=*:0/60
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Create timer file
    sudo tee "/etc/systemd/system/network-reporting.timer" > /dev/null <<EOF
[Unit]
Description=Network Host Reporting Timer
Requires=network-reporting.service

[Timer]
OnCalendar=*:0/60
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start the timer
    sudo systemctl daemon-reload
    sudo systemctl enable network-reporting.timer
    sudo systemctl start network-reporting.timer
    
    echo -e "${GREEN}Network reporting systemd service installed.${NC}"
}

# Function to install launchd service (macOS)
install_network_launchd() {
    local report_script="${NETWORK_APP_DIR}/report.sh"
    local plist_file="${HOME}/Library/LaunchAgents/com.dotfiles.network-reporting.plist"
    
    echo -e "${BLUE}Installing network reporting launchd service...${NC}"
    
    # Make sure script is executable
    chmod +x "$report_script"
    
    # Create launchd plist file
    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dotfiles.network-reporting</string>
    <key>ProgramArguments</key>
    <array>
        <string>${report_script}</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${NETWORK_APP_DIR}/network-report.log</string>
    <key>StandardErrorPath</key>
    <string>${NETWORK_APP_DIR}/network-report.log</string>
</dict>
</plist>
EOF
    
    # Load the service
    launchctl load "$plist_file"
    
    echo -e "${GREEN}Network reporting launchd service installed.${NC}"
}

# Function to test network reporting
test_network_reporting() {
    local report_script="${NETWORK_APP_DIR}/report.sh"
    
    echo -e "${BLUE}Testing network reporting...${NC}"
    
    if [[ -f "$report_script" && -x "$report_script" ]]; then
        # Test with a safe endpoint
        local config_backup=$(mktemp)
        cp "${NETWORK_APP_DIR}/config.conf" "$config_backup"
        
        # Set test configuration
        cat > "${NETWORK_APP_DIR}/config.conf" <<EOF
UPSTREAM_URL="https://httpbin.org/post"
REPORT_INTERVAL=60
VERBOSE_LOGGING=0
EOF
        
        # Run test
        if "$report_script" >/dev/null 2>&1; then
            echo -e "${GREEN}Network reporting test successful.${NC}"
        else
            echo -e "${YELLOW}Network reporting test failed (this may be expected if no upstream URL is configured).${NC}"
        fi
        
        # Restore original config
        cp "$config_backup" "${NETWORK_APP_DIR}/config.conf"
        rm -f "$config_backup"
    else
        echo -e "${RED}Network reporting script not found or not executable.${NC}"
        return 1
    fi
}

# Main installation function
install_network_reporting() {
    local install_flags="$1"
    
    # Check if network reporting should be installed
    if ! is_network_reporting_enabled "$install_flags"; then
        return 0
    fi
    
    echo -e "\n${BLUE}Installing Network Host Reporting...${NC}"
    echo "====================================="
    
    # Check dependencies
    if ! check_network_dependencies; then
        echo -e "${YELLOW}Skipping network reporting due to missing dependencies.${NC}"
        return 1
    fi
    
    # Configure the application
    configure_network_reporting
    
    # Detect platform and install appropriate service
    local platform=$(detect_platform)
    
    case "$platform" in
        "macos")
            install_network_launchd
            ;;
        "linux")
            # Try systemd first, fall back to cron
            if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
                install_network_systemd
            else
                install_network_cron
            fi
            ;;
        "freebsd"|"unix")
            install_network_cron
            ;;
        *)
            echo -e "${YELLOW}Unknown platform: $platform, using cron fallback${NC}"
            install_network_cron
            ;;
    esac
    
    # Test the installation
    test_network_reporting
    
    echo -e "${GREEN}Network Host Reporting installation completed.${NC}"
    echo -e "${YELLOW}Remember to configure your upstream service URL in ${NETWORK_APP_DIR}/config.conf${NC}"
}

# Function to uninstall network reporting
uninstall_network_reporting() {
    local platform=$(detect_platform)
    
    echo -e "${BLUE}Uninstalling Network Host Reporting...${NC}"
    
    case "$platform" in
        "macos")
            # Remove launchd service
            local plist_file="${HOME}/Library/LaunchAgents/com.dotfiles.network-reporting.plist"
            if [[ -f "$plist_file" ]]; then
                launchctl unload "$plist_file" 2>/dev/null || true
                rm -f "$plist_file"
                echo -e "${GREEN}Launchd service removed.${NC}"
            fi
            ;;
        "linux")
            # Remove systemd service
            if systemctl is-enabled network-reporting.timer >/dev/null 2>&1; then
                sudo systemctl stop network-reporting.timer 2>/dev/null || true
                sudo systemctl disable network-reporting.timer 2>/dev/null || true
                sudo rm -f /etc/systemd/system/network-reporting.service
                sudo rm -f /etc/systemd/system/network-reporting.timer
                sudo systemctl daemon-reload
                echo -e "${GREEN}Systemd service removed.${NC}"
            fi
            ;;
    esac
    
    # Remove cron job (fallback for all platforms)
    if crontab -l 2>/dev/null | grep -q "${NETWORK_APP_DIR}/report.sh"; then
        crontab -l 2>/dev/null | grep -v "${NETWORK_APP_DIR}/report.sh" | crontab -
        echo -e "${GREEN}Cron job removed.${NC}"
    fi
    
    echo -e "${GREEN}Network Host Reporting uninstalled.${NC}"
}

# Export functions for use by main install script
export -f is_network_reporting_enabled
export -f detect_platform
export -f check_network_dependencies
export -f configure_network_reporting
export -f install_network_cron
export -f install_network_systemd
export -f install_network_launchd
export -f test_network_reporting
export -f install_network_reporting
export -f uninstall_network_reporting

