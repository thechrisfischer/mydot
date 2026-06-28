#!/bin/bash

# Mirror Claude Desktop extensions into Claude Code's mcpServers config.
#
# Reads each extension's manifest.json (entry point, env schema) and the
# matching Claude Extensions Settings/<id>.json (enabled flag, user values),
# then writes a stdio entry into ~/.claude.json under .mcpServers.
#
# Sensitive user_config values are encrypted on disk by Desktop, so they
# can't be copied. Instead, sensitive entries are emitted as ${ENV_VAR}
# references (uppercase of the user_config key) — Claude Code expands these
# from the shell at launch. Set the matching env vars in
# ~/.bash/credentials.bash (e.g. grepler_token → GREPLER_TOKEN).
#
# Entries previously added by this function are tagged with
# _source: "claude-extension:<id>" so a re-run can sweep extensions that
# were uninstalled or disabled in Desktop.
dot-claude-sync() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: dot-claude-sync [--dry-run]

Mirrors enabled Claude Desktop extensions into ~/.claude.json's mcpServers.
Sensitive values from each extension's user_config become ${ENV_VAR} refs
(uppercase of the user_config key); set those vars in ~/.bash/credentials.bash.
Re-run after installing, updating, or disabling a Desktop extension.

  --dry-run    Show planned changes without writing.
EOF
        return 0
    fi

    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "dot-claude-sync: macOS only (Claude Desktop extensions don't exist on Linux)"
        return 0
    fi
    if ! command -v jq &>/dev/null; then
        echo "dot-claude-sync: jq not found (brew install jq or sudo port install jq)"
        return 1
    fi

    local dry_run=0
    [[ "$1" == "--dry-run" ]] && dry_run=1

    local ext_dir="$HOME/Library/Application Support/Claude/Claude Extensions"
    local settings_dir="$HOME/Library/Application Support/Claude/Claude Extensions Settings"
    local code_config="$HOME/.claude.json"

    if [[ ! -d "$ext_dir" ]]; then
        echo "dot-claude-sync: no extensions directory at $ext_dir"
        return 0
    fi
    [[ -f "$code_config" ]] || echo '{"mcpServers":{}}' > "$code_config"

    local -a kept_names=()
    local ext_path manifest ext_id settings_file

    for ext_path in "$ext_dir"/*/; do
        [[ -d "$ext_path" ]] || continue
        manifest="$ext_path/manifest.json"
        [[ -f "$manifest" ]] || continue
        ext_id="$(basename "$ext_path")"
        settings_file="$settings_dir/$ext_id.json"

        if [[ -f "$settings_file" ]]; then
            local enabled
            enabled=$(jq -r '.isEnabled // true' "$settings_file")
            if [[ "$enabled" == "false" ]]; then
                echo "→ skipping $ext_id (disabled in Claude Desktop)"
                continue
            fi
        fi

        local server_name
        server_name=$(jq -r '.name // empty' "$manifest" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
        if [[ -z "$server_name" ]]; then
            echo "⚠️  $ext_id: manifest missing .name — skipping"
            continue
        fi

        local cmd
        cmd=$(jq -r '.server.mcp_config.command // empty' "$manifest")
        if [[ -z "$cmd" ]]; then
            echo "⚠️  $ext_id: manifest has no server.mcp_config.command — skipping"
            continue
        fi

        # Resolve ${__dirname} in args to the absolute extension directory.
        local args_json
        args_json=$(jq -c --arg dir "${ext_path%/}" \
            '[.server.mcp_config.args[]? | gsub("\\$\\{__dirname\\}"; $dir)]' "$manifest")

        # Build env: ${user_config.<key>} → ${KEY_UPPER} if sensitive,
        # else literal value from settings (or schema default).
        local user_values='{}'
        [[ -f "$settings_file" ]] && user_values=$(jq -c '.userConfig // {}' "$settings_file")

        local env_json
        env_json=$(jq -c --argjson uv "$user_values" '
            (.user_config // {}) as $uc
            | (.server.mcp_config.env // {}) as $env
            | reduce ($env | to_entries[]) as $e ({};
                .[$e.key] = (
                    ($e.value | tostring) as $v
                    | if ($v | test("^\\$\\{user_config\\.[^}]+\\}$"))
                      then ($v | capture("^\\$\\{user_config\\.(?<k>[^}]+)\\}$").k) as $k
                        | if ($uc[$k].sensitive // false)
                          then "${" + ($k | ascii_upcase) + "}"
                          else ($uv[$k] // $uc[$k].default // "")
                          end
                      else $v
                      end
                )
            )
        ' "$manifest")

        kept_names+=("$server_name")

        local entry
        entry=$(jq -n \
            --arg cmd "$cmd" \
            --argjson args "$args_json" \
            --argjson env "$env_json" \
            --arg src "claude-extension:$ext_id" \
            '{type: "stdio", command: $cmd, args: $args, env: $env, _source: $src}')

        echo "✓ $server_name ← $ext_id"
        if (( dry_run )); then
            echo "$entry" | jq .
            continue
        fi

        local tmp
        tmp=$(mktemp)
        if jq --arg name "$server_name" --argjson entry "$entry" \
            '.mcpServers[$name] = $entry' "$code_config" > "$tmp"; then
            mv "$tmp" "$code_config"
        else
            rm -f "$tmp"
            echo "❌ failed to write $server_name"
            return 1
        fi
    done

    # Sweep: drop entries we previously added whose extension is gone/disabled.
    local kept_json
    if (( ${#kept_names[@]} )); then
        kept_json=$(printf '%s\n' "${kept_names[@]}" | jq -R . | jq -s -c .)
    else
        kept_json='[]'
    fi
    local stale
    stale=$(jq -r --argjson kept "$kept_json" '
        (.mcpServers // {}) | to_entries
        | map(select(((.value._source // "") | startswith("claude-extension:"))
                     and (([.key] | inside($kept)) | not)))
        | .[].key
    ' "$code_config")

    if [[ -n "$stale" ]]; then
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            echo "🧹 removing $name (extension no longer present/enabled)"
            (( dry_run )) && continue
            local tmp
            tmp=$(mktemp)
            if jq --arg name "$name" 'del(.mcpServers[$name])' "$code_config" > "$tmp"; then
                mv "$tmp" "$code_config"
            else
                rm -f "$tmp"
            fi
        done <<< "$stale"
    fi

    (( dry_run )) && echo "(dry run — no changes written)"
    echo "Done. Restart Claude Code to pick up MCP changes."
}
