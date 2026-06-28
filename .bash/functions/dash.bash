#!/bin/bash

# Dashlane vault access via dcli.
# TTY-aware: copies to clipboard when run interactively, prints to stdout
# when captured (so Claude/scripts can read the value directly).
#
# Note-field TOTP seeds: this vault stores some TOTP secrets in the `note`
# field as `otpauth://totp/...?secret=...&issuer=...` URLs (not in Dashlane's
# native OTP store). Every retrieval auto-mints codes from any such URLs in
# addition to whatever dcli's native OTP path returns — so both legacy
# (note-embedded) and migrated (native) seeds work transparently.

dash() {
    local sub="${1:-}"
    shift 2>/dev/null || true

    case "$sub" in
        search)
            _dash_search "$@"
            ;;
        get)
            _dash_get "$@"
            ;;
        otp)
            _dash_otp "$@"
            ;;
        note)
            _dash_note "$@"
            ;;
        unlock)
            _dash_unlock "$@"
            ;;
        admin)
            _dash_admin "$@"
            ;;
        ""|help|-h|--help)
            cat <<'EOF'
Usage: dash <command> [args]

  search <query>   List vault items matching <query>; interactive: prompts
                   for a number and retrieves that entry's password
  get <name>       Get password by exact title match — clipboard if TTY,
                   stdout if piped
  otp <name>       Get 2FA code (native dcli OTP + any otpauth seeds found
                   in note fields) — clipboard if TTY, stdout if piped
  note <name>      Get secure note contents
  unlock <site>    Search + get + otp + note in one shot; copies password
                   to clipboard and prints OTP code(s) and full note
  <site>           Shortcut for 'unlock <site>' (any non-reserved first arg)
  admin <action>   Maintenance: setup | sync | status | lock | log
EOF
            ;;
        *)
            # Anything starting with a dash is an unknown flag — error.
            # Everything else is treated as a site name → unlock shortcut.
            if [[ "$sub" == -* ]]; then
                echo "Unknown command: $sub (try 'dash help')" >&2
                return 1
            fi
            _dash_unlock "$sub" "$@"
            ;;
    esac
}

# Internal: bail with a clear message if dcli isn't set up yet. Checks the
# local userdata.db device table directly instead of invoking dcli, since
# dcli prompts on raw TTY when no account is registered (which hangs in
# non-interactive contexts).
_dash_ensure_setup() {
    if ! command -v dcli &> /dev/null; then
        echo "✗ dcli is not installed. Run: ~/Code/dotfiles/install.sh packages" >&2
        return 1
    fi

    local db="$HOME/Library/Application Support/dashlane-cli/userdata.db"
    [ -f "$db" ] || db="$HOME/.config/dashlane-cli/userdata.db"

    if [ ! -f "$db" ]; then
        printf '✗ Dashlane vault is not set up on this device.\n  Run: dash admin setup\n' >&2
        return 1
    fi

    local count
    count="$(sqlite3 "$db" 'SELECT COUNT(*) FROM device' 2>/dev/null || echo 0)"
    if [ -z "$count" ] || [ "$count" = "0" ]; then
        printf '✗ Dashlane vault is not set up on this device.\n  Run: dash admin setup\n' >&2
        return 1
    fi
}

# Internal: run a dcli command capturing stdout/stderr separately. On non-zero
# exit, prints stderr to fd 2 and returns 1. On success, prints stdout (which
# may be a valid-but-empty JSON array). Use this instead of `dcli ... 2>/dev/null`
# so vault-locked / network / auth errors don't get swallowed and misreported
# as "no value found".
_dash_dcli() {
    local stderr_file rc
    stderr_file="$(mktemp)"
    local stdout
    stdout="$("$@" 2>"$stderr_file")"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '✗ dcli error (exit %d):\n' "$rc" >&2
        cat "$stderr_file" >&2
        rm -f "$stderr_file"
        return 1
    fi
    rm -f "$stderr_file"
    printf '%s' "$stdout"
}

