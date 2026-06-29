#!/bin/bash
# Back-compat shim — the bootstrap is now OS-aware. Use scripts/bootstrap.sh.
# Kept so the previously-published one-liner URL keeps working.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$DIR/bootstrap.sh" ]]; then
    exec /bin/bash "$DIR/bootstrap.sh" "$@"
fi
# Running detached via curl (no sibling file): fetch the universal script.
GH="${DOTFILES_GITHUB:-thechrisfischer/mydot}"
exec /bin/bash -c "$(curl -fsSL "https://raw.githubusercontent.com/$GH/main/scripts/bootstrap.sh")" "$@"
