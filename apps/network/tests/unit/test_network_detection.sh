#!/bin/bash

# Unit tests for network detection functionality
# Tests IP detection, hostname, and system information gathering

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_framework.sh"

# Test functions
test_hostname_detection() {
    start_test_case "Hostname Detection"
    
    local hostname=$(hostname)
    assert_not_empty "$hostname" "Hostname is not empty"
    if [[ "$hostname" =~ ^[A-Za-z0-9._-]+$ ]]; then
        print_test_result "Hostname contains valid characters" "PASS"
    else
        print_test_result "Hostname contains valid characters" "FAIL" "Invalid hostname characters: $hostname"
    fi
}

test_local_ip_detection() {
    start_test_case "Local IP Detection"
    
    # Test different methods of local IP detection
    local local_ip=""
    
    # Method 1: ifconfig
    if command -v ifconfig >/dev/null 2>&1; then
        local_ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' 2>/dev/null || echo "")
        if [[ -n "$local_ip" ]]; then
            assert_ip_format "$local_ip" "Local IP via ifconfig"
        fi
    fi
    
    # Method 2: ip command (Linux)
    if command -v ip >/dev/null 2>&1; then
        local_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1 2>/dev/null || echo "")
        if [[ -n "$local_ip" ]]; then
            assert_ip_format "$local_ip" "Local IP via ip command"
        fi
    fi
    
    # At least one method should work
    if [[ -n "$local_ip" ]]; then
        print_test_result "Local IP detection successful" "PASS"
    else
        print_test_result "Local IP detection successful" "FAIL" "Could not detect local IP with any method"
    fi
}

test_external_ip_detection() {
    start_test_case "External IP Detection"
    
    # Test external IP detection with timeout
    local external_ip=$(curl -s --connect-timeout 5 --max-time 10 "https://api.ipify.org" 2>/dev/null | tr -d '\n\r' || echo "unknown")
    
    if [[ "$external_ip" != "unknown" ]]; then
        assert_ip_format "$external_ip" "External IP format"
        print_test_result "External IP detection" "PASS"
    else
        print_test_result "External IP detection" "FAIL" "Could not detect external IP"
    fi
}

test_system_info_detection() {
    start_test_case "System Information Detection"
    
    local os_type=""
    local os_version=""
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macOS"
        os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="Linux"
        if [[ -f /etc/os-release ]]; then
            os_version=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2 2>/dev/null || echo "unknown")
        else
            os_version=$(uname -r)
        fi
    else
        os_type="Unix"
        os_version=$(uname -r)
    fi
    
    assert_not_empty "$os_type" "OS type detection"
    assert_not_empty "$os_version" "OS version detection"
}

test_network_connectivity() {
    start_test_case "Network Connectivity"
    
    # Test basic connectivity
    assert_http_response "https://httpbin.org/get" "200" "HTTP connectivity test"
    
    # Test external IP services
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
    )
    
    local working_services=0
    for service in "${services[@]}"; do
        if curl -s --connect-timeout 3 --max-time 5 "$service" >/dev/null 2>&1; then
            working_services=$((working_services + 1))
        fi
    done
    
    if [[ $working_services -gt 0 ]]; then
        print_test_result "External IP services accessible" "PASS"
    else
        print_test_result "External IP services accessible" "FAIL" "No external IP services accessible"
    fi
}

# Main test runner
main() {
    start_test_suite "Network Detection Tests"
    
    test_hostname_detection
    test_local_ip_detection
    test_external_ip_detection
    test_system_info_detection
    test_network_connectivity
    
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
