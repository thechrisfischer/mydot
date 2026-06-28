#!/bin/bash

# Unit tests for script structure and dependencies
# Tests basic file structure, permissions, and dependencies

set -euo pipefail

# Source the test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_framework.sh"

# Test configuration
NETWORK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_SCRIPT="${NETWORK_DIR}/report.sh"
CONFIG_FILE="${NETWORK_DIR}/config.conf"
INSTALL_SCRIPT="${NETWORK_DIR}/install_functions.sh"

# Test functions
test_script_exists() {
    start_test_case "Script File Structure"
    
    assert_file_exists "$REPORT_SCRIPT" "Report script exists"
    assert_file_executable "$REPORT_SCRIPT" "Report script is executable"
    assert_file_exists "$CONFIG_FILE" "Config file exists"
    assert_file_exists "$INSTALL_SCRIPT" "Install script exists"
    assert_file_executable "$INSTALL_SCRIPT" "Install script is executable"
}

test_script_syntax() {
    start_test_case "Script Syntax Validation"
    
    # Test report script syntax
    if bash -n "$REPORT_SCRIPT" 2>/dev/null; then
        print_test_result "Report script syntax" "PASS"
    else
        print_test_result "Report script syntax" "FAIL" "Report script has syntax errors"
    fi
    
    # Test install script syntax
    if bash -n "$INSTALL_SCRIPT" 2>/dev/null; then
        print_test_result "Install script syntax" "PASS"
    else
        print_test_result "Install script syntax" "FAIL" "Install script has syntax errors"
    fi
}

test_dependencies() {
    start_test_case "System Dependencies"
    
    assert_command_exists "curl" "curl is available"
    assert_command_exists "hostname" "hostname command is available"
    assert_command_exists "crontab" "crontab is available"
    
    # Test ifconfig or ip command
    if command -v ifconfig >/dev/null 2>&1 || command -v ip >/dev/null 2>&1; then
        print_test_result "Network interface command available" "PASS"
    else
        print_test_result "Network interface command available" "FAIL" "Neither ifconfig nor ip command found"
    fi
}

test_config_loading() {
    start_test_case "Configuration Loading"
    
    # Test if config file can be sourced
    if source "$CONFIG_FILE" 2>/dev/null; then
        print_test_result "Config file can be sourced" "PASS"
    else
        print_test_result "Config file can be sourced" "FAIL" "Cannot source config file"
    fi
    
    # Test if UPSTREAM_URL is set
    source "$CONFIG_FILE" 2>/dev/null || true
    if [[ -n "${UPSTREAM_URL:-}" ]]; then
        print_test_result "UPSTREAM_URL is configured" "PASS"
    else
        print_test_result "UPSTREAM_URL is configured" "FAIL" "UPSTREAM_URL not set in config"
    fi
}

# Main test runner
main() {
    start_test_suite "Script Structure Tests"
    
    test_script_exists
    test_script_syntax
    test_dependencies
    test_config_loading
    
    print_test_summary
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
