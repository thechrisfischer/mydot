#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$REPO_ROOT" || exit 1

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

setup_tmp() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/bin" "$HOME/Code/project" "$HOME/.ssh"
    export PATH="$HOME/.local/bin:/usr/bin:/bin"

    cat > "$HOME/.local/bin/gh" <<'BASH'
#!/bin/bash
echo "gh $*" >> "$HOME/gh.log"
case "$1" in
  auth)
    [[ "$2" == "status" ]] && exit 0
    ;;
  repo)
    [[ "$2" == "clone" ]] || exit 1
    mkdir -p "$4/.git"
    exit 0
    ;;
esac
exit 0
BASH
    chmod +x "$HOME/.local/bin/gh"

    cat > "$HOME/.local/bin/git" <<'BASH'
#!/bin/bash
if [[ "$1" == "clone" ]]; then
  echo "git clone $*" >> "$HOME/git.log"
  mkdir -p "$3/.git"
  exit 0
fi
exit 0
BASH
    chmod +x "$HOME/.local/bin/git"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/install/_helpers.bash"
}

test_dotfiles_git_clone_prefers_gh() {
    setup_tmp
    local dest="$HOME/Code/example/repo"
    _dotfiles_git_clone "ExampleOrg/example" "$dest"
    [[ -d "$dest/.git" ]] || fail "expected clone dest to exist"
    grep -q 'gh repo clone' "$HOME/gh.log" || fail "expected gh repo clone"
    ! grep -q 'git clone' "$HOME/git.log" 2>/dev/null || fail "should not fall back to git when gh works"
}

test_dotfiles_git_clone_prefers_ssh_when_id_rsa_present() {
    setup_tmp
    touch "$HOME/.ssh/id_rsa"
    chmod 600 "$HOME/.ssh/id_rsa"
    local dest="$HOME/Code/example/repo-ssh"
    _dotfiles_git_clone "ExampleOrg/example" "$dest"
    [[ -d "$dest/.git" ]] || fail "expected clone dest to exist"
    grep -q 'git@github.com:ExampleOrg/example.git' "$HOME/git.log" \
        || fail "expected git@ clone when id_rsa exists"
}

test_grepler_agent_is_opt_in() {
    ! grep -q 'ExampleOrg/example' "$REPO_ROOT/install/grepler-agent.bash" \
        || fail "grepler-agent should not hardcode a product repo"
    grep -q 'GREPLER_AGENT_SOURCE not set' "$REPO_ROOT/install/grepler-agent.bash" \
        || fail "grepler-agent should skip when no source is configured"
}

test_bootstrap_script_is_executable() {
    [[ -x "$REPO_ROOT/scripts/bootstrap-macos.sh" ]] \
        || fail "bootstrap-macos.sh should be executable"
    bash -n "$REPO_ROOT/scripts/bootstrap-macos.sh" \
        || fail "bootstrap-macos.sh should parse"
}

test_dotfiles_git_clone_prefers_gh
test_dotfiles_git_clone_prefers_ssh_when_id_rsa_present
test_grepler_agent_is_opt_in
test_bootstrap_script_is_executable

echo "bootstrap tests passed"
