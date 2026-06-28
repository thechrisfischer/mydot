#!/bin/bash

# Test script to show the JSON payload that would be sent

# Get system information
hostname=$(hostname)
local_ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
external_ip=$(curl -s --connect-timeout 5 --max-time 10 "https://api.ipify.org" 2>/dev/null | tr -d '\n\r' || echo "unknown")
os_type="macOS"
os_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
uptime=$(uptime | awk '{print $3}' | sed 's/,//' || echo "unknown")

# Create JSON payload
json_payload=$(cat <<EOF
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

echo "JSON Payload that would be sent:"
echo "================================="
echo "$json_payload" | jq . 2>/dev/null || echo "$json_payload"

