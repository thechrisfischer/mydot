#!/bin/bash

# dot-aws-switch — pick (or set) the active AWS profile for the current shell.
# Exports AWS_PROFILE and AWS_REGION (from the profile's region= line, if any).

# Internal: print one [profile NAME] per line, in config order. Excludes the
# bare [default] section (no [profile] prefix). Returns 0 even when none found.
_dot_aws_switch_list_profiles() {
    local config="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
    [[ -f "$config" ]] || return 0
    awk '
        /^\[profile[[:space:]]+/ {
            name = $0
            sub(/^\[profile[[:space:]]+/, "", name)
            sub(/[[:space:]]*\][[:space:]]*$/, "", name)
            print name
        }
    ' "$config"
}

# Internal: print the region= value for [profile NAME], or empty if absent.
_dot_aws_switch_region_for() {
    local target="$1"
    local config="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
    [[ -f "$config" ]] || return 0
    awk -v target="$target" '
        BEGIN { in_target = 0 }
        /^\[/ {
            in_target = 0
            name = $0
            if (sub(/^\[profile[[:space:]]+/, "", name)) {
                sub(/[[:space:]]*\][[:space:]]*$/, "", name)
                if (name == target) in_target = 1
            }
            next
        }
        in_target && /^[[:space:]]*region[[:space:]]*=/ {
            val = $0
            sub(/^[[:space:]]*region[[:space:]]*=[[:space:]]*/, "", val)
            sub(/[[:space:]]+$/, "", val)
            print val
            exit
        }
    ' "$config"
}

dot-aws-switch() {
    case "${1:-}" in
        -h|--help|help)
            cat <<'EOF'
Usage: dot-aws-switch [profile | --unset]

  dot-aws-switch              Interactive picker over [profile ...] blocks
                             in ~/.aws/config. Empty [default] is excluded.
                             Selection exports AWS_PROFILE (and AWS_REGION
                             from the profile's region= line, when present;
                             AWS_REGION is unset otherwise so stale values
                             from a previous switch don't leak through).
  dot-aws-switch <profile>    Set AWS_PROFILE to <profile> directly.
  dot-aws-switch -u|--unset   Unset AWS_PROFILE and AWS_REGION.
  dot-aws-switch -h|--help    Print this message.
EOF
            return 0
            ;;
        -u|--unset)
            unset AWS_PROFILE AWS_REGION
            echo "AWS_PROFILE=(unset)  AWS_REGION=(unset)"
            return 0
            ;;
    esac

    local profiles
    profiles="$(_dot_aws_switch_list_profiles)"
    if [[ -z "$profiles" ]]; then
        echo "✗ No [profile ...] blocks found in ${AWS_CONFIG_FILE:-$HOME/.aws/config}" >&2
        echo "  Run: ./install.sh dotfiles" >&2
        return 1
    fi

    local target=""
    if [[ -n "${1:-}" ]]; then
        target="$1"
        if ! grep -Fxq "$target" <<<"$profiles"; then
            echo "✗ Unknown AWS profile: $target" >&2
            echo "  Available:" >&2
            sed 's/^/    /' <<<"$profiles" >&2
            return 1
        fi
    else
        local -a profile_arr=()
        local p
        while IFS= read -r p; do
            [[ -z "$p" ]] && continue
            profile_arr+=("$p")
        done <<<"$profiles"

        echo "AWS profiles:"
        local i
        for i in "${!profile_arr[@]}"; do
            printf '  %d) %s\n' "$((i + 1))" "${profile_arr[$i]}"
        done
        printf 'Pick a profile [1-%d]: ' "${#profile_arr[@]}"

        local choice
        read -r choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] \
           || (( choice < 1 || choice > ${#profile_arr[@]} )); then
            echo "✗ Invalid choice: $choice" >&2
            return 1
        fi
        target="${profile_arr[$((choice - 1))]}"
    fi

    export AWS_PROFILE="$target"
    local region
    region="$(_dot_aws_switch_region_for "$target")"
    if [[ -n "$region" ]]; then
        export AWS_REGION="$region"
    else
        unset AWS_REGION
    fi
    printf 'AWS_PROFILE=%s  AWS_REGION=%s\n' \
        "$AWS_PROFILE" "${AWS_REGION:-(unset)}"
}