# Internal: emit a value to clipboard if interactive, stdout otherwise.
_dash_emit() {
    local label="$1" value="$2"
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "✗ no value found" >&2
        return 1
    fi
    if [ -t 1 ]; then
        printf '%s' "$value" | pbcopy
        echo "✓ $label copied to clipboard"
    else
        printf '%s' "$value"
    fi
    _dash_log "$label"
}

# Internal: append to audit log. Best-effort — never fails the caller (e.g.
# when running under `set -e` in a sandbox without a writable $HOME).
_dash_log() {
    printf '%s  %s  (from %s)\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$1" \
        "${CLAUDE_SESSION:-${TERM_PROGRAM:-shell}}" \
        >> "$HOME/.dash.log" 2>/dev/null || true
}

# Internal: mint TOTP code(s) from otpauth:// URL(s) found in a note string.
# Prints one line per URL in the form "<issuer>: <code> (<secs_left>s)".
# Empty output when:
#   - note is empty
#   - note contains no otpauth:// URL
#   - python3 is unavailable (graceful no-op so the rest of dash still works)
_dash_otp_from_note() {
    local note="$1"
    [ -z "$note" ] && return 0
    command -v python3 >/dev/null 2>&1 || return 0

    local urls
    urls="$(printf '%s' "$note" | grep -oE 'otpauth://totp/[^[:space:]"<>]+' || true)"
    [ -z "$urls" ] && return 0

    # NOTE: we pass the python script via -c (not via heredoc-to-stdin) so the
    # URL lines piped on stdin reach `sys.stdin` instead of being eaten by the
    # heredoc that would otherwise become python's stdin.
    printf '%s\n' "$urls" | python3 -c '
import sys, time, hmac, hashlib, base64, struct, urllib.parse, re

now = int(time.time())
secs_left = 30 - (now % 30)

for raw in sys.stdin:
    raw = raw.strip()
    if not raw:
        continue
    try:
        parsed = urllib.parse.urlparse(raw)
        q = urllib.parse.parse_qs(parsed.query)
        secret = q.get("secret", [""])[0]
        if not secret:
            continue
        issuer = q.get("issuer", [""])[0]
        if not issuer:
            label = urllib.parse.unquote(parsed.path.lstrip("/"))
            issuer = label.split(":")[0] if ":" in label else label
        issuer = urllib.parse.unquote(issuer)
        seed = re.sub(r"\s+", "", secret).upper()
        padding = "=" * ((8 - len(seed) % 8) % 8)
        key = base64.b32decode(seed + padding)
        counter = now // 30
        h = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
        offset = h[-1] & 0x0f
        code = (struct.unpack(">I", h[offset:offset + 4])[0] & 0x7fffffff) % 1000000
        print(f"{issuer}: {code:06d} ({secs_left}s)")
    except Exception:
        continue
'
}

# Internal: print note-derived OTP codes alongside another value, TTY-aware.
# When TTY: prints to stderr prefixed with "  🔑 " so it appears next to but
# doesn't pollute the primary stdout value. When piped: prints "OTP_CODE: <code>"
# lines to stdout so scripts/agents can parse deterministically.
_dash_emit_note_otps() {
    local note="$1"
    local lines
    lines="$(_dash_otp_from_note "$note")"
    [ -z "$lines" ] && return 0
    if [ -t 1 ]; then
        printf '%s\n' "$lines" | sed 's/^/  🔑 /' >&2
    else
        printf '%s\n' "$lines" | while IFS= read -r line; do
            local code
            code="$(printf '%s' "$line" | grep -oE '[0-9]{6}' | head -1)"
            [ -n "$code" ] && printf 'OTP_CODE: %s\n' "$code"
        done
    fi
}

