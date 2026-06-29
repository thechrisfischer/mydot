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
    cleanup
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    mkdir -p "$TEST_TMPDIR/bin"
    PATH="$TEST_TMPDIR/bin:$PATH"
    export PATH

    cat > "$TEST_TMPDIR/bin/cursor" <<'BASH'
#!/bin/bash
printf 'cursor'
printf ' <%s>' "$@"
printf '\n'
BASH
    chmod +x "$TEST_TMPDIR/bin/cursor"

    cat > "$TEST_TMPDIR/bin/cursor-agent" <<'BASH'
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == "--print" ]]; then
        printf '{"type":"result","session_id":"conv-1","request_id":"gen-1","model":"composer-2.5","usage":{"inputTokens":12,"outputTokens":3,"cacheReadTokens":4,"cacheWriteTokens":5}}\n'
        exit 0
    fi
done
printf 'cursor-agent'
printf ' <%s>' "$@"
printf '\n'
BASH
    chmod +x "$TEST_TMPDIR/bin/cursor-agent"

    cat > "$TEST_TMPDIR/bin/codex" <<'BASH'
#!/bin/bash
printf 'codex'
printf ' <%s>' "$@"
printf '\n'
BASH
    chmod +x "$TEST_TMPDIR/bin/codex"
    hash -r
}

setup_shell_tmp() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home" "$TEST_TMPDIR/etc" "$TEST_TMPDIR/bin"
    export HOME="$TEST_TMPDIR/home"
    export DOTFILES_REPO_DIR="$REPO_ROOT"

    cat > "$TEST_TMPDIR/bin/bash" <<'BASH'
#!/bin/bash
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/bash"
    ln -s "$TEST_TMPDIR/bin/bash" "$TEST_TMPDIR/bin/bash-link"

    cat > "$TEST_TMPDIR/bin/grep" <<'BASH'
#!/bin/bash
if [[ "$#" -eq 3 && "$1" == "-qx" && "$3" == "/etc/shells" ]]; then
    exit 0
fi
exec /usr/bin/grep "$@"
BASH
    chmod +x "$TEST_TMPDIR/bin/grep"
}

cleanup() {
    if [[ -n "${TEST_TMPDIR:-}" ]]; then
        rm -rf "$TEST_TMPDIR"
        TEST_TMPDIR=""
    fi
}

trap cleanup EXIT

test_cursor_yolo_uses_agent_force_mode() {
    setup_tmp

    # shellcheck source=/dev/null
    source .bash/functions/cursor.bash

    local output
    output=$(cursor yolo ./ "fix this")

    [[ "$output" == "cursor-agent <--force> <./> <fix this>" ]] \
        || fail "cursor yolo should call cursor-agent --force; got: $output"
}

test_cursor_paths_use_gui_launcher() {
    setup_tmp

    # shellcheck source=/dev/null
    source .bash/functions/cursor.bash

    local output
    output=$(cursor ./ "some directory")

    [[ "$output" == "cursor <./> <some directory>" ]] \
        || fail "cursor path args should call GUI cursor CLI unchanged; got: $output"
}

test_cursor_yolo_must_be_exact_first_arg() {
    setup_tmp

    # shellcheck source=/dev/null
    source .bash/functions/cursor.bash

    local output
    output=$(cursor ./yolo)

    [[ "$output" == "cursor <./yolo>" ]] \
        || fail "only exact first arg 'yolo' should invoke cursor-agent; got: $output"
}

test_codex_yolo_wraps_dangerous_flag() {
    setup_tmp

    # shellcheck source=/dev/null
    source .bash/functions/codex.bash

    local output
    output=$(codex yolo "fix this")

    [[ "$output" == "codex <--dangerously-bypass-approvals-and-sandbox> <fix this>" ]] \
        || fail "codex yolo should add the dangerous bypass flag; got: $output"
}

test_codex_yolo_must_be_exact_first_arg() {
    setup_tmp

    # shellcheck source=/dev/null
    source .bash/functions/codex.bash

    local output
    output=$(codex ./yolo)

    [[ "$output" == "codex <./yolo>" ]] \
        || fail "only exact first arg 'yolo' should invoke codex wrapper mode; got: $output"
}

