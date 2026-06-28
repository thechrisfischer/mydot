#!/bin/bash
# Wrapper for Gemini CLI with convenience subcommands
#   gemini yolo  — runs gemini --yolo (auto-approve all tool calls)

gemini() {
    if [[ "${1:-}" == "yolo" ]]; then
        shift
        command gemini --yolo "$@"
    else
        command gemini "$@"
    fi
}
