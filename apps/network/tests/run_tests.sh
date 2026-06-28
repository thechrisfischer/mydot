#!/bin/bash

# Main test runner for Network Host Reporting
# Runs all test suites and provides comprehensive reporting

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test counters
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
FAILED_SUITES=()

# Function to print header
print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                Network Host Reporting - Test Suite          ║"
    echo "║                                                              ║"
    echo "║  Running comprehensive tests for network reporting system   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Function to run a test suite
run_test_suite() {
    local suite_name="$1"
    local test_script="$2"
    
    echo -e "\n${BLUE}Running Test Suite: $suite_name${NC}"
    echo "=================================================="
    
    if [[ -f "$test_script" && -x "$test_script" ]]; then
        # Capture test results
        local suite_output
        local suite_exit_code
        
        set +e
        suite_output=$("$test_script" 2>&1)
        suite_exit_code=$?
        set -e
        
        # Extract test counts from output
        local clean_output tests_run tests_passed tests_failed
        clean_output=$(printf '%s\n' "$suite_output" | sed $'s/\033\\[[0-9;]*m//g')
        tests_run=$(echo "$clean_output" | awk '/Tests run:/ {print $3}' | tail -1)
        tests_passed=$(echo "$clean_output" | awk '/Passed:/ {print $2}' | tail -1)
        tests_failed=$(echo "$clean_output" | awk '/Failed:/ {print $2}' | tail -1)
        tests_run="${tests_run:-0}"
        tests_passed="${tests_passed:-0}"
        tests_failed="${tests_failed:-0}"
        
        # Update totals
        TOTAL_TESTS=$((TOTAL_TESTS + tests_run))
        TOTAL_PASSED=$((TOTAL_PASSED + tests_passed))
        TOTAL_FAILED=$((TOTAL_FAILED + tests_failed))
        
        # Display results
        echo "$suite_output"
        
        if [[ $suite_exit_code -ne 0 ]]; then
            FAILED_SUITES+=("$suite_name")
            echo -e "${RED}❌ Test suite failed${NC}"
        else
            echo -e "${GREEN}✅ Test suite passed${NC}"
        fi
    else
        echo -e "${RED}❌ Test script not found or not executable: $test_script${NC}"
        FAILED_SUITES+=("$suite_name")
    fi
}

# Function to run all unit tests
run_unit_tests() {
    echo -e "\n${YELLOW}UNIT TESTS${NC}"
    echo "=========="
    
    # Script structure tests
    run_test_suite "Script Structure" "${SCRIPT_DIR}/unit/test_script_structure.sh"
    
    # Network detection tests
    run_test_suite "Network Detection" "${SCRIPT_DIR}/unit/test_network_detection.sh"
    
    # JSON generation tests
    run_test_suite "JSON Generation" "${SCRIPT_DIR}/unit/test_json_generation.sh"
}

# Function to run all integration tests
run_integration_tests() {
    echo -e "\n${YELLOW}INTEGRATION TESTS${NC}"
    echo "=================="
    
    # End-to-end tests
    run_test_suite "End-to-End Integration" "${SCRIPT_DIR}/integration/test_end_to_end.sh"
}

# Function to run quick tests
run_quick_tests() {
    echo -e "\n${YELLOW}QUICK TESTS${NC}"
    echo "============"
    
    # Just run the most critical tests
    run_test_suite "Script Structure" "${SCRIPT_DIR}/unit/test_script_structure.sh"
}

# Function to run specific test
run_specific_test() {
    local test_name="$1"
    
    case "$test_name" in
        "structure"|"script")
            run_test_suite "Script Structure" "${SCRIPT_DIR}/unit/test_script_structure.sh"
            ;;
        "network"|"detection")
            run_test_suite "Network Detection" "${SCRIPT_DIR}/unit/test_network_detection.sh"
            ;;
        "json")
            run_test_suite "JSON Generation" "${SCRIPT_DIR}/unit/test_json_generation.sh"
            ;;
        "integration"|"e2e")
            run_test_suite "End-to-End Integration" "${SCRIPT_DIR}/integration/test_end_to_end.sh"
            ;;
        *)
            echo -e "${RED}Unknown test: $test_name${NC}"
            echo "Available tests: structure, network, json, integration"
            exit 1
            ;;
    esac
}

# Function to print final summary
print_final_summary() {
    echo -e "\n${CYAN}FINAL TEST SUMMARY${NC}"
    echo "=================="
    echo -e "Total Tests: ${BLUE}$TOTAL_TESTS${NC}"
    echo -e "Passed: ${GREEN}$TOTAL_PASSED${NC}"
    echo -e "Failed: ${RED}$TOTAL_FAILED${NC}"
    
    if [[ $TOTAL_TESTS -gt 0 ]]; then
        local success_rate=$((TOTAL_PASSED * 100 / TOTAL_TESTS))
        echo -e "Success Rate: ${BLUE}${success_rate}%${NC}"
    fi
    
    if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
        echo -e "\n${RED}Failed Test Suites:${NC}"
        for suite in "${FAILED_SUITES[@]}"; do
            echo -e "  ${RED}❌ $suite${NC}"
        done
    fi
    
    if [[ $TOTAL_FAILED -eq 0 && ${#FAILED_SUITES[@]} -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Some tests failed.${NC}"
        exit 1
    fi
}

# Function to show help
show_help() {
    echo "Network Host Reporting - Test Runner"
    echo "===================================="
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --all, -a          Run all tests (default)"
    echo "  --unit, -u         Run unit tests only"
    echo "  --integration, -i  Run integration tests only"
    echo "  --quick, -q        Run quick tests only"
    echo "  --test <name>      Run specific test suite"
    echo "  --help, -h         Show this help message"
    echo
    echo "Available test suites:"
    echo "  structure    - Script structure and dependencies"
    echo "  network      - Network detection functionality"
    echo "  json         - JSON generation and validation"
    echo "  integration  - End-to-end integration tests"
    echo
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 --unit            # Run unit tests only"
    echo "  $0 --test network    # Run network detection tests"
    echo "  $0 --quick           # Run quick tests"
}

# Main function
main() {
    local run_mode="all"
    local specific_test=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all|-a)
                run_mode="all"
                shift
                ;;
            --unit|-u)
                run_mode="unit"
                shift
                ;;
            --integration|-i)
                run_mode="integration"
                shift
                ;;
            --quick|-q)
                run_mode="quick"
                shift
                ;;
            --test)
                run_mode="specific"
                specific_test="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_header
    
    # Run tests based on mode
    case "$run_mode" in
        "all")
            run_unit_tests
            run_integration_tests
            ;;
        "unit")
            run_unit_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "quick")
            run_quick_tests
            ;;
        "specific")
            run_specific_test "$specific_test"
            ;;
    esac
    
    print_final_summary
}

# Run main function
main "$@"