test_bash_login_profile_loads_codex_function() {
    setup_tmp

    # macOS /etc/profile runs path_helper and can discard inherited PATH segments,
    # so ensure the codex stub stays ahead of prefs.bash PATH prepends.
    {
        printf 'export PATH="%s:$PATH"\n' "$TEST_TMPDIR/bin"
        cat .bash_profile
    } > "$TEST_TMPDIR/.bash_profile"
    cp .bashrc "$TEST_TMPDIR/.bashrc"
    mkdir -p "$TEST_TMPDIR/.bash"
    cp -a .bash/functions "$TEST_TMPDIR/.bash/"
    cp .bash/prefs.bash "$TEST_TMPDIR/.bash/prefs.bash"
    cp .bash/prompt.bash "$TEST_TMPDIR/.bash/prompt.bash"

    local output
    output=$(HOME="$TEST_TMPDIR" /bin/bash --login -c 'type -t codex')

    [[ "$output" == "function" ]] \
        || fail "bash login shell should load codex function via .bash_profile; got: $output"
}

test_configure_shell_skips_chsh_for_equivalent_bash_path() {
    setup_shell_tmp

    local chsh_log="$TEST_TMPDIR/chsh.log"
    cat > "$TEST_TMPDIR/bin/chsh" <<'BASH'
#!/bin/bash
printf 'chsh <%s>\n' "$@" >> "$CHSH_LOG"
BASH
    chmod +x "$TEST_TMPDIR/bin/chsh"
    export CHSH_LOG="$chsh_log"
    export SHELL="$TEST_TMPDIR/bin/bash-link"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/shell.bash

    configure_shell > "$TEST_TMPDIR/output" 2>&1

    [[ ! -e "$chsh_log" ]] \
        || fail "configure_shell should not call chsh when SHELL and command -v bash resolve to the same shell"
}

test_configure_shell_skips_chsh_without_tty_when_captured() {
    setup_shell_tmp

    local chsh_log="$TEST_TMPDIR/chsh.log"
    cat > "$TEST_TMPDIR/bin/chsh" <<'BASH'
#!/bin/bash
printf 'chsh <%s>\n' "$@" >> "$CHSH_LOG"
BASH
    chmod +x "$TEST_TMPDIR/bin/chsh"
    # Isolate from host sudo: if sudo -n succeeds here, configure_shell runs real
    # sudo chsh (ignored PATH), which can hang against Directory Services and
    # bypass this mock entirely — defeating "skipped without tty".
    cat > "$TEST_TMPDIR/bin/sudo" <<'BASH'
#!/bin/bash
exit 1
BASH
    chmod +x "$TEST_TMPDIR/bin/sudo"
    hash -r

    export CHSH_LOG="$chsh_log"
    export SHELL="/bin/zsh"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/shell.bash

    _DOTFILES_SECTION_CAPTURE=1 configure_shell > "$TEST_TMPDIR/output" 2>&1

    [[ ! -e "$chsh_log" ]] \
        || fail "configure_shell should skip chsh when captured and no terminal is available"
    grep -q "skipping chsh" "$TEST_TMPDIR/output" \
        || fail "configure_shell should explain why chsh was skipped without a terminal"
}

test_configure_shell_uses_sudo_chsh_when_noninteractive_sudo_available() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home" "$TEST_TMPDIR/bin"
    export HOME="$TEST_TMPDIR/home"
    export DOTFILES_REPO_DIR="$REPO_ROOT"
    # Use real bash from /etc/shells — do not shadow `bash` with setup_shell_tmp stub.
    PATH="$TEST_TMPDIR/bin:/bin:/usr/bin:/usr/local/bin"

    local sudo_log="$TEST_TMPDIR/sudo.log"
    local chsh_log="$TEST_TMPDIR/chsh.log"
    cat > "$TEST_TMPDIR/bin/sudo" <<BASH
#!/bin/bash
printf 'sudo' >> "${sudo_log:?}"
printf ' <%s>' "\$@" >> "${sudo_log:?}"
printf '\n' >> "${sudo_log:?}"
if [[ "\$1" == "-n" ]]; then
    shift
    case "\$1" in
        -v|true) exit 0 ;;
        chsh)
            shift
            printf 'chsh <%s>\n' "\$@" >> "${chsh_log:?}"
            exit 0
            ;;
    esac
