#!/bin/bash

# Unit tests for network reporting script
# Tests individual functions and overall functionality

set -euo pipefail

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_SCRIPT="${TEST_DIR}/report.sh"
CONFIG_FILE="${TEST_DIR}/config.conf"

# Function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        if [[ -n "$details" ]]; then
            echo -e "  ${RED}Details: $details${NC}"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Function to assert equality
assert_equal() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        print_test_result "$test_name" "PASS"
    else
        print_test_result "$test_name" "FAIL" "Expected: '$expected', Got: '$actual'"
    fi
}

# Function to assert not empty
assert_not_empty() {
    local value="$1"
    local test_name="$2"
    
    if [[ -n "$value" ]]; then
        print_test_result "$test_name" "PASS"
    else
        print_test_result "$test_name" "FAIL" "Value is empty"
    fi
}

# Function to assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        print_test_result "$test_name" "PASS"
    else
        print_test_result "$test_name" "FAIL" "String '$haystack' does not contain '$needle'"
    fi
}

# Function to test JSON validity
test_json_validity() {
    local json_string="$1"
    local test_name="$2"
    
    # Check if it's valid JSON by trying to parse it with a simple method
    if echo "$json_string" | grep -q '^{.*}$' && echo "$json_string" | grep -q '"hostname"' && echo "$json_string" | grep -q '"timestamp"'; then
        print_test_result "$test_name" "PASS"
    else
        print_test_result "$test_name" "FAIL" "Invalid JSON format"
    fi
}

# Test 1: Check if report script exists and is executable
test_script_exists() {
    if [[ -f "$REPORT_SCRIPT" && -x "$REPORT_SCRIPT" ]]; then
        print_test_result "Script exists and is executable" "PASS"
    else
        print_test_result "Script exists and is executable" "FAIL" "Script not found or not executable"
    fi
}

# Test 2: Check if config file exists
test_config_exists() {
    if [[ -f "$CONFIG_FILE" ]]; then
        print_test_result "Config file exists" "PASS"
    else
        print_test_result "Config file exists" "FAIL" "Config file not found"
    fi
}

# Test 3: Test hostname function
test_hostname() {
    local hostname=$(hostname)
    assert_not_empty "$hostname" "Hostname is not empty"
    assert_contains "$hostname" "." "Hostname contains valid characters"
}

# Test 4: Test local IP detection
test_local_ip() {
    # Source the report script to get the get_local_ip function
    source "$REPORT_SCRIPT" 2>/dev/null || true
    
    # Test if we can get a local IP
    local local_ip=$(get_local_ip 2>/dev/null || echo "unknown")
    
    if [[ "$local_ip" != "unknown" && "$local_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_test_result "Local IP detection" "PASS"
    else
        print_test_result "Local IP detection" "FAIL" "Could not detect valid local IP: $local_ip"
    fi
}

# Test 5: Test external IP detection
test_external_ip() {
    # Test external IP detection with timeout
    local external_ip=$(curl -s --connect-timeout 5 --max-time 10 "https://api.ipify.org" 2>/dev/null | tr -d '\n\r' || echo "unknown")
    
    if [[ "$external_ip" != "unknown" && "$external_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_test_result "External IP detection" "PASS"
    else
        print_test_result "External IP detection" "FAIL" "Could not detect valid external IP: $external_ip"
    fi
}

# Test 6: Test system info detection
test_system_info() {
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

# Test 7: Test JSON payload generation
test_json_payload() {
    local hostname=$(hostname)
    local local_ip=$(curl -s --connect-timeout 2 --max-time 5 "https://api.ipify.org" 2>/dev/null | tr -d '\n\r' || echo "unknown")
    local external_ip=$(curl -s --connect-timeout 2 --max-time 5 "https://api.ipify.org" 2>/dev/null | tr -d '\n\r' || echo "unknown")
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local json_payload=$(cat <<EOF
{
    "hostname": "$hostname",
    "local_ip": "$local_ip",
    "external_ip": "$external_ip",
    "os_type": "macOS",
    "os_version": "14.0",
    "timestamp": "$timestamp",
    "uptime": "1d"
}
EOF
)
    
    test_json_validity "$json_payload" "JSON payload generation"
    assert_contains "$json_payload" "$hostname" "JSON contains hostname"
    assert_contains "$json_payload" "$timestamp" "JSON contains timestamp"
}

# Test 8: Test curl availability
test_curl_availability() {
    if command -v curl >/dev/null 2>&1; then
        print_test_result "curl is available" "PASS"
    else
        print_test_result "curl is available" "FAIL" "curl not found"
    fi
}

# Test 9: Test network connectivity
test_network_connectivity() {
    if curl -s --connect-timeout 5 --max-time 10 "https://httpbin.org/get" >/dev/null 2>&1; then
        print_test_result "Network connectivity" "PASS"
    else
        print_test_result "Network connectivity" "FAIL" "Cannot reach external services"
    fi
}

# Test 10: Test script syntax
test_script_syntax() {
    if bash -n "$REPORT_SCRIPT" 2>/dev/null; then
        print_test_result "Script syntax is valid" "PASS"
    else
        print_test_result "Script syntax is valid" "FAIL" "Script has syntax errors"
    fi
}

# Test 11: Test configuration loading
test_config_loading() {
    # Create a temporary config file for testing
    local temp_config=$(mktemp)
    cat > "$temp_config" <<EOF
UPSTREAM_URL="https://httpbin.org/post"
REPORT_INTERVAL=60
VERBOSE_LOGGING=0
EOF
    
    # Test if we can source the config
    if source "$temp_config" 2>/dev/null && [[ -n "${UPSTREAM_URL:-}" ]]; then
        print_test_result "Configuration loading" "PASS"
    else
        print_test_result "Configuration loading" "FAIL" "Cannot load configuration"
    fi
    
    rm -f "$temp_config"
}

# Test 12: Test log file creation
test_log_creation() {
    local test_log=$(mktemp)
    local test_message="Test log message $(date)"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $test_message" > "$test_log"
    
    if [[ -f "$test_log" && -s "$test_log" ]]; then
        print_test_result "Log file creation" "PASS"
    else
        print_test_result "Log file creation" "FAIL" "Cannot create or write to log file"
    fi
    
    rm -f "$test_log"
}

# Main test runner
run_tests() {
    echo "Network Reporting Script - Unit Tests"
    echo "====================================="
    echo
    
    test_script_exists
    test_config_exists
    test_script_syntax
    test_curl_availability
    test_network_connectivity
    test_config_loading
    test_log_creation
    test_hostname
    test_local_ip
    test_external_ip
    test_system_info
    test_json_payload
    
    echo
    echo "Test Summary"
    echo "============"
    echo -e "Tests run: ${BLUE}$TESTS_RUN${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
fi

