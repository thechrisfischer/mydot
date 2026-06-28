#!/bin/bash
#
# Fly.io account switcher — vault-backed, no global token export.
#
# WHY THIS REPLACES THE OLD VERSION
#   The old switcher relied on FLY_TOKEN_WORK / FLY_TOKEN_PERSONAL being synced
#   into the shell env, and *globally* exported FLY_API_TOKEN (defaulting to
#   personal). That global export SHADOWS `fly auth login`, the synced tokens go
#   stale, and every child process inherits the secrets. This version stores
#   nothing in the environment: it fetches the one token you ask for from the
#   Grepler Vault, per command, and never exports it globally.
#
# ACCOUNTS (alias → human)
#   personal  = you@personal.example
#   work  = you@work.example
#
# VAULT LAYOUT  (personal scope)
#   client=fly / service=<alias> / environment=prod / key=API_TOKEN
#
# REQUIRES
#   GREPLER_VAULT_TOKEN — a read-only `grpl_vault_…` token (mint with
#   vault_api_token_issue(scope="personal", capability="read")). This single
#   read token is the only Fly-related secret in your shell.

_DOT_FLY_VAULT_BASE="${GREPLER_URL:-https://grepler.dev}"
_DOT_FLY_CACHE_DIR="${TMPDIR:-/tmp}/dot-fly-cache.$(id -u)"

_dot_fly_account() {
    case "$1" in
        personal)  echo "you@personal.example" ;;
        work)  echo "you@work.example" ;;
        *) return 1 ;;
    esac
}

# Fetch fly/<alias>/prod/API_TOKEN from the vault, cached per-session (0600).
_dot_fly_token() {
    local alias="$1" cache="$_DOT_FLY_CACHE_DIR/$1"
    [[ -s "$cache" ]] && { cat "$cache"; return 0; }
    [[ -n "${GREPLER_VAULT_TOKEN:-}" ]] || { echo "dot-fly: GREPLER_VAULT_TOKEN not set (mint a read-only vault token)" >&2; return 1; }
    _dot_fly_account "$alias" >/dev/null || { echo "dot-fly: unknown account '$alias'" >&2; return 1; }
    local val
    val="$(curl -fsS -H "Authorization: Bearer $GREPLER_VAULT_TOKEN" \
        "$_DOT_FLY_VAULT_BASE/v1/vault/secrets/API_TOKEN?client=fly&service=$alias&environment=prod" \
        2>/dev/null | jq -r '.value // empty')"
    [[ -n "$val" ]] || { echo "dot-fly: no token at fly/$alias/prod/API_TOKEN in the vault" >&2; return 1; }
    ( umask 077; mkdir -p "$_DOT_FLY_CACHE_DIR"; printf '%s' "$val" > "$cache" )
    printf '%s' "$val"
}

dot-fly() {
    local sub="${1:-}"; shift 2>/dev/null || true
    case "$sub" in
        as)   # run ONE command as an account, scoped to this call only
            local alias="${1:-}"; shift 2>/dev/null || true
            local tok; tok="$(_dot_fly_token "$alias")" || return 1
            FLY_API_TOKEN="$tok" fly "$@" ;;
        use)  # set FLY_API_TOKEN for THIS shell only (explicit)
            local alias="${1:-}"
            local tok; tok="$(_dot_fly_token "$alias")" || return 1
            export FLY_API_TOKEN="$tok"
            echo "✓ this shell → $(_dot_fly_account "$alias") ($alias).  'dot-fly off' to clear." ;;
        off)  unset FLY_API_TOKEN; echo "✓ FLY_API_TOKEN cleared — fly now uses your interactive login" ;;
        who)  fly auth whoami 2>/dev/null ;;
        refresh) rm -rf "$_DOT_FLY_CACHE_DIR"; echo "✓ token cache cleared" ;;
        *) cat >&2 <<'EOF'
Usage:
  dot-fly as  <personal|work> <fly args...>              one command as that account
  dot-fly use <alias>                                        set this shell to that account
  dot-fly off                                                clear → use interactive login
  dot-fly who                                                show current fly identity
  dot-fly refresh                                            drop cached vault tokens
EOF
            return 1 ;;
    esac
}