fi
exit 1
BASH
    chmod +x "$TEST_TMPDIR/bin/sudo"
    hash -r

    export SHELL="/bin/zsh"

    # shellcheck source=/dev/null
    source install/_helpers.bash
    # shellcheck source=/dev/null
    source install/shell.bash

    # Pin keepalive to this shell so the background refresher does not race
    # the sudo stub log while configure_shell runs.
    _DOTFILES_SUDO_KEEPALIVE_PID=$$

    configure_shell > "$TEST_TMPDIR/output" 2>&1

    grep -q '<-n> <-v>' "$sudo_log" \
        || fail "configure_shell should refresh sudo cache before chsh; log=$(cat "$sudo_log")"
    grep -q '<-n> <chsh>' "$sudo_log" \
        || fail "configure_shell should prefer sudo -n chsh when cached; log=$(cat "$sudo_log")"

    _stop_sudo_keepalive
    grep -q 'chsh <-s>' "$chsh_log" \
        || fail "sudo chsh stub should run chsh with -s; log=$(cat "$chsh_log")"
}

test_awsso_help_prints_usage() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    local output
    output="$(awsso --help 2>&1)" || fail "awsso --help should exit 0; output=$output"

    grep -q "Usage: awsso" <<<"$output" \
        || fail "awsso --help should print 'Usage: awsso'; output=$output"
    grep -q -- "--all" <<<"$output" \
        || fail "awsso --help should document --all; output=$output"
}

test_awsso_lists_sso_sessions_from_config() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[default]
region = us-east-1

[profile work-sso]
sso_session = MyOrg
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-east-1

[profile client-sso]
sso_session = ClientExample
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-west-2

[sso-session MyOrg]
sso_start_url = https://example.awsapps.com/start
sso_region = us-east-1

[sso-session ClientExample]
sso_start_url = https://example.awsapps.com/start
sso_region = us-west-2
CONF
    export HOME="$TEST_TMPDIR/home"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    local output
    output="$(_awsso_list_sessions 2>&1)" \
        || fail "_awsso_list_sessions should exit 0; output=$output"

    [[ "$output" == *"MyOrg"* ]] \
        || fail "_awsso_list_sessions should include MyOrg; got: $output"
    [[ "$output" == *"ClientExample"* ]] \
        || fail "_awsso_list_sessions should include ClientExample; got: $output"
    [[ "$output" != *"work-sso"* ]] \
        || fail "_awsso_list_sessions should NOT include profile names; got: $output"
}

test_awsso_direct_session_calls_aws_sso_login() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[sso-session MyOrg]
sso_start_url = https://example.awsapps.com/start
sso_region = us-east-1
CONF
    export HOME="$TEST_TMPDIR/home"

    local aws_log="$TEST_TMPDIR/aws.log"
    cat > "$TEST_TMPDIR/bin/aws" <<BASH
#!/bin/bash
printf 'aws' >> "${aws_log:?}"
printf ' <%s>' "\$@" >> "${aws_log:?}"
printf '\n' >> "${aws_log:?}"
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/aws"
    hash -r

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    awsso MyOrg > "$TEST_TMPDIR/output" 2>&1 \
        || fail "awsso MyOrg should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    grep -q 'aws <sso> <login> <--sso-session> <MyOrg>' "$aws_log" \
        || fail "awsso MyOrg should call aws sso login --sso-session MyOrg; log=$(cat "$aws_log")"
}

test_awsso_unknown_session_errors_without_calling_aws() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[sso-session MyOrg]
sso_region = us-east-1
CONF
    export HOME="$TEST_TMPDIR/home"

    local aws_log="$TEST_TMPDIR/aws.log"
    cat > "$TEST_TMPDIR/bin/aws" <<BASH
#!/bin/bash
printf 'aws called\n' >> "${aws_log:?}"
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/aws"
    hash -r

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    if awsso NoSuchSession > "$TEST_TMPDIR/output" 2>&1; then
        fail "awsso NoSuchSession should exit non-zero; output=$(cat "$TEST_TMPDIR/output")"
    fi

    [[ ! -s "$aws_log" ]] \
        || fail "awsso NoSuchSession must not call aws; log=$(cat "$aws_log")"
    grep -q "NoSuchSession" "$TEST_TMPDIR/output" \
        || fail "error message should mention the unknown session name; output=$(cat "$TEST_TMPDIR/output")"
}

