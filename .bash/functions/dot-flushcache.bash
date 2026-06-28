#!/bin/bash

# Function to flush the dns cache
dot-flushcache() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-flushcache"
        echo "Flushes DNS cache (macOS only)"
        return 0
    fi

    local os_type
    os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
    if [[ $os_type == 'darwin' ]]; then
        if sudo killall -HUP mDNSResponder; then
            echo "DNS cache flushed successfully"
        else
            echo "Error: Failed to flush DNS cache"
            return 1
        fi
    else
        echo "This function only works on macOS"
        return 0
    fi
}
