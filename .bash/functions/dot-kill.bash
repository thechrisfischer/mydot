#!/bin/bash

# Function will kill all processes with the associated application name
dot-kill() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-kill <application_name>"
        echo "Kills all processes matching the application name"
        echo "Example: dot-kill chrome"
        return 0
    fi

    # Set a local variable set to the incoming first argument
    local application=$1

    # Usage help - Shows how to use the function
    if [[ -z "$application" ]]; then
        echo "Usage: dot-kill <application_name>"
        return 1
    fi

    # Get matching process ids using pgrep
    local process_ids
    process_ids=$(pgrep -fi "$application" 2>/dev/null)

    # Error handling - Checks if processes were found
    if [[ -z "$process_ids" ]]; then
        echo "No processes found matching '$application'"
        return 1
    fi

    # Show processes that will be killed
    echo "Found processes matching '$application':"
    pgrep -fil "$application"

    echo "Killing all matching processes..."

    # For each process in the list kill off all PIDs
    for process in $process_ids; do
        # Try graceful kill first, then force kill
        if kill "$process" 2>/dev/null; then
            echo "Killed $application: PID $process (graceful)"
        else
            kill -9 "$process" 2>/dev/null
            echo "Killed $application: PID $process (force)"
        fi
    done
}