test_awsso_all_loops_every_session() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[sso-session MyOrg]
sso_region = us-east-1

[sso-session ClientExample]
sso_region = us-west-2
CONF
    export HOME="$TEST_TMPDIR/home"

    local aws_log="$TEST_TMPDIR/aws.log"
    cat > "$TEST_TMPDIR/bin/aws" <<BASH
#!/bin/bash
printf 'aws' >> "${aws_log:?}"
printf ' <%s>' "\$@" >> "${aws_log:?}"
printf '\n' >> "${aws_log:?}"
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/aws"
    hash -r

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    awsso --all > "$TEST_TMPDIR/output" 2>&1 \
        || fail "awsso --all should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    grep -q 'aws <sso> <login> <--sso-session> <MyOrg>' "$aws_log" \
        || fail "awsso --all should log into MyOrg; log=$(cat "$aws_log")"
    grep -q 'aws <sso> <login> <--sso-session> <ClientExample>' "$aws_log" \
        || fail "awsso --all should log into ClientExample; log=$(cat "$aws_log")"
}

test_awsso_single_session_skips_menu() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[sso-session MyOrg]
sso_region = us-east-1
CONF
    export HOME="$TEST_TMPDIR/home"

    local aws_log="$TEST_TMPDIR/aws.log"
    cat > "$TEST_TMPDIR/bin/aws" <<BASH
#!/bin/bash
printf 'aws' >> "${aws_log:?}"
printf ' <%s>' "\$@" >> "${aws_log:?}"
printf '\n' >> "${aws_log:?}"
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/aws"
    hash -r

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    awsso </dev/null > "$TEST_TMPDIR/output" 2>&1 \
        || fail "awsso (single session) should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    grep -q 'aws <sso> <login> <--sso-session> <MyOrg>' "$aws_log" \
        || fail "awsso with single session should log in directly; log=$(cat "$aws_log")"
}

test_awsso_menu_picks_session_by_number() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[sso-session MyOrg]
sso_region = us-east-1

[sso-session ClientExample]
sso_region = us-west-2
CONF
    export HOME="$TEST_TMPDIR/home"

    local aws_log="$TEST_TMPDIR/aws.log"
    cat > "$TEST_TMPDIR/bin/aws" <<BASH
#!/bin/bash
printf 'aws' >> "${aws_log:?}"
printf ' <%s>' "\$@" >> "${aws_log:?}"
printf '\n' >> "${aws_log:?}"
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/aws"
    hash -r

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    # Pick option 2 → ClientExample
    awsso <<<"2" > "$TEST_TMPDIR/output" 2>&1 \
        || fail "awsso menu pick 2 should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    grep -q 'aws <sso> <login> <--sso-session> <ClientExample>' "$aws_log" \
        || fail "awsso menu pick 2 should log into ClientExample; log=$(cat "$aws_log")"
}

test_dot_aws_switch_help_prints_usage() {
    setup_tmp

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    local output
    output="$(dot-aws-switch --help 2>&1)" \
        || fail "dot-aws-switch --help should exit 0; output=$output"

    grep -q "Usage: dot-aws-switch" <<<"$output" \
        || fail "dot-aws-switch --help should print 'Usage: dot-aws-switch'; output=$output"
    grep -q -- "--unset" <<<"$output" \
        || fail "dot-aws-switch --help should document --unset; output=$output"
}

test_dot_aws_switch_lists_profiles_excluding_default() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[default]
region = us-east-1

[profile work-sso]
region = us-east-1

[profile client-sso]
region = us-west-2

[sso-session MyOrg]
sso_region = us-east-1
CONF
    export HOME="$TEST_TMPDIR/home"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    local output
    output="$(_dot_aws_switch_list_profiles 2>&1)" \
        || fail "_dot_aws_switch_list_profiles should exit 0; output=$output"

    grep -qx "work-sso" <<<"$output" \
        || fail "should list work-sso; got: $output"
    grep -qx "client-sso" <<<"$output" \
        || fail "should list client-sso; got: $output"
    ! grep -qx "default" <<<"$output" \
        || fail "should NOT list default; got: $output"
    ! grep -qx "MyOrg" <<<"$output" \
        || fail "should NOT list sso-session names; got: $output"
}

