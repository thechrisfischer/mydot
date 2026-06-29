#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$REPO_ROOT" || exit 1

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# shellcheck source=/dev/null
source install/_helpers.bash

assert_mapping() {
    local name="$1"
    local pm="$2"
    local expected="$3"
    local actual
    actual=$(_linux_packages_for "$name" "$pm")
    [[ "$actual" == "$expected" ]] || fail "_linux_packages_for $name $pm: expected '$expected', got '$actual'"
}

assert_mapping node apt "nodejs npm"
assert_mapping virtualenv apt "python3-venv python3-virtualenv"
assert_mapping shellcheck yum "ShellCheck"
assert_mapping uv apt ""

bash -n install.sh install/_helpers.bash install/packages.bash install/apps.bash install/dictation.bash install/cursor.bash install/shell.bash install/external-fs.bash

# gh apt repo wiring
( set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/install/_helpers.bash"
  url="$(_gh_apt_source_line)"
  case "$url" in
    *cli.github.com/packages*stable\ main*) : ;;
    *) echo "unexpected gh apt source: $url" >&2; exit 1 ;;
  esac
) || fail "gh apt source line"

echo "linux package tests passed"
