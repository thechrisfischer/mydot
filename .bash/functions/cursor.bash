#!/bin/bash
# Wrapper for the `cursor` command with convenience subcommands
#   cursor yolo  — runs cursor-agent --force
# Anything else falls through to the real `cursor` GUI launcher.

cursor() {
    if [[ "${1:-}" == "yolo" ]]; then
        shift
        command cursor-agent --force "$@"
    else
        command cursor "$@"
    fi
}