test_dot_aws_switch_region_for_profile() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[profile work-sso]
sso_session = MyOrg
region = us-east-1

[profile client-sso]
sso_session = ClientExample
region = us-west-2

[profile no-region]
sso_session = Other
CONF
    export HOME="$TEST_TMPDIR/home"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    local out
    out="$(_dot_aws_switch_region_for client-sso)" \
        || fail "_dot_aws_switch_region_for should exit 0"
    [[ "$out" == "us-west-2" ]] \
        || fail "expected us-west-2 for client-sso; got: $out"

    out="$(_dot_aws_switch_region_for work-sso)"
    [[ "$out" == "us-east-1" ]] \
        || fail "expected us-east-1 for work-sso; got: $out"

    out="$(_dot_aws_switch_region_for no-region)"
    [[ -z "$out" ]] \
        || fail "expected empty region for no-region profile; got: $out"
}

test_dot_aws_switch_direct_sets_profile_and_region() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[profile work-sso]
region = us-east-1

[profile client-sso]
region = us-west-2
CONF
    export HOME="$TEST_TMPDIR/home"
    unset AWS_PROFILE AWS_REGION

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    dot-aws-switch client-sso > "$TEST_TMPDIR/output" 2>&1 \
        || fail "dot-aws-switch client-sso should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    [[ "$AWS_PROFILE" == "client-sso" ]] \
        || fail "AWS_PROFILE should be client-sso; got: ${AWS_PROFILE:-<unset>}"
    [[ "$AWS_REGION" == "us-west-2" ]] \
        || fail "AWS_REGION should be us-west-2; got: ${AWS_REGION:-<unset>}"
}

test_dot_aws_switch_unsets_region_for_profile_without_region() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[profile no-region]
sso_session = Other
CONF
    export HOME="$TEST_TMPDIR/home"
    export AWS_PROFILE="stale"
    export AWS_REGION="us-west-2"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    dot-aws-switch no-region > "$TEST_TMPDIR/output" 2>&1 \
        || fail "dot-aws-switch no-region should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    [[ "$AWS_PROFILE" == "no-region" ]] \
        || fail "AWS_PROFILE should be no-region; got: ${AWS_PROFILE:-<unset>}"
    [[ -z "${AWS_REGION:-}" ]] \
        || fail "AWS_REGION should be unset when profile has no region; got: ${AWS_REGION:-<unset>}"
}

test_dot_aws_switch_unknown_profile_errors() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[profile work-sso]
region = us-east-1
CONF
    export HOME="$TEST_TMPDIR/home"
    unset AWS_PROFILE AWS_REGION

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    if dot-aws-switch nope > "$TEST_TMPDIR/output" 2>&1; then
        fail "dot-aws-switch nope should exit non-zero; output=$(cat "$TEST_TMPDIR/output")"
    fi
    [[ -z "${AWS_PROFILE:-}" ]] \
        || fail "AWS_PROFILE should remain unset on error; got: ${AWS_PROFILE:-<unset>}"
}

test_dot_aws_switch_unset_clears_env() {
    setup_tmp

    export AWS_PROFILE="work-sso"
    export AWS_REGION="us-east-1"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    dot-aws-switch --unset > "$TEST_TMPDIR/output" 2>&1 \
        || fail "dot-aws-switch --unset should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    [[ -z "${AWS_PROFILE:-}" ]] \
        || fail "AWS_PROFILE should be unset; got: ${AWS_PROFILE:-<unset>}"
    [[ -z "${AWS_REGION:-}" ]] \
        || fail "AWS_REGION should be unset; got: ${AWS_REGION:-<unset>}"
}

test_dot_aws_switch_menu_picks_profile_by_number() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[profile work-sso]
region = us-east-1

[profile client-sso]
region = us-west-2
CONF
    export HOME="$TEST_TMPDIR/home"
    unset AWS_PROFILE AWS_REGION

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    dot-aws-switch <<<"2" > "$TEST_TMPDIR/output" 2>&1 \
        || fail "dot-aws-switch menu pick 2 should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    [[ "$AWS_PROFILE" == "client-sso" ]] \
        || fail "AWS_PROFILE should be client-sso (option 2); got: ${AWS_PROFILE:-<unset>}"
    [[ "$AWS_REGION" == "us-west-2" ]] \
        || fail "AWS_REGION should be us-west-2; got: ${AWS_REGION:-<unset>}"
}

