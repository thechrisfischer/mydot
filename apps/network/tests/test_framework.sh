#!/bin/bash

# Test Framework for Network Host Reporting
# Provides common testing utilities and assertions

set -euo pipefail

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters. Keep this compatible with macOS /bin/bash 3.2.
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_SUITE=""
TEST_CASE=""

# Test results storage
TEST_RESULTS=()

# Function to start a test suite
start_test_suite() {
    local suite_name="$1"
    TEST_SUITE="$suite_name"
    echo -e "\n${CYAN}Running Test Suite: $suite_name${NC}"
    echo "=================================================="
}

# Function to start a test case
start_test_case() {
    local case_name="$1"
    TEST_CASE="$case_name"
    echo -e "\n${BLUE}Test Case: $case_name${NC}"
    echo "----------------------------------------"
}

# Function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$result" == "PASS" ]]; then
        echo -e "  ${GREEN}✓${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TEST_RESULTS+=("PASS:$test_name")
    else
        echo -e "  ${RED}✗${NC} $test_name"
        if [[ -n "$details" ]]; then
            echo -e "    ${RED}Details: $details${NC}"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TEST_RESULTS+=("FAIL:$test_name:$details")
    fi
}

# Function to assert equality
assert_equal() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "Expected: '$expected', Got: '$actual'"
        return 0
    fi
}

# Function to assert not empty
assert_not_empty() {
    local value="$1"
    local test_name="$2"
    
    if [[ -n "$value" ]]; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "Value is empty"
        return 0
    fi
}

# Function to assert contains
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "String '$haystack' does not contain '$needle'"
        return 0
    fi
}

# Function to assert file exists
assert_file_exists() {
    local file_path="$1"
    local test_name="$2"
    
    if [[ -f "$file_path" ]]; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "File does not exist: $file_path"
        return 0
    fi
}

# Function to assert file is executable
assert_file_executable() {
    local file_path="$1"
    local test_name="$2"
    
    if [[ -f "$file_path" && -x "$file_path" ]]; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "File is not executable: $file_path"
        return 0
    fi
}

# Function to assert command exists
assert_command_exists() {
    local command="$1"
    local test_name="$2"
    
    if command -v "$command" >/dev/null 2>&1; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "Command not found: $command"
        return 0
    fi
}

# Function to assert JSON validity
assert_json_valid() {
    local json_string="$1"
    local test_name="$2"
    
    if command -v jq >/dev/null 2>&1; then
        if printf '%s\n' "$json_string" | jq empty >/dev/null 2>&1; then
            print_test_result "$test_name" "PASS"
            return 0
        fi
        print_test_result "$test_name" "FAIL" "Invalid JSON format"
        return 0
    fi

    # Fallback when jq is unavailable: normalize multiline payloads and check
    # for object delimiters plus expected fields.
    local compact_json
    compact_json=$(printf '%s\n' "$json_string" | tr -d '\n\r')
    if echo "$compact_json" | grep -q '^{.*}$' && echo "$compact_json" | grep -q '"hostname"' && echo "$compact_json" | grep -q '"timestamp"'; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "Invalid JSON format"
        return 0
    fi
}

# Function to assert HTTP response
assert_http_response() {
    local url="$1"
    local expected_code="$2"
    local test_name="$3"
    
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")
    
    if [[ "$response_code" == "$expected_code" ]]; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "Expected HTTP $expected_code, got $response_code"
        return 0
    fi
}

_is_ipv4() {
    local ip="$1"
    local IFS=.
    local o1 o2 o3 o4 extra

    [[ "$ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
    read -r o1 o2 o3 o4 extra <<< "$ip"
    [[ -z "${extra:-}" ]] || return 1
    for octet in "$o1" "$o2" "$o3" "$o4"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        [[ "$octet" -ge 0 && "$octet" -le 255 ]] || return 1
    done
}

# Function to assert IP format
assert_ip_format() {
    local ip="$1"
    local test_name="$2"
    
    if _is_ipv4 "$ip"; then
        print_test_result "$test_name" "PASS"
        return 0
    else
        print_test_result "$test_name" "FAIL" "Invalid IP format: $ip"
        return 0
    fi
}

# Function to run a test function
run_test() {
    local test_function="$1"
    local test_name="${2:-$test_function}"
    
    if "$test_function"; then
        return 0
    else
        return 1
    fi
}

# Function to print test summary
print_test_summary() {
    echo
    echo "Test Summary"
    echo "============"
    echo -e "Tests run: ${BLUE}$TESTS_RUN${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo
        echo "Failed Tests:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL:* ]]; then
                local test_name=$(echo "$result" | cut -d':' -f2)
                local details=$(echo "$result" | cut -d':' -f3-)
                echo -e "  ${RED}✗${NC} $test_name"
                if [[ -n "$details" ]]; then
                    echo -e "    ${RED}$details${NC}"
                fi
            fi
        done
    fi
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Function to reset test counters
reset_test_counters() {
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TEST_RESULTS=()
}

# Function to run tests with timeout
run_with_timeout() {
    local timeout_seconds="$1"
    local command="$2"
    
    timeout "$timeout_seconds" bash -c "$command" 2>/dev/null || {
        if [[ $? -eq 124 ]]; then
            echo "Test timed out after ${timeout_seconds}s"
            return 1
        else
            return $?
        fi
    }
}

# Export functions for use in test files
export -f start_test_suite start_test_case print_test_result
export -f assert_equal assert_not_empty assert_contains assert_file_exists
export -f assert_file_executable assert_command_exists assert_json_valid
export -f assert_http_response _is_ipv4 assert_ip_format run_test print_test_summary
export -f reset_test_counters run_with_timeout
