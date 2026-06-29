#!/bin/bash
# Tests sudo prompt channel selection (no real sudo invoked).
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$REPO_ROOT" || exit 1
fail() { echo "FAIL: $*" >&2; exit 1; }

# tty available + stdin not a tty (the curl|bash case) → choose tty, not none
expect_channel() {
    local tty_writable="$1" stdin_tty="$2" want="$3"
    (
        # shellcheck disable=SC1091
        source "$REPO_ROOT/install/_helpers.bash"
        _DOTFILES_TEST_TTY_WRITABLE="$tty_writable"
        _DOTFILES_TEST_STDIN_TTY="$stdin_tty"
        got=$(_sudo_prompt_channel)
        [[ "$got" == "$want" ]] || { echo "tty=$tty_writable stdin=$stdin_tty expected=$want got=$got" >&2; exit 1; }
    ) || fail "_sudo_prompt_channel tty=$tty_writable stdin=$stdin_tty → $want"
}

expect_channel 1 0 tty      # curl|bash: no stdin tty but /dev/tty writable
expect_channel 0 1 stdin    # normal interactive: stdin is a tty
expect_channel 1 1 tty      # both: prefer /dev/tty (robust under capture)
expect_channel 0 0 none     # headless CI: neither → caller must use DOTFILES_SUDO_PASSWORD
echo "sudo prompt-channel tests passed"