test_dot_aws_switch_menu_invalid_choice_errors() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[profile work-sso]
region = us-east-1

[profile client-sso]
region = us-west-2
CONF
    export HOME="$TEST_TMPDIR/home"
    unset AWS_PROFILE AWS_REGION

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/dot-aws-switch.bash"

    if dot-aws-switch <<<"99" > "$TEST_TMPDIR/output" 2>&1; then
        fail "dot-aws-switch invalid choice should exit non-zero; output=$(cat "$TEST_TMPDIR/output")"
    fi
    [[ -z "${AWS_PROFILE:-}" ]] \
        || fail "AWS_PROFILE should not be set on invalid choice; got: ${AWS_PROFILE:-<unset>}"
}

test_awsso_menu_invalid_choice_errors() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[sso-session MyOrg]
sso_region = us-east-1

[sso-session ClientExample]
sso_region = us-west-2
CONF
    export HOME="$TEST_TMPDIR/home"

    local aws_log="$TEST_TMPDIR/aws.log"
    cat > "$TEST_TMPDIR/bin/aws" <<BASH
#!/bin/bash
printf 'aws called\n' >> "${aws_log:?}"
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/aws"
    hash -r

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    if awsso <<<"99" > "$TEST_TMPDIR/output" 2>&1; then
        fail "awsso with invalid choice should exit non-zero; output=$(cat "$TEST_TMPDIR/output")"
    fi

    [[ ! -s "$aws_log" ]] \
        || fail "awsso with invalid choice must not call aws; log=$(cat "$aws_log")"
}

test_awsso_mirrors_credentials_to_default_after_login() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[profile work-sso]
sso_session = MyOrg
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = us-east-1

[sso-session MyOrg]
sso_start_url = https://example.awsapps.com/start
sso_region = us-east-1
CONF
    export HOME="$TEST_TMPDIR/home"

    local aws_log="$TEST_TMPDIR/aws.log"
    cat > "$TEST_TMPDIR/bin/aws" <<BASH
#!/bin/bash
printf 'aws' >> "${aws_log:?}"
for a in "\$@"; do printf ' <%s>' "\$a" >> "${aws_log:?}"; done
printf '\n' >> "${aws_log:?}"
if [[ "\$1" == "configure" && "\$2" == "export-credentials" ]]; then
    cat <<CREDS
AWS_ACCESS_KEY_ID=AKIAFAKE
AWS_SECRET_ACCESS_KEY=SECRETFAKE
AWS_SESSION_TOKEN=TOKENFAKE
AWS_CREDENTIAL_EXPIRATION=2026-05-16T20:00:00+0000
CREDS
fi
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/aws"
    hash -r

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    awsso MyOrg > "$TEST_TMPDIR/output" 2>&1 \
        || fail "awsso MyOrg should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    grep -q 'aws <sso> <login> <--sso-session> <MyOrg>' "$aws_log" \
        || fail "should call aws sso login; log=$(cat "$aws_log")"
    grep -q 'aws <configure> <export-credentials> <--profile> <work-sso>' "$aws_log" \
        || fail "should export creds for work-sso; log=$(cat "$aws_log")"
    grep -q 'aws <configure> <set> <aws_access_key_id> <AKIAFAKE> <--profile> <default>' "$aws_log" \
        || fail "should set default access key; log=$(cat "$aws_log")"
    grep -q 'aws <configure> <set> <aws_access_key_id> <AKIAFAKE> <--profile> <work-sso>' "$aws_log" \
        || fail "should set work-sso access key; log=$(cat "$aws_log")"
    grep -q 'aws <configure> <set> <aws_session_token> <TOKENFAKE> <--profile> <default>' "$aws_log" \
        || fail "should set default session token; log=$(cat "$aws_log")"
    grep -q 'aws <configure> <set> <aws_session_token> <TOKENFAKE> <--profile> <work-sso>' "$aws_log" \
        || fail "should set work-sso session token; log=$(cat "$aws_log")"
}

