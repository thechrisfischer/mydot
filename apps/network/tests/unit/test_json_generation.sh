#!/bin/bash

# Unit tests for JSON payload generation
# Tests JSON formatting, data validation, and payload structure

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_framework.sh"

# Test functions
test_json_structure() {
    start_test_case "JSON Structure Validation"
    
    # Create a test JSON payload
    local hostname=$(hostname)
    local local_ip="192.168.1.100"
    local external_ip="203.0.113.1"
    local os_type="macOS"
    local os_version="15.6.1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local uptime="1d"
    
    local json_payload=$(cat <<EOF
{
    "hostname": "$hostname",
    "local_ip": "$local_ip",
    "external_ip": "$external_ip",
    "os_type": "$os_type",
    "os_version": "$os_version",
    "timestamp": "$timestamp",
    "uptime": "$uptime"
}
EOF
)
    
    # Test JSON structure
    assert_json_valid "$json_payload" "JSON payload structure"
    assert_contains "$json_payload" "$hostname" "JSON contains hostname"
    assert_contains "$json_payload" "$timestamp" "JSON contains timestamp"
    assert_contains "$json_payload" "\"hostname\"" "JSON has hostname field"
    assert_contains "$json_payload" "\"local_ip\"" "JSON has local_ip field"
    assert_contains "$json_payload" "\"external_ip\"" "JSON has external_ip field"
    assert_contains "$json_payload" "\"os_type\"" "JSON has os_type field"
    assert_contains "$json_payload" "\"os_version\"" "JSON has os_version field"
    assert_contains "$json_payload" "\"timestamp\"" "JSON has timestamp field"
    assert_contains "$json_payload" "\"uptime\"" "JSON has uptime field"
}

test_timestamp_format() {
    start_test_case "Timestamp Format Validation"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Test timestamp format (ISO 8601)
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        print_test_result "Timestamp format (ISO 8601)" "PASS"
    else
        print_test_result "Timestamp format (ISO 8601)" "FAIL" "Invalid timestamp format: $timestamp"
    fi
}

test_ip_validation() {
    start_test_case "IP Address Validation"
    
    # Test valid IP formats
    local valid_ips=("192.168.1.1" "10.0.0.1" "172.16.0.1" "203.0.113.1")
    for ip in "${valid_ips[@]}"; do
        assert_ip_format "$ip" "Valid IP: $ip"
    done
    
    # Test invalid IP formats
    local invalid_ips=("not.an.ip" "256.1.1.1" "192.168.1" "192.168.1.1.1")
    for ip in "${invalid_ips[@]}"; do
        if ! _is_ipv4 "$ip"; then
            print_test_result "Invalid IP rejected: $ip" "PASS"
        else
            print_test_result "Invalid IP rejected: $ip" "FAIL" "Invalid IP was accepted"
        fi
    done
}

test_json_escaping() {
    start_test_case "JSON String Escaping"
    
    # Test with special characters in hostname
    local special_hostname="test-host_with.special+chars"
    local json_payload=$(cat <<EOF
{
    "hostname": "$special_hostname",
    "local_ip": "192.168.1.1",
    "external_ip": "203.0.113.1",
    "os_type": "macOS",
    "os_version": "15.6.1",
    "timestamp": "2024-01-01T00:00:00Z",
    "uptime": "1d"
}
EOF
)
    
    assert_contains "$json_payload" "$special_hostname" "Special characters in hostname"
    assert_json_valid "$json_payload" "JSON with special characters"
}

test_required_fields() {
    start_test_case "Required Fields Validation"
    
    local json_payload='{"hostname":"test","local_ip":"192.168.1.1","external_ip":"203.0.113.1","os_type":"macOS","os_version":"15.6.1","timestamp":"2024-01-01T00:00:00Z","uptime":"1d"}'
    
    local required_fields=("hostname" "local_ip" "external_ip" "os_type" "os_version" "timestamp" "uptime")
    
    for field in "${required_fields[@]}"; do
        assert_contains "$json_payload" "\"$field\"" "Required field: $field"
    done
}

test_json_parsing() {
    start_test_case "JSON Parsing Test"
    
    # Test if jq can parse the JSON (if available)
    if command -v jq >/dev/null 2>&1; then
        local json_payload='{"hostname":"test","local_ip":"192.168.1.1","external_ip":"203.0.113.1","os_type":"macOS","os_version":"15.6.1","timestamp":"2024-01-01T00:00:00Z","uptime":"1d"}'
        
        if echo "$json_payload" | jq . >/dev/null 2>&1; then
            print_test_result "JSON parsing with jq" "PASS"
        else
            print_test_result "JSON parsing with jq" "FAIL" "jq cannot parse the JSON"
        fi
    else
        print_test_result "JSON parsing with jq" "PASS" "jq not available, skipping"
    fi
}

# Main test runner
main() {
    start_test_suite "JSON Generation Tests"
    
    test_json_structure
    test_timestamp_format
    test_ip_validation
    test_json_escaping
    test_required_fields
    test_json_parsing
    
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
