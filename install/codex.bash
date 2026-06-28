#!/bin/bash

DOTFILES_CODEX_PLUGINS=(
    "superpowers@openai-curated"
    "build-web-apps@openai-curated"
    "browser-use@openai-bundled"
    "documents@openai-primary-runtime"
    "spreadsheets@openai-primary-runtime"
    "presentations@openai-primary-runtime"
)

function _codex_config_file {
    printf '%s\n' "$HOME/.codex/config.toml"
}

function _enable_codex_plugin {
    local plugin_ref="$1"
    local config
    local table
    local tmp

    config=$(_codex_config_file)
    table="[plugins.\"$plugin_ref\"]"

    mkdir -p "$(dirname "$config")"
    touch "$config"
    tmp=$(mktemp)

    awk -v table="$table" '
        BEGIN {
            in_table = 0
            found_table = 0
            found_enabled = 0
        }

        $0 == table {
            if (in_table && !found_enabled) {
                print "enabled = true"
            }
            in_table = 1
            found_table = 1
            found_enabled = 0
            print
            next
        }

        in_table && /^\[/ {
            if (!found_enabled) {
                print "enabled = true"
            }
            in_table = 0
        }

        in_table && $0 ~ /^[[:space:]]*enabled[[:space:]]*=/ {
            print "enabled = true"
            found_enabled = 1
            next
        }

        { print }

        END {
            if (in_table && !found_enabled) {
                print "enabled = true"
            }
            if (!found_table) {
                print ""
                print table
                print "enabled = true"
            }
        }
    ' "$config" > "$tmp"

    mv "$tmp" "$config"
}

function install_codex {
    echo "Installing Codex configuration..."

    if ! command -v codex &>/dev/null; then
        echo "❌ codex not found — run './install.sh packages' first"
        return 1
    fi

    mkdir -p "$HOME/.codex"

    # Refresh configured marketplaces when possible. Built-in marketplaces may
    # not appear in config.toml on a fresh install until Codex initializes them.
    _install_progress "Codex marketplaces: refreshing"
    codex plugin marketplace upgrade >/dev/null 2>&1 || true

    local plugin
    for plugin in "${DOTFILES_CODEX_PLUGINS[@]}"; do
        _enable_codex_plugin "$plugin"
        _install_progress "Codex plugin $plugin: enabled"
    done

    echo "Codex configuration installed!"
    echo "⚠️  Start a new Codex session for plugin changes to take effect"
}