_dash_search() {
    local query="${1:-}"
    if [ -z "$query" ]; then
        echo "Usage: dash search <query>" >&2
        return 1
    fi
    _dash_ensure_setup || return 1

    local results count
    results="$(_dash_dcli dcli p "$query" -o json)" || return 1
    count="$(printf '%s' "$results" | jq 'length' 2>/dev/null)"
    if [ -z "$count" ] || [ "$count" = "0" ]; then
        echo "No matches for '$query'." >&2
        return 1
    fi

    # Build numbered list with title, email, and an OTP column for any row
    # whose note has an otpauth:// URL.
    local i title email note otp_code
    {
        for i in $(seq 0 $((count - 1))); do
            title="$(printf '%s' "$results" | jq -r --argjson i "$i" '.[$i].title // .[$i].url // "—"')"
            email="$(printf '%s' "$results" | jq -r --argjson i "$i" '.[$i].email // .[$i].login // "—"')"
            note="$(printf '%s' "$results" | jq -r --argjson i "$i" '.[$i].note // ""')"
            otp_code="$(_dash_otp_from_note "$note" | head -1 | grep -oE '[0-9]{6}' | head -1 || true)"
            if [ -n "$otp_code" ]; then
                printf '%d\t%s\t%s\t🔑 %s\n' $((i + 1)) "$title" "$email" "$otp_code"
            else
                printf '%d\t%s\t%s\t\n' $((i + 1)) "$title" "$email"
            fi
        done
    } | column -t -s $'\t'

    # If not interactive, stop after listing (scripts can parse the output).
    [ -t 0 ] && [ -t 1 ] || return 0

    local selection
    printf '\nGet password for which number? (1-%s, blank to cancel): ' "$count"
    read -r selection
    [ -z "$selection" ] && return 0
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
        echo "✗ invalid selection: $selection" >&2
        return 1
    fi

    local idx=$((selection - 1))
    local password label note_for_sel
    password="$(printf '%s' "$results" | jq -r --argjson i "$idx" '.[$i].password // empty')"
    label="$(printf '%s' "$results" | jq -r --argjson i "$idx" \
        '"\(.[$i].title // .[$i].url // "—") (\(.[$i].email // .[$i].login // "—"))"')"
    note_for_sel="$(printf '%s' "$results" | jq -r --argjson i "$idx" '.[$i].note // ""')"
    _dash_emit "password for $label" "$password"
    _dash_emit_note_otps "$note_for_sel"
}

_dash_get() {
    local query="${1:-}"
    if [ -z "$query" ]; then
        echo "Usage: dash get <name>" >&2
        return 1
    fi
    _dash_ensure_setup || return 1
    local results password note
    results="$(_dash_dcli dcli p "$query" -o json)" || return 1
    password="$(printf '%s' "$results" | jq -r '.[0].password // empty')"
    note="$(printf '%s' "$results" | jq -r '.[0].note // ""')"
    _dash_emit "password for '$query'" "$password"
    _dash_emit_note_otps "$note"
}

_dash_otp() {
    local query="${1:-}"
    if [ -z "$query" ]; then
        echo "Usage: dash otp <name>" >&2
        return 1
    fi
    _dash_ensure_setup || return 1

    # Path A: native dcli OTP field (works once the seed lives in Dashlane's
    # native OTP store; returns "No credential found with OTP" otherwise).
    local native
    native="$(dcli password -f otp -o console "$query" 2>/dev/null || true)"
    native="$(printf '%s' "$native" | tr -d '[:space:]' | grep -oE '^[0-9]{6}$' || true)"

    # Path B: any otpauth:// URL stored in the note field.
    local results note note_lines
    results="$(_dash_dcli dcli p "$query" -o json)" || return 1
    note="$(printf '%s' "$results" | jq -r '.[0].note // ""')"
    note_lines="$(_dash_otp_from_note "$note")"

    if [ -z "$native" ] && [ -z "$note_lines" ]; then
        echo "✗ no OTP found for '$query'" >&2
        return 1
    fi

    # Emit. Native code (if present) becomes the primary value (clipboard or
    # stdout). Note-derived codes are always shown alongside.
    if [ -n "$native" ]; then
        _dash_emit "otp for '$query'" "$native"
        if [ -n "$note_lines" ]; then
            _dash_emit_note_otps "$note"
        fi
    else
        # No native — promote the first note code to primary slot.
        local primary
        primary="$(printf '%s' "$note_lines" | head -1 | grep -oE '[0-9]{6}' | head -1)"
        _dash_emit "otp for '$query'" "$primary"
        # If there are additional note-derived codes, show them too.
        local extra
        extra="$(printf '%s' "$note_lines" | tail -n +2)"
        if [ -n "$extra" ]; then
            if [ -t 1 ]; then
                printf '%s\n' "$extra" | sed 's/^/  🔑 /' >&2
            else
                printf '%s\n' "$extra" | while IFS= read -r line; do
                    local c
                    c="$(printf '%s' "$line" | grep -oE '[0-9]{6}' | head -1)"
                    [ -n "$c" ] && printf 'OTP_CODE: %s\n' "$c"
                done
            fi
        fi
    fi
}

_dash_note() {
    local query="${1:-}"
    if [ -z "$query" ]; then
        echo "Usage: dash note <name>" >&2
        return 1
    fi
    _dash_ensure_setup || return 1
    local results content note_for_pw
    results="$(_dash_dcli dcli note "$query" -o json)" || return 1
    content="$(printf '%s' "$results" | jq -r '.[0].content // empty')"
    # If `dcli note` returns nothing, fall back to the note field on the
    # matching password entry (the user's own convention puts free-form text
    # there alongside otpauth:// URLs).
    if [ -z "$content" ]; then
        local pw_results
        pw_results="$(_dash_dcli dcli p "$query" -o json)" || return 1
        note_for_pw="$(printf '%s' "$pw_results" | jq -r '.[0].note // ""')"
        content="$note_for_pw"
    fi
    _dash_emit "note '$query'" "$content"
    # Surface any otpauth:// codes from the content itself.
    _dash_emit_note_otps "$content"
}

# Internal: print one entry's full unlock payload (title/login/url, password,
# OTP codes from any otpauth:// in note, then the full note). TTY-aware:
#   - interactive: copies password to clipboard, prints decorated lines
#   - piped: emits labeled KEY: value lines for deterministic parsing
_dash_unlock_emit() {
    local results="$1" idx="$2"
    local title login url password note
    title="$(printf '%s' "$results" | jq -r --argjson i "$idx" '.[$i].title // "—"')"
    login="$(printf '%s' "$results" | jq -r --argjson i "$idx" '.[$i].login // .[$i].email // "—"')"
    url="$(printf '%s' "$results" | jq -r --argjson i "$idx" '.[$i].url // ""')"
    password="$(printf '%s' "$results" | jq -r --argjson i "$idx" '.[$i].password // ""')"
    note="$(printf '%s' "$results" | jq -r --argjson i "$idx" '.[$i].note // ""')"

    if [ -t 1 ]; then
        printf '✓ %s  (%s)\n' "$title" "$login"
        [ -n "$url" ] && printf '  %s\n' "$url"
        if [ -n "$password" ]; then
            printf '%s' "$password" | pbcopy
            printf '  Password copied to clipboard\n'
        fi
        local otp_lines
        otp_lines="$(_dash_otp_from_note "$note")"
        if [ -n "$otp_lines" ]; then
            printf '%s\n' "$otp_lines" | sed 's/^/  🔑 /'
        fi
        if [ -n "$note" ]; then
            printf '  ─── note ───\n'
            printf '%s\n' "$note" | sed 's/^/  /'
        fi
    else
        printf 'TITLE: %s\n' "$title"
        printf 'LOGIN: %s\n' "$login"
        [ -n "$url" ] && printf 'URL: %s\n' "$url"
        [ -n "$password" ] && printf 'PASSWORD: %s\n' "$password"
        local otp_lines code
        otp_lines="$(_dash_otp_from_note "$note")"
        if [ -n "$otp_lines" ]; then
            printf '%s\n' "$otp_lines" | while IFS= read -r line; do
                code="$(printf '%s' "$line" | grep -oE '[0-9]{6}' | head -1)"
                [ -n "$code" ] && printf 'OTP_CODE: %s\n' "$code"
            done
        fi
        if [ -n "$note" ]; then
            printf 'NOTE:\n%s\n' "$note"
        fi
    fi
    _dash_log "unlock $title"
}

_dash_unlock() {
    local query="${1:-}"
    if [ -z "$query" ]; then
        echo "Usage: dash unlock <site>" >&2
        return 1
    fi
    _dash_ensure_setup || return 1

    local results count
    results="$(_dash_dcli dcli p "$query" -o json)" || return 1
    count="$(printf '%s' "$results" | jq 'length' 2>/dev/null)"
    if [ -z "$count" ] || [ "$count" = "0" ]; then
        echo "✗ no matches for '$query'" >&2
        return 1
    fi

    if [ "$count" = "1" ]; then
        _dash_unlock_emit "$results" 0
        return 0
    fi

    # Multiple matches.
    if [ -t 0 ] && [ -t 1 ]; then
        # Interactive: list, prompt, unlock the chosen row.
        echo "Found $count matches for '$query':"
        local i title email
        {
            for i in $(seq 0 $((count - 1))); do
                title="$(printf '%s' "$results" | jq -r --argjson i "$i" '.[$i].title // .[$i].url // "—"')"
                email="$(printf '%s' "$results" | jq -r --argjson i "$i" '.[$i].email // .[$i].login // "—"')"
                printf '%d\t%s\t%s\n' $((i + 1)) "$title" "$email"
            done
        } | column -t -s $'\t'

        local selection
        printf '\nUnlock which? (1-%s, blank to cancel): ' "$count"
        read -r selection
        [ -z "$selection" ] && return 0
        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
            echo "✗ invalid selection: $selection" >&2
            return 1
        fi
        _dash_unlock_emit "$results" $((selection - 1))
    else
        # Piped: dump every match (multi-match piped behaviour chosen by user).
        local i
        for i in $(seq 0 $((count - 1))); do
            [ "$i" -gt 0 ] && printf '\n---\n\n'
            _dash_unlock_emit "$results" "$i"
        done
    fi
}

_dash_admin() {
    local action="${1:-status}"
    case "$action" in
        setup)
            echo "Running first-time setup..."
            dcli sync || return 1
            dcli configure save-master-password true
            # Try biometric unlock; fall back to no presence check on devices
            # without biometric hardware. With save-master-password=true the
            # master password lives in the OS keychain, so the vault still
            # unlocks without prompting in both modes.
            if dcli configure user-presence --method biometrics 2>/dev/null; then
                echo "✓ dcli configured with biometric unlock"
            else
                dcli configure user-presence --method none >/dev/null 2>&1 || true
                echo "✓ dcli configured (no biometrics — master password cached in OS keychain)"
            fi
            ;;
        sync)
            _dash_ensure_setup || return 1
            dcli sync
            ;;
        status)
            echo "dcli version: $(dcli --version 2>/dev/null || echo 'not installed')"
            local account
            account="$(dcli accounts whoami 2>/dev/null)"
            echo "logged in as: ${account:-not logged in}"
            echo "audit log:    $HOME/.dash.log ($(wc -l < "$HOME/.dash.log" 2>/dev/null || echo 0) entries)"
            ;;
        lock)
            _dash_ensure_setup || return 1
            dcli accounts logout
            echo "✓ vault locked"
            ;;
        log)
            tail -20 "$HOME/.dash.log" 2>/dev/null || echo "no log yet"
            ;;
        *)
            echo "Usage: dash admin [setup|sync|status|lock|log]" >&2
            return 1
            ;;
    esac
}
