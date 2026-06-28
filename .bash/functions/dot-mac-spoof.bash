#!/bin/bash

dot-mac-spoof() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: dot-mac-spoof"
        echo "Changes Wi-Fi MAC address (macOS only)"
        return 0
    fi

    # Check if we're on macOS
    if [[ $(uname -s) != "Darwin" ]]; then
        echo "This function only works on macOS"
        return 0
    fi

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        echo "Error: Don't run this as root"
        return 1
    fi

    echo "Disabling Wi-Fi..."
    sudo networksetup -setnetworkserviceenabled Wi-Fi off

    # Generate new MAC address
    local new_mac
    new_mac=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/.$//')

    echo "Setting new MAC address: $new_mac"
    sudo ifconfig en0 ether "$new_mac"

    echo "Re-enabling Wi-Fi..."
    sudo networksetup -setnetworkserviceenabled Wi-Fi on

    echo "MAC address spoofed successfully"
}
