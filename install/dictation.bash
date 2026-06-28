#!/bin/bash

function install_dictation {
    if [[ "$(uname -s)" != "Linux" ]]; then
        _install_step_done "dictation" "skipped (Linux only)"
        return 0
    fi

    _install_voxtype_linux
}

function _install_voxtype_linux {
    if ! command -v apt-get &>/dev/null; then
        _install_step_fail "voxtype" "apt-based Linux required"
        return 1
    fi

    _apt_update_once || return 1
    _install_step_start "voxtype deps" "apt install dictation dependencies..."
    if sudo apt-get install -y \
        ca-certificates wget wtype wl-clipboard libnotify-bin pipewire-alsa playerctl \
        xclip xdotool ydotool \
        &>/dev/null; then
        _install_step_done_changed "voxtype deps" "installed (apt)"
    else
        _install_step_fail "voxtype deps" "apt install failed"
        return 1
    fi

    _install_voxtype_deb || return 1
    _configure_voxtype || return 1
}

function _install_voxtype_deb {
    local version="0.7.2"
    if command -v voxtype &>/dev/null && voxtype --version 2>/dev/null | grep -q " $version$"; then
        _install_step_done "voxtype" "already installed ($(voxtype --version))"
        return 0
    fi

    local tmp
    tmp=$(mktemp -d) || return 1
    _install_step_start "voxtype" "installing $version deb..."
    if wget -q "https://github.com/peteonrails/voxtype/releases/download/v$version/voxtype_${version}-1_amd64.deb" \
        -O "$tmp/voxtype.deb" \
        && sudo apt-get install -y "$tmp/voxtype.deb" &>/dev/null; then
        rm -rf "$tmp"
        _install_step_done_changed "voxtype" "installed ($(voxtype --version))"
    else
        rm -rf "$tmp"
        _install_step_fail "voxtype" "install failed"
        return 1
    fi
}

function _configure_voxtype {
    mkdir -p "$HOME/.config/voxtype"
    if [[ -f /etc/voxtype/config.toml ]]; then
        cp -f /etc/voxtype/config.toml "$HOME/.config/voxtype/config.toml"
    else
        _install_step_fail "voxtype config" "/etc/voxtype/config.toml not found"
        return 1
    fi

    python3 - <<'PY'
from pathlib import Path

p = Path.home() / ".config/voxtype/config.toml"
s = p.read_text()
s = s.replace('# engine = "whisper"', 'engine = "whisper"')
s = s.replace('mode = "paste"', 'mode = "type"', 1)
if 'driver_order = ["ydotool", "clipboard"]' not in s:
    s = s.replace(
        'type_delay_ms = 0',
        'type_delay_ms = 0\ndriver_order = ["ydotool", "clipboard"]',
        1,
    )
s = s.replace('on_recording_start = false', 'on_recording_start = true')
s = s.replace('on_recording_stop = false', 'on_recording_stop = true')
p.write_text(s)
PY

    _install_step_start "voxtype model" "installing base.en Whisper model..."
    if voxtype setup --download --model base.en --no-post-install &>/dev/null; then
        _install_step_done_changed "voxtype model" "base.en installed"
    else
        _install_step_fail "voxtype model" "download failed"
        return 1
    fi

    _install_step_start "voxtype service" "installing user service..."
    if voxtype setup systemd &>/dev/null \
        && _install_ydotoold_service \
        && _patch_voxtype_service \
        && systemctl --user disable voxtype &>/dev/null \
        && systemctl --user enable --now voxtype.service &>/dev/null \
        && systemctl --user restart voxtype &>/dev/null; then
        _install_step_done_changed "voxtype service" "enabled and started"
    else
        _install_step_fail "voxtype service" "start failed"
        return 1
    fi
}

function _install_ydotoold_service {
    local service_tmp
    service_tmp=$(mktemp) || return 1
    cat > "$service_tmp" <<EOF
[Unit]
Description=ydotool daemon for dotfiles dictation
After=multi-user.target

[Service]
Type=simple
ExecStartPre=/usr/bin/rm -f /tmp/.ydotool_socket
ExecStart=/usr/bin/ydotoold -p /tmp/.ydotool_socket -P 0666
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

    if sudo install -m 0644 "$service_tmp" /etc/systemd/system/ydotoold-dotfiles.service \
        && sudo systemctl daemon-reload \
        && sudo systemctl enable ydotoold-dotfiles.service &>/dev/null \
        && sudo systemctl restart ydotoold-dotfiles.service; then
        rm -f "$service_tmp"
        systemctl --user disable --now ydotool &>/dev/null || true
    else
        rm -f "$service_tmp"
        return 1
    fi
}

function _patch_voxtype_service {
    cat > "$HOME/.config/voxtype/start-voxtype.sh" <<'EOF'
#!/bin/bash
set -e
export DISPLAY="${DISPLAY:-:0}"
export YDOTOOL_SOCKET="${YDOTOOL_SOCKET:-/tmp/.ydotool_socket}"
if [[ -z "${XAUTHORITY:-}" ]]; then
    XAUTHORITY=$(ps -eo args | sed -n 's/.*-auth \([^ ]*\).*/\1/p' | head -n 1)
    [[ -n "$XAUTHORITY" ]] && export XAUTHORITY
fi
exec /usr/bin/voxtype daemon
EOF
    chmod +x "$HOME/.config/voxtype/start-voxtype.sh"

    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/voxtype.service" <<EOF
[Unit]
Description=Voxtype push-to-talk voice-to-text daemon
Documentation=https://voxtype.io
After=default.target

[Service]
Type=simple
ExecStart=$HOME/.config/voxtype/start-voxtype.sh
Restart=on-failure
RestartSec=5
Environment=XDG_RUNTIME_DIR=%t
Environment=DISPLAY=:0
Environment=YDOTOOL_SOCKET=/tmp/.ydotool_socket

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
}
