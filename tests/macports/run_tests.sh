#!/bin/bash
# Tests MacPorts installer PKG slug mapping (no MacPorts install, no sw_vers mocking).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$REPO_ROOT" || exit 1

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

expect_slug() {
    local pv="$1" want="$2"
    (
        set --
        # shellcheck disable=SC1091
        source "$REPO_ROOT/install/_helpers.bash"
        local got
        got=$(_macports_pkg_slug_from_version "$pv") || {
            echo "unexpected failure for pv=$pv" >&2
            exit 1
        }
        [[ "$got" == "$want" ]] || {
            echo "pv=$pv expected='$want' got='$got'" >&2
            exit 1
        }
    ) || fail "_macports_pkg_slug_from_version $pv → $want"
}

expect_slug_fail() {
    local pv="$1"
    (
        set --
        # shellcheck disable=SC1091
        source "$REPO_ROOT/install/_helpers.bash"
        if _macports_pkg_slug_from_version "$pv" &>/dev/null; then
            exit 1
        fi
        exit 0
    ) || fail "_macports_pkg_slug_from_version should reject pv=$pv"
}

expect_slug "10.15.7" "10.15-Catalina"
expect_slug "10.14.6" "10.14-Mojave"
expect_slug "10.13.99" "10.13-HighSierra"
expect_slug "10.12.0" "10.12-Sierra"
expect_slug "10.11.1" "10.11-ElCapitan"
expect_slug "10.10.3" "10.10-Yosemite"
expect_slug "10.9.5" "10.9-Mavericks"
expect_slug "10.8.4" "10.8-MountainLion"
expect_slug "10.7.2" "10.7-Lion"
expect_slug "10.6.8" "10.6-SnowLeopard"
expect_slug "11.0" "11-BigSur"
expect_slug "12.7.6" "12-Monterey"
expect_slug "13.2" "13-Ventura"
expect_slug "14.5.99" "14-Sonoma"
expect_slug "15.0.1" "15-Sequoia"

expect_slug_fail "10.5.9"
expect_slug_fail "42.0.0"
expect_slug_fail ""

echo "macports tests passed"
