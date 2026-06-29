#!/bin/bash

# awsso — interactive picker for `aws sso login`.
# Reads SSO sessions from ~/.aws/config and runs
# `aws sso login --sso-session <name>` against the user's choice.
#
# After a successful single-session login, mirrors the temporary
# credentials into ~/.aws/credentials under both [default] and the
# matching [<profile>] section, so tools that don't set AWS_PROFILE
# transparently pick up the last session you logged into.

# Internal: print one [sso-session NAME] per line, in the order they appear
# in ~/.aws/config. Prints nothing (and exits 0) if the file is missing or
# contains no sessions.
_awsso_list_sessions() {
    local config="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
    [[ -f "$config" ]] || return 0
    awk '
        /^\[sso-session[[:space:]]+/ {
            name = $0
            sub(/^\[sso-session[[:space:]]+/, "", name)
            sub(/[[:space:]]*\][[:space:]]*$/, "", name)
            print name
        }
    ' "$config"
}

# Internal: print the first [profile NAME] in ~/.aws/config whose
# sso_session = <target>. Empty output if no profile matches.
_awsso_profile_for_session() {
    local target="$1"
    local config="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
    [[ -f "$config" ]] || return 0
    awk -v target="$target" '
        /^\[/ {
            in_profile = 0
            name = $0
            if (sub(/^\[profile[[:space:]]+/, "", name)) {
                sub(/[[:space:]]*\][[:space:]]*$/, "", name)
                current_profile = name
                in_profile = 1
            }
            next
        }
        in_profile && /^[[:space:]]*sso_session[[:space:]]*=/ {
            val = $0
            sub(/^[[:space:]]*sso_session[[:space:]]*=[[:space:]]*/, "", val)
            sub(/[[:space:]]+$/, "", val)
            if (val == target) { print current_profile; exit }
        }
    ' "$config"
}

# Internal: after a successful `aws sso login`, mirror temporary creds for
# the named session into ~/.aws/credentials [default] AND [<profile>].
# Non-fatal: prints a warning and returns 0 on any failure so a failed
# mirror doesn't make the login itself appear to fail.
_awsso_mirror_to_default() {
    local session="$1"
    local profile
    profile="$(_awsso_profile_for_session "$session")"
    if [[ -z "$profile" ]]; then
        echo "⚠ No profile uses sso_session = $session — skipping default mirror" >&2
        return 0
    fi

    local export_output
    export_output="$(aws configure export-credentials --profile "$profile" --format env-no-export 2>&1)"
    local export_rc=$?
    if (( export_rc != 0 )); then
        echo "⚠ Could not export credentials for $profile (rc=$export_rc) — skipping default mirror" >&2
        return 0
    fi

    local ak sk st exp
    ak="$(grep -m1 '^AWS_ACCESS_KEY_ID=' <<<"$export_output" | cut -d= -f2-)"
    sk="$(grep -m1 '^AWS_SECRET_ACCESS_KEY=' <<<"$export_output" | cut -d= -f2-)"
    st="$(grep -m1 '^AWS_SESSION_TOKEN=' <<<"$export_output" | cut -d= -f2-)"
    exp="$(grep -m1 '^AWS_CREDENTIAL_EXPIRATION=' <<<"$export_output" | cut -d= -f2-)"

    if [[ -z "$ak" || -z "$sk" ]]; then
        echo "⚠ Exported credentials missing key fields — skipping default mirror" >&2
        return 0
    fi

    local target_profile
    for target_profile in default "$profile"; do
        aws configure set aws_access_key_id "$ak" --profile "$target_profile"
        aws configure set aws_secret_access_key "$sk" --profile "$target_profile"
        if [[ -n "$st" ]]; then
            aws configure set aws_session_token "$st" --profile "$target_profile"
        fi
    done

    local pretty_exp="$exp"
    if [[ -n "$exp" ]]; then
        # Try to render in local time. macOS `date -j -f`; falls back to raw.
        local local_exp
        local_exp="$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "${exp/Z/+0000}" "+%H:%M %Z" 2>/dev/null)" \
            || local_exp="$(date -d "$exp" "+%H:%M %Z" 2>/dev/null)" \
            || local_exp=""
        [[ -n "$local_exp" ]] && pretty_exp="$local_exp"
    fi

    echo "✓ Mirrored $profile creds to [default] and [$profile] in ~/.aws/credentials (expires ${pretty_exp:-?})"
}

# Internal: run `aws sso login --sso-session <name>` and mirror creds on success.
_awsso_login_and_mirror() {
    local session="$1"
    echo "🔐 aws sso login --sso-session $session"
    aws sso login --sso-session "$session" || return $?
    _awsso_mirror_to_default "$session"
}

awsso() {
    case "${1:-}" in
        -h|--help|help)
            cat <<'EOF'
Usage: awsso [session | --all]

  awsso              Interactive picker over [sso-session ...] blocks in
                     ~/.aws/config. If only one session is configured,
                     logs into it without prompting.
  awsso <session>    Log into the named SSO session directly.
  awsso -a|--all     Log into every configured SSO session sequentially.
                     Does not mirror to [default] (ambiguous which session
                     should win); use awsso <session> to set a default.
  awsso -h|--help    Print this message.

After a single-session login, awsso writes the temporary credentials to
~/.aws/credentials under [default] AND [<matching profile>] so tools
that hit the default credential chain (no AWS_PROFILE / --profile) pick
them up automatically. Credentials expire when the SSO role does;
re-run awsso to refresh.
EOF
            return 0
            ;;
    esac

    if ! command -v aws >/dev/null 2>&1; then
        echo "✗ aws CLI not found. Run: ~/Code/mydot/install.sh packages" >&2
        return 1
    fi

    local sessions
    sessions="$(_awsso_list_sessions)"
    if [[ -z "$sessions" ]]; then
        echo "✗ No [sso-session ...] blocks found in ${AWS_CONFIG_FILE:-$HOME/.aws/config}" >&2
        echo "  Run: ./install.sh dotfiles  (or add one with: aws configure sso)" >&2
        return 1
    fi

    # Direct: awsso <name>
    if [[ -n "${1:-}" && "$1" != "-a" && "$1" != "--all" ]]; then
        local target="$1"
        if ! grep -Fxq "$target" <<<"$sessions"; then
            echo "✗ Unknown SSO session: $target" >&2
            echo "  Available:" >&2
            sed 's/^/    /' <<<"$sessions" >&2
            return 1
        fi
        _awsso_login_and_mirror "$target"
        return $?
    fi

    # --all: loop every session (no default mirror — ambiguous which wins)
    if [[ "${1:-}" == "-a" || "${1:-}" == "--all" ]]; then
        local rc=0 session
        while IFS= read -r session; do
            [[ -z "$session" ]] && continue
            echo "🔐 aws sso login --sso-session $session"
            aws sso login --sso-session "$session" || rc=$?
        done <<<"$sessions"
        return "$rc"
    fi

    # Interactive menu
    local -a session_arr=()
    local session
    while IFS= read -r session; do
        [[ -z "$session" ]] && continue
        session_arr+=("$session")
    done <<<"$sessions"

    # Single session: log in without prompting.
    if [[ "${#session_arr[@]}" -eq 1 ]]; then
        _awsso_login_and_mirror "${session_arr[0]}"
        return $?
    fi

    echo "SSO sessions:"
    local i
    for i in "${!session_arr[@]}"; do
        printf '  %d) %s\n' "$((i + 1))" "${session_arr[$i]}"
    done
    printf 'Pick a session [1-%d]: ' "${#session_arr[@]}"

    local choice
    read -r choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] \
       || (( choice < 1 || choice > ${#session_arr[@]} )); then
        echo "✗ Invalid choice: $choice" >&2
        return 1
    fi

    local target="${session_arr[$((choice - 1))]}"
    _awsso_login_and_mirror "$target"
}