test_awsso_all_does_not_mirror_to_default() {
    setup_tmp

    mkdir -p "$TEST_TMPDIR/home/.aws"
    cat > "$TEST_TMPDIR/home/.aws/config" <<'CONF'
[profile work-sso]
sso_session = MyOrg

[sso-session MyOrg]
sso_region = us-east-1
CONF
    export HOME="$TEST_TMPDIR/home"

    local aws_log="$TEST_TMPDIR/aws.log"
    cat > "$TEST_TMPDIR/bin/aws" <<BASH
#!/bin/bash
printf 'aws' >> "${aws_log:?}"
for a in "\$@"; do printf ' <%s>' "\$a" >> "${aws_log:?}"; done
printf '\n' >> "${aws_log:?}"
exit 0
BASH
    chmod +x "$TEST_TMPDIR/bin/aws"
    hash -r

    # shellcheck source=/dev/null
    source "$REPO_ROOT/.bash/functions/awsso.bash"

    awsso --all > "$TEST_TMPDIR/output" 2>&1 \
        || fail "awsso --all should exit 0; output=$(cat "$TEST_TMPDIR/output")"

    ! grep -q 'aws <configure> <export-credentials>' "$aws_log" \
        || fail "awsso --all should NOT export credentials; log=$(cat "$aws_log")"
    ! grep -q 'aws <configure> <set>' "$aws_log" \
        || fail "awsso --all should NOT mirror to default; log=$(cat "$aws_log")"
}

test_install_iterm_shell_integration_copies_script() {
    setup_tmp

    export DOTFILES_REPO_DIR="$REPO_ROOT"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME"

    # shellcheck source=/dev/null
    source install/iterm.bash
    _install_iterm_shell_integration

    [[ -f "$HOME/.iterm2_shell_integration.bash" ]] \
        || fail "expected ~/.iterm2_shell_integration.bash to be installed"
    cmp -s "$REPO_ROOT/system/iterm2/iterm2_shell_integration.bash" \
        "$HOME/.iterm2_shell_integration.bash" \
        || fail "installed shell integration script should match repo copy"
}

test_iterm_bash_skips_without_error_on_non_darwin() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        return 0
    fi

    setup_tmp
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.bash"
    cp .bash/iterm.bash "$HOME/.bash/iterm.bash"

    # shellcheck source=/dev/null
    source "$HOME/.bash/iterm.bash"
}

test_cursor_yolo_uses_agent_force_mode
test_cursor_paths_use_gui_launcher
test_cursor_yolo_must_be_exact_first_arg
test_codex_yolo_wraps_dangerous_flag
test_codex_yolo_must_be_exact_first_arg
test_bash_login_profile_loads_codex_function
# New tests intentionally run before the configure_shell suite while
# test_configure_shell_* has a pre-existing failure under investigation
# (unrelated to AWS helpers). Keep new tests above that block until fixed.
test_awsso_help_prints_usage
test_awsso_lists_sso_sessions_from_config
test_awsso_direct_session_calls_aws_sso_login
test_awsso_unknown_session_errors_without_calling_aws
test_awsso_all_loops_every_session
test_awsso_single_session_skips_menu
test_awsso_menu_picks_session_by_number
test_awsso_menu_invalid_choice_errors
test_awsso_mirrors_credentials_to_default_after_login
test_awsso_all_does_not_mirror_to_default
test_dot_aws_switch_help_prints_usage
test_dot_aws_switch_lists_profiles_excluding_default
test_dot_aws_switch_region_for_profile
test_dot_aws_switch_direct_sets_profile_and_region
test_dot_aws_switch_unsets_region_for_profile_without_region
test_dot_aws_switch_unknown_profile_errors
test_dot_aws_switch_unset_clears_env
test_dot_aws_switch_menu_picks_profile_by_number
test_dot_aws_switch_menu_invalid_choice_errors
test_install_iterm_shell_integration_copies_script
test_iterm_bash_skips_without_error_on_non_darwin
test_configure_shell_skips_chsh_for_equivalent_bash_path
test_configure_shell_skips_chsh_without_tty_when_captured
test_configure_shell_uses_sudo_chsh_when_noninteractive_sudo_available

echo "shell tests passed"
