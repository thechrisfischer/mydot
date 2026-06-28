#!/bin/bash

# Integration tests for end-to-end functionality
# Tests the complete workflow from data gathering to HTTP transmission

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_framework.sh"

# Test configuration
NETWORK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_SCRIPT="${NETWORK_DIR}/report.sh"
CONFIG_FILE="${NETWORK_DIR}/config.conf"
LOG_FILE="${NETWORK_DIR}/network-report.log"

# Test functions
test_script_execution() {
    start_test_case "Script Execution Test"
    
    # Backup original config
    local config_backup=$(mktemp)
    cp "$CONFIG_FILE" "$config_backup"
    
    # Set test configuration
    cat > "$CONFIG_FILE" <<EOF
UPSTREAM_URL="https://httpbin.org/post"
REPORT_INTERVAL=60
VERBOSE_LOGGING=0
EOF
    
    # Run the script
    if "$REPORT_SCRIPT" >/dev/null 2>&1; then
        print_test_result "Script execution successful" "PASS"
    else
        print_test_result "Script execution successful" "FAIL" "Script execution failed"
    fi
    
    # Restore original config
    cp "$config_backup" "$CONFIG_FILE"
    rm -f "$config_backup"
}

test_log_file_creation() {
    start_test_case "Log File Creation"
    
    # Check if log file exists and has content
    if [[ -f "$LOG_FILE" && -s "$LOG_FILE" ]]; then
        print_test_result "Log file exists and has content" "PASS"
    else
        print_test_result "Log file exists and has content" "FAIL" "Log file missing or empty"
    fi
    
    # Check log file format
    if grep -q "Starting network host report" "$LOG_FILE" 2>/dev/null; then
        print_test_result "Log file contains expected entries" "PASS"
    else
        print_test_result "Log file contains expected entries" "FAIL" "Log file missing expected entries"
    fi
}

test_http_transmission() {
    start_test_case "HTTP Transmission Test"
    
    # Test with a simple HTTP endpoint
    local test_url="https://httpbin.org/post"
    local test_data='{"test": "data"}'
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$test_data" \
        --connect-timeout 10 \
        --max-time 30 \
        "$test_url" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" =~ ^[2-3][0-9][0-9]$ ]]; then
        print_test_result "HTTP transmission successful" "PASS"
    else
        print_test_result "HTTP transmission successful" "FAIL" "HTTP request failed with code $http_code"
    fi
}

test_data_validation() {
    start_test_case "Data Validation Test"
    
    # Extract data from log file
    local hostname=$(grep "Hostname:" "$LOG_FILE" 2>/dev/null | tail -1 | awk '{print $2}' || echo "")
    local local_ip=$(grep "Local IP:" "$LOG_FILE" 2>/dev/null | tail -1 | awk '{print $3}' || echo "")
    local external_ip=$(grep "External IP:" "$LOG_FILE" 2>/dev/null | tail -1 | awk '{print $3}' || echo "")
    local os_info=$(grep "OS:" "$LOG_FILE" 2>/dev/null | tail -1 | awk '{print $2, $3}' || echo "")
    
    # Validate extracted data
    assert_not_empty "$hostname" "Hostname extracted from logs"
    assert_not_empty "$local_ip" "Local IP extracted from logs"
    assert_not_empty "$external_ip" "External IP extracted from logs"
    assert_not_empty "$os_info" "OS info extracted from logs"
    
    # Validate IP formats
    if [[ -n "$local_ip" ]]; then
        assert_ip_format "$local_ip" "Local IP format validation"
    fi
    
    if [[ -n "$external_ip" ]]; then
        assert_ip_format "$external_ip" "External IP format validation"
    fi
}

test_error_handling() {
    start_test_case "Error Handling Test"
    
    # Test with invalid URL
    local config_backup=$(mktemp)
    cp "$CONFIG_FILE" "$config_backup"
    
    cat > "$CONFIG_FILE" <<EOF
UPSTREAM_URL="https://invalid-url-that-does-not-exist.com/post"
REPORT_INTERVAL=60
VERBOSE_LOGGING=0
EOF
    
    # Run script and check for error handling
    if "$REPORT_SCRIPT" >/dev/null 2>&1; then
        print_test_result "Error handling with invalid URL" "FAIL" "Script should fail with invalid URL"
    else
        print_test_result "Error handling with invalid URL" "PASS"
    fi
    
    # Restore original config
    cp "$config_backup" "$CONFIG_FILE"
    rm -f "$config_backup"
}

test_performance() {
    start_test_case "Performance Test"
    
    # Test script execution time
    local start_time=$(date +%s)
    
    if "$REPORT_SCRIPT" >/dev/null 2>&1; then
        local end_time=$(date +%s)
        local execution_time=$((end_time - start_time))
        
        if [[ $execution_time -lt 30 ]]; then
            print_test_result "Script execution time < 30s" "PASS"
        else
            print_test_result "Script execution time < 30s" "FAIL" "Script took ${execution_time}s to execute"
        fi
    else
        print_test_result "Script execution time < 30s" "FAIL" "Script execution failed"
    fi
}

# Main test runner
main() {
    start_test_suite "End-to-End Integration Tests"
    
    test_script_execution
    test_log_file_creation
    test_http_transmission
    test_data_validation
    test_error_handling
    test_performance
    
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

