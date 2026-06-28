#!/bin/bash
# Wrapper for Codex CLI with convenience subcommands
#   codex yolo  — runs codex --dangerously-bypass-approvals-and-sandbox

codex() {
    if [[ "${1:-}" == "yolo" ]]; then
        shift
        command codex --dangerously-bypass-approvals-and-sandbox "$@"
    else
        command codex "$@"
    fi
}
