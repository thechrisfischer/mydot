#!/bin/bash

# Shared helper functions for the installer

# Quiet mode: section summaries + selected progress. Use INSTALL_VERBOSE=1
# or --verbose for full command output.
INSTALL_VERBOSE="${INSTALL_VERBOSE:-0}"
for arg in "$@"; do
  [[ "$arg" == --verbose || "$arg" == -v ]] && INSTALL_VERBOSE=1 && break
done

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_GREEN='\033[32m'
  C_RED='\033[31m'
  C_RESET='\033[0m'
else
  C_GREEN='' C_RED='' C_RESET=''
fi

_section_run() {
  local name="$1"
  shift
  local section_start status
  section_start=$(date +%s)
  if [[ "$INSTALL_VERBOSE" == 1 ]]; then
    printf "\n==> %s\n" "$name"
    "$@"
    return $?
  fi
  local tmp previous_capture previous_capture_set
  tmp=$(mktemp)
  printf "\n==> %s\n" "$name"
  previous_capture="${_DOTFILES_SECTION_CAPTURE:-}"
  previous_capture_set=0
  [[ -n "${_DOTFILES_SECTION_CAPTURE+x}" ]] && previous_capture_set=1
  _DOTFILES_SECTION_CAPTURE=1
  _DOTFILES_STEPS_OK=0
  _DOTFILES_STEPS_CHANGED=0
  _DOTFILES_STEPS_FAILED=0
  _DOTFILES_STEP_INFLIGHT=""
  export _DOTFILES_SECTION_CAPTURE _DOTFILES_STEPS_OK _DOTFILES_STEPS_CHANGED _DOTFILES_STEPS_FAILED _DOTFILES_STEP_INFLIGHT
  "$@" > "$tmp" 2>&1
  status=$?
  _install_step_clear_inflight
  if [[ "$previous_capture_set" == 1 ]]; then
    _DOTFILES_SECTION_CAPTURE="$previous_capture"
  else
    unset _DOTFILES_SECTION_CAPTURE
  fi

  local elapsed=$(( $(date +%s) - section_start ))
  local summary=""
  local total=$(( _DOTFILES_STEPS_OK + _DOTFILES_STEPS_CHANGED + _DOTFILES_STEPS_FAILED ))
  if [[ "$total" -gt 0 ]]; then
    summary=$(printf "  %d ok · %d changed · %d failed   %ds" \
      "$_DOTFILES_STEPS_OK" "$_DOTFILES_STEPS_CHANGED" "$_DOTFILES_STEPS_FAILED" "$elapsed")
  fi

  if [[ "$status" -eq 0 ]]; then
    printf "%-12s ${C_GREEN}✓${C_RESET}%s\n" "$name" "$summary"
  else
    printf "%-12s ${C_RED}✗${C_RESET}%s\n" "$name" "$summary"
    cat "$tmp"
    rm -f "$tmp"
    return "$status"
  fi
  rm -f "$tmp"
}

function _install_out_target {
    # Resolve where streamed progress should be written. During a captured
    # section, stdout has been redirected to a temp file that may be discarded
    # — so emit to /dev/tty directly when available. Outside capture, just
    # write to stdout. The probe is cached on first call (per shell) because
    # `-w /dev/tty` can pass when no controlling terminal is actually attached
    # (e.g., subprocess under a non-interactive runner), but the subsequent
    # write fails with "Device not configured". An empty probe write catches
    # that up front.
    if [[ -z "${_DOTFILES_TTY_AVAILABLE:-}" ]]; then
        # Use a subshell so a failed redirect to /dev/tty doesn't pollute
        # the outer shell's stderr — `2>/dev/null` on the builtin alone is
        # not enough on bash 3.2 (macOS) because the redirection error is
        # reported before stderr is rebound.
        if (exec 2>/dev/null; : > /dev/tty); then
            _DOTFILES_TTY_AVAILABLE=1
        else
            _DOTFILES_TTY_AVAILABLE=0
        fi
        export _DOTFILES_TTY_AVAILABLE
    fi
    if [[ "${_DOTFILES_SECTION_CAPTURE:-0}" == 1 && "$_DOTFILES_TTY_AVAILABLE" == 1 ]]; then
        echo /dev/tty
    else
        echo /dev/stdout
    fi
}

function _install_step_clear_inflight {
    # If a step row was left as a partial line, end it cleanly so subsequent
    # output (captured log dumps, summary lines) starts on a fresh line.
    if [[ -n "${_DOTFILES_STEP_INFLIGHT:-}" ]]; then
        local target
        target=$(_install_out_target)
        printf '\r\033[K' > "$target" 2>/dev/null
        _DOTFILES_STEP_INFLIGHT=""
    fi
}

function _install_log {
    _install_step_clear_inflight
    local target
    target=$(_install_out_target)
    printf '%s\n' "$*" > "$target"
}

function _install_progress {
    _install_log "  - $*"
}

function _install_step_start {
    local name="$1" action="${2:-installing...}"
    local target
    target=$(_install_out_target)
    _DOTFILES_STEP_INFLIGHT="$name"
    if [[ "$target" == /dev/tty ]] && [[ -z "${NO_COLOR:-}" ]]; then
        printf '\r\033[K  \033[33m⋯\033[0m %-22s %s' "$name" "$action" > "$target"
    else
        printf '  ⋯ %-22s %s\n' "$name" "$action" > "$target"
    fi
}

function _install_step_done {
    local name="$1" result="${2:-done}"
    _DOTFILES_STEPS_OK=$(( ${_DOTFILES_STEPS_OK:-0} + 1 ))
    _DOTFILES_STEP_INFLIGHT=""
    local target
    target=$(_install_out_target)
    if [[ "$target" == /dev/tty ]] && [[ -z "${NO_COLOR:-}" ]]; then
        printf '\r\033[K  \033[32m✓\033[0m %-22s %s\n' "$name" "$result" > "$target"
    else
        printf '  ✓ %-22s %s\n' "$name" "$result" > "$target"
    fi
}

function _install_step_done_changed {
    local name="$1" result="${2:-installed}"
    _DOTFILES_STEPS_CHANGED=$(( ${_DOTFILES_STEPS_CHANGED:-0} + 1 ))
    _DOTFILES_STEP_INFLIGHT=""
    local target
    target=$(_install_out_target)
    if [[ "$target" == /dev/tty ]] && [[ -z "${NO_COLOR:-}" ]]; then
        printf '\r\033[K  \033[32m✓\033[0m %-22s \033[36m%s\033[0m\n' "$name" "$result" > "$target"
    else
        printf '  ✓ %-22s %s\n' "$name" "$result" > "$target"
    fi
}

function _install_step_fail {
    local name="$1" reason="${2:-failed}"
    _DOTFILES_STEPS_FAILED=$(( ${_DOTFILES_STEPS_FAILED:-0} + 1 ))
    _DOTFILES_STEP_INFLIGHT=""
    local target
    target=$(_install_out_target)
    if [[ "$target" == /dev/tty ]] && [[ -z "${NO_COLOR:-}" ]]; then
        printf '\r\033[K  \033[31m✗\033[0m %-22s %s\n' "$name" "$reason" > "$target"
    else
        printf '  ✗ %-22s %s\n' "$name" "$reason" > "$target"
    fi
}

function timestamp {
    local stamp
    stamp=$(date +%Y-%m-%d:%H:%M:%S | sed 's/-/_/g' | sed 's/:/_/g')
    echo "$stamp"
}

function _verify_repo_complete {
    # Guard against running from an incomplete copy of the repo. The classic
    # failure is `cp ~/Downloads/mydot-main/* ~/dest/` — a bare `*` glob does
    # NOT match dotfiles, so the entire `.bash/` tree, `.bashrc`, etc. are
    # silently left behind. The installer then "succeeds" (green checkmarks)
    # while copying nothing and nothing sources. Catch it up front with a
    # precise message instead of burning an hour and three reruns.
    local repo="${DOTFILES_REPO_DIR:?}"
    local missing=()
    local required=(
        ".bashrc"
        ".bash/prefs.bash"
        ".bash/functions/_loader.bash"
    )
    local f
    for f in "${required[@]}"; do
        [[ -e "$repo/$f" ]] || missing+=("$f")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0

    echo "❌ This looks like an incomplete copy of the dotfiles repo." >&2
    echo "   Missing required files in $repo:" >&2
    for f in "${missing[@]}"; do
        echo "     - $f" >&2
    done
    echo "" >&2
    echo "   Dotfiles (hidden files) are missing — this happens when the repo is" >&2
    echo "   copied with a bare glob, e.g. \`cp /path/dotfiles-main/* dest/\`, which" >&2
    echo "   skips everything starting with a dot. Get a complete copy instead:" >&2
    echo "" >&2
    echo "     git clone https://github.com/thechrisfischer/mydot.git ~/Code/mydot" >&2
    echo "     cd ~/Code/mydot && ./install.sh all" >&2
    echo "" >&2
    echo "   Or, if you already extracted a download to e.g. ~/Downloads/mydot-main," >&2
    echo "   run the installer from there directly (do not \`cp dir/*\` first):" >&2
    echo "" >&2
    echo "     cd ~/Downloads/mydot-main && ./install.sh all" >&2
    echo "" >&2
    echo "   To copy a download into a working dir including dotfiles, use:" >&2
    echo "     cp -R ~/Downloads/mydot-main/. ~/Code/mydot/" >&2
    return 1
}

function _os_type {
    uname -s
}

function _is_macos {
    [[ "$(_os_type)" == "Darwin" ]]
}

function _is_linux {
    [[ "$(_os_type)" == "Linux" ]]
}

function _macos_major {
    ! _is_macos && return 1
    sw_vers -productVersion 2>/dev/null | cut -d. -f1
}

function _sysctl_value {
    local key="$1"
    if command -v sysctl &>/dev/null; then
        sysctl -n "$key" 2>/dev/null
    elif [[ -x /usr/sbin/sysctl ]]; then
        /usr/sbin/sysctl -n "$key" 2>/dev/null
    else
        return 1
    fi
}

function _is_apple_silicon {
    _is_macos || return 1
    [[ "$(_sysctl_value hw.optional.arm64 || true)" == 1 ]]
}

function _is_rosetta_process {
    _is_macos || return 1
    [[ "$(_sysctl_value sysctl.proc_translated || true)" == 1 ]]
}

function _needs_arm64_reexec {
    _is_apple_silicon || return 1
    _is_rosetta_process || return 1
    [[ "${DOTFILES_REEXEC_ARM64:-0}" != 1 ]] || return 1
    [[ "${DOTFILES_ALLOW_ROSETTA:-0}" != 1 ]] || return 1
}

function _maybe_reexec_arm64 {
    local arch_bin="${DOTFILES_ARCH_BIN:-/usr/bin/arch}"
    _needs_arm64_reexec || return 0
    if [[ ! -x "$arch_bin" || ! -x /bin/bash ]]; then
        echo "⚠️  Apple Silicon process is running under Rosetta, but arch/bash re-exec is unavailable"
        return 0
    fi
    echo "Apple Silicon detected under Rosetta — restarting installer under arm64..."
    export DOTFILES_REEXEC_ARM64=1
    exec "$arch_bin" -arm64 /bin/bash "$@"
}

function _linux_package_manager {
    command -v apt-get &>/dev/null && { echo apt; return 0; }
    command -v dnf &>/dev/null && { echo dnf; return 0; }
    command -v yum &>/dev/null && { echo yum; return 0; }
    return 1
}

function _linux_packages_for {
    local name="$1"
    local pm="$2"

    case "$name:$pm" in
        python3:*) echo "python3" ;;
        node:*) echo "nodejs npm" ;;
        npm:*) echo "npm" ;;
        jq:*) echo "jq" ;;
        shellcheck:apt|shellcheck:dnf) echo "shellcheck" ;;
        shellcheck:yum) echo "ShellCheck" ;;
        flake8:*) echo "python3-flake8" ;;
        virtualenv:apt) echo "python3-venv python3-virtualenv" ;;
        virtualenv:dnf|virtualenv:yum) echo "python3-virtualenv" ;;
        pipx:*) echo "pipx" ;;
        gh:*) echo "gh" ;;
        screen:*) echo "screen" ;;
        tmux:*) echo "tmux" ;;
        cmatrix:*) echo "cmatrix" ;;
        awscli:*) echo "awscli" ;;
        git:*) echo "git" ;;
        wget:*) echo "wget" ;;
        tree:*) echo "tree" ;;
        ccache:*) echo "ccache" ;;
        uv:*|flyctl:*) echo "" ;;
        *) echo "$name" ;;
    esac
}

function _gh_apt_source_line {
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$(dpkg --print-architecture 2>/dev/null || echo amd64)"
}

function _linux_install_gh {
    command -v gh >/dev/null 2>&1 && { _install_step_done "gh" "already installed"; return 0; }
    _ensure_sudo_cached || { _install_step_fail "gh" "sudo required"; return 1; }
    _install_step_start "gh" "adding cli.github.com apt repo..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    if ! curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; then
        _install_step_fail "gh" "keyring import failed"; return 1
    fi
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    _gh_apt_source_line | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    _DOTFILES_APT_UPDATED=0  # force a refresh now that a new source exists
    _apt_update_once || return 1
    if sudo apt-get install -y gh >/dev/null 2>&1; then
        _install_step_done_changed "gh" "installed (apt + cli.github.com)"
    else
        _install_step_fail "gh" "apt install failed"; return 1
    fi
}

function _apt_update_once {
    if [[ "${DOTFILES_SKIP_APT_UPDATE:-0}" == 1 ]]; then
        _install_progress "apt metadata update skipped (DOTFILES_SKIP_APT_UPDATE=1)"
        return 0
    fi
    [[ "${_DOTFILES_APT_UPDATED:-0}" == 1 ]] && return 0
    _install_progress "apt: updating metadata once"
    _ensure_sudo_cached || return 1
    sudo apt-get update || return 1
    _DOTFILES_APT_UPDATED=1
}

function _linux_pkg_install {
    local name="$1"
    local pm packages
    local package_list=()

    pm=$(_linux_package_manager) || {
        _install_step_fail "$name" "no supported Linux package manager"
        return 1
    }

    if [[ "$name" == gh && "$pm" == apt ]]; then
        _linux_install_gh; return $?
    fi

    packages=$(_linux_packages_for "$name" "$pm")
    if [[ -z "$packages" ]]; then
        case "$name" in
            flyctl) _install_flyctl_direct; return $? ;;
            uv) _install_uv_direct; return $? ;;
            *) _install_step_fail "$name" "no Linux package mapping"; return 1 ;;
        esac
    fi
    read -r -a package_list <<< "$packages"

    case "$pm" in
        apt)
            _apt_update_once || return 1
            _install_step_start "$name" "apt install ($packages)..."
            _ensure_sudo_cached || { _install_step_fail "$name" "sudo required"; return 1; }
            if sudo apt-get install -y "${package_list[@]}" &>/dev/null; then
                _install_step_done_changed "$name" "installed (apt)"
            else
                _install_step_fail "$name" "apt install failed"
                return 1
            fi
            ;;
        dnf)
            _install_step_start "$name" "dnf install ($packages)..."
            _ensure_sudo_cached || { _install_step_fail "$name" "sudo required"; return 1; }
            if sudo dnf install -y "${package_list[@]}" &>/dev/null; then
                _install_step_done_changed "$name" "installed (dnf)"
            else
                _install_step_fail "$name" "dnf install failed"
                return 1
            fi
            ;;
        yum)
            _install_step_start "$name" "yum install ($packages)..."
            _ensure_sudo_cached || { _install_step_fail "$name" "sudo required"; return 1; }
            if sudo yum install -y "${package_list[@]}" &>/dev/null; then
                _install_step_done_changed "$name" "installed (yum)"
            else
                _install_step_fail "$name" "yum install failed"
                return 1
            fi
            ;;
    esac
}

function _prefer_macports {
    # True on macOS <15, where Homebrew no longer ships bottles and every
    # formula would otherwise build from source.
    local major
    major=$(_macos_major) || return 1
    [[ -n "$major" && "$major" -lt 15 ]]
}

function _macports_pkg_slug_from_version {
    # Pure mapping from sw_vers -productVersion output → MacPorts-*-{slug}.pkg segment.
    local pv="$1"
    [[ -n "$pv" ]] || return 1
    case "$pv" in
        10.15.*) printf '%s\n' "10.15-Catalina" ;;
        10.14.*) printf '%s\n' "10.14-Mojave" ;;
        10.13.*) printf '%s\n' "10.13-HighSierra" ;;
        10.12.*) printf '%s\n' "10.12-Sierra" ;;
        10.11.*) printf '%s\n' "10.11-ElCapitan" ;;
        10.10.*) printf '%s\n' "10.10-Yosemite" ;;
        10.9.*)  printf '%s\n' "10.9-Mavericks" ;;
        10.8.*)  printf '%s\n' "10.8-MountainLion" ;;
        10.7.*)  printf '%s\n' "10.7-Lion" ;;
        10.6.*)  printf '%s\n' "10.6-SnowLeopard" ;;
        10.5.*)
            echo "❌ MacPorts auto-install for Mac OS X 10.5 ships as .dmg only — install manually from https://www.macports.org/install.php" >&2
            return 1
            ;;
        11.*) printf '%s\n' "11-BigSur" ;;
        12.*) printf '%s\n' "12-Monterey" ;;
        13.*) printf '%s\n' "13-Ventura" ;;
        14.*) printf '%s\n' "14-Sonoma" ;;
        15.*) printf '%s\n' "15-Sequoia" ;;
        *)
            echo "❌ No MacPorts .pkg mapping for macOS $pv — install MacPorts manually from https://www.macports.org/install.php" >&2
            return 1
            ;;
    esac
}

function _macports_pkg_slug {
    # MacPorts GitHub release assets are named MacPorts-<ver>-<slug>.pkg where <slug>
    # is "10.15-Catalina", "11-BigSur", ... — not just the major OS version (10.x needs
    # the minor release in the filename).
    local pv
    pv=$(/usr/bin/sw_vers -productVersion 2>/dev/null) || return 1
    [[ -n "$pv" ]] || return 1
    _macports_pkg_slug_from_version "$pv"
}

function _ensure_macports_path {
    # System-wide PATH entry for MacPorts. The .pkg installer usually writes
    # this, but occasionally doesn't stick (or got uninstalled). Safe to
    # re-run: content is fixed and sudo-gated.
    if [[ -r /etc/paths.d/MacPorts ]] && \
       grep -q "^/opt/local/bin$" /etc/paths.d/MacPorts 2>/dev/null; then
        return 0
    fi
    echo "Writing /etc/paths.d/MacPorts for system-wide PATH..."
    _ensure_sudo_cached || return 1
    echo -e "/opt/local/bin\n/opt/local/sbin" | sudo tee /etc/paths.d/MacPorts >/dev/null
}

function _ensure_macports {
    if command -v port &> /dev/null; then
        _ensure_macports_path
        return 0
    fi
    if [[ -x /opt/local/bin/port ]]; then
        export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
        _ensure_macports_path
        return 0
    fi
    local slug version pkg url tmp
    _is_macos || { echo "❌ MacPorts is macOS-only"; return 1; }
    slug=$(_macports_pkg_slug) || return 1
    version="2.10.5"
    pkg="MacPorts-${version}-${slug}.pkg"
    url="https://github.com/macports/macports-base/releases/download/v${version}/${pkg}"

    echo "MacPorts not found — installing $pkg..."
    _ensure_sudo_cached || { echo "❌ sudo access required to install MacPorts"; return 1; }

    tmp=$(mktemp -d)
    if ! curl -fsSL "$url" -o "$tmp/$pkg"; then
        echo "❌ Failed to download $url"
        rm -rf "$tmp"
        return 1
    fi
    sudo installer -pkg "$tmp/$pkg" -target /
    local status=$?
    rm -rf "$tmp"
    if [[ $status -ne 0 ]]; then
        echo "❌ MacPorts installer failed"
        return 1
    fi
    export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
    _ensure_macports_path
    echo "Syncing MacPorts ports tree..."
    sudo /opt/local/bin/port -q selfupdate || echo "⚠️  selfupdate failed (continuing)"
    _DOTFILES_MACPORTS_UPDATED=1
}

function _macports_selfupdate_once {
    if [[ "${DOTFILES_SKIP_MACPORTS_UPDATE:-0}" == 1 ]]; then
        _install_progress "MacPorts metadata update skipped (DOTFILES_SKIP_MACPORTS_UPDATE=1)"
        return 0
    fi
    [[ "${_DOTFILES_MACPORTS_UPDATED:-0}" == 1 ]] && return 0
    [[ -x /opt/local/bin/port ]] || return 1

    _install_progress "MacPorts: syncing ports tree once"
    _ensure_sudo_cached || return 1
    if sudo /opt/local/bin/port -q selfupdate; then
        _install_progress "MacPorts: metadata current"
    else
        _install_progress "MacPorts: selfupdate failed, using cached metadata"
    fi
    _DOTFILES_MACPORTS_UPDATED=1
}

function _sudo_prompt_channel {
    # Decide where to read the sudo password from. Prefer /dev/tty whenever it
    # is writable — that is the only channel that survives `curl | bash` (stdin
    # is the script) and captured sections (stdout/stderr redirected). Falls
    # back to stdin when it is a TTY, else "none" (headless — caller needs
    # DOTFILES_SUDO_PASSWORD).
    local tty_writable stdin_tty
    if [[ -n "${_DOTFILES_TEST_TTY_WRITABLE:-}" ]]; then
        tty_writable="$_DOTFILES_TEST_TTY_WRITABLE"
    else
        { [ -w /dev/tty ]; } 2>/dev/null && tty_writable=1 || tty_writable=0
    fi
    if [[ -n "${_DOTFILES_TEST_STDIN_TTY:-}" ]]; then
        stdin_tty="$_DOTFILES_TEST_STDIN_TTY"
    else
        [[ -t 0 ]] && stdin_tty=1 || stdin_tty=0
    fi
    if [[ "$tty_writable" == 1 ]]; then echo tty; return 0; fi
    if [[ "$stdin_tty" == 1 ]]; then echo stdin; return 0; fi
    echo none
}

function _dotfiles_sudo {
    # Use the real sudo binary, not a shell alias (Cursor sets `sudo -A`) and
    # never inherit SUDO_ASKPASS — both break non-interactive cache refresh.
    local sudo_bin
    sudo_bin=$(command -v sudo 2>/dev/null || true)
    [[ -n "$sudo_bin" ]] || sudo_bin=/usr/bin/sudo
    SUDO_ASKPASS= "$sudo_bin" "$@"
}

function _ensure_sudo_cached {
    # Drive prompts off the actual sudo cache state, not the keepalive PID:
    # a previously-spawned-but-dead keepalive used to leave us claiming
    # success while the cache was silently expired, so the next sudo call
    # mid-section would prompt the user a second time.
    if _dotfiles_sudo -n -v 2>/dev/null; then
        _spawn_sudo_keepalive
        return 0
    fi

    local msg="Caching sudo credentials for the install (you'll be prompted once)..."
    if [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
        if printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | _dotfiles_sudo -S -v 2>/dev/null; then
            _spawn_sudo_keepalive
            return 0
        fi
    fi

    case "$(_sudo_prompt_channel)" in
        tty)
            printf '%s\n' "$msg" > /dev/tty
            if ! _dotfiles_sudo -v < /dev/tty > /dev/tty 2>&1; then
                printf '❌ sudo access required\n' > /dev/tty
                return 1
            fi
            ;;
        stdin)
            echo "$msg"
            _dotfiles_sudo -v || { echo "❌ sudo access required"; return 1; }
            ;;
        none)
            echo "$msg" >&2
            echo "❌ sudo access required (no TTY — run from Terminal or set DOTFILES_SUDO_PASSWORD for this session)" >&2
            return 1
            ;;
    esac
    _spawn_sudo_keepalive
}

function _stop_sudo_keepalive {
    if [[ -n "${_DOTFILES_SUDO_KEEPALIVE_PID:-}" ]]; then
        kill "$_DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$_DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null || true
        unset _DOTFILES_SUDO_KEEPALIVE_PID
    fi
    trap - EXIT
}

function _spawn_sudo_keepalive {
    if [[ -n "${_DOTFILES_SUDO_KEEPALIVE_PID:-}" ]] && \
       kill -0 "$_DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null; then
        # Tests pin $$ to block spawning; never treat the installer shell as the worker.
        if [[ "$_DOTFILES_SUDO_KEEPALIVE_PID" == "$$" ]]; then
            unset _DOTFILES_SUDO_KEEPALIVE_PID
        else
            return 0
        fi
    fi
    local parent_pid=$$
    # Don't exit on a transient `sudo -n -v` failure — a single hiccup
    # (PAM contention, brief unavailability, etc.) used to kill the keepalive
    # permanently, after which the 5-min timestamp expired silently. Keep
    # looping so refresh resumes once sudo is reachable again.
    ( while kill -0 "$parent_pid" 2>/dev/null; do
        if ! _dotfiles_sudo -n -v 2>/dev/null && [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
            printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | _dotfiles_sudo -S -v 2>/dev/null
        fi
        sleep 50
      done ) 2>/dev/null &
    _DOTFILES_SUDO_KEEPALIVE_PID=$!
    disown "$_DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    export _DOTFILES_SUDO_KEEPALIVE_PID
    trap '[[ -n "${_DOTFILES_SUDO_KEEPALIVE_PID:-}" ]] && kill "$_DOTFILES_SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

function _dotfiles_github_auth_ok {
    command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1
}

# Interactive GitHub login via gh (HTTPS). Avoids requiring SSH keys for cloning.
function _dotfiles_ensure_github_auth {
    _dotfiles_github_auth_ok && return 0

    if [[ ! -t 0 ]]; then
        echo "❌ GitHub not authenticated. Run: gh auth login -h github.com -p https -w" >&2
        echo "   Or export GITHUB_TOKEN for non-interactive bootstrap." >&2
        return 1
    fi

    echo "GitHub login required (browser flow — HTTPS via gh, no SSH key required)."
    gh auth login -h github.com -p https -w
}

function _dotfiles_git_clone {
    local spec="$1"
    local dest="$2"
    local repo_spec="$spec"

    [[ -d "$dest/.git" ]] && return 0
    mkdir -p "$(dirname "$dest")"

    if [[ "$repo_spec" == git@github.com:* ]]; then
        repo_spec="${repo_spec#git@github.com:}"
        repo_spec="${repo_spec%.git}"
    elif [[ "$repo_spec" == https://github.com/* ]]; then
        repo_spec="${repo_spec#https://github.com/}"
        repo_spec="${repo_spec%.git}"
    fi

    # Prefer chaos canonical SSH key when present (matches system/ssh/config).
    if [[ -f "$HOME/.ssh/id_rsa" ]] && command -v git &>/dev/null; then
        if git clone "git@github.com:${repo_spec}.git" "$dest"; then
            return 0
        fi
        echo "⚠️  git@ clone failed for $repo_spec — trying gh HTTPS fallback"
    fi

    if _dotfiles_github_auth_ok; then
        if gh repo clone "$repo_spec" "$dest"; then
            return 0
        fi
        echo "⚠️  gh repo clone failed for $repo_spec — trying git/SSH fallback"
    fi

    local url="$spec"
    if [[ "$url" != git@* && "$url" != https://* ]]; then
        url="git@github.com:${repo_spec}.git"
    fi

    if ! command -v git &>/dev/null; then
        echo "❌ git not found" >&2
        return 1
    fi

    git clone "$url" "$dest"
}

function _ensure_xcode_clt {
    [[ "$(uname -s)" != "Darwin" ]] && return 0

    if xcode-select -p &>/dev/null; then
        return 0
    fi

    echo "Xcode Command Line Tools not found — triggering install (GUI prompt)."
    xcode-select --install 2>/dev/null || true

    local waited=0
    while ! xcode-select -p &>/dev/null; do
        if (( waited == 0 )); then
            echo "Waiting for Command Line Tools install to finish..."
        fi
        sleep 5
        waited=$((waited + 5))
        if (( waited >= 1800 )); then
            echo "❌ Timed out waiting for Xcode Command Line Tools (30 min)" >&2
            return 1
        fi
    done

    echo "✅ Xcode Command Line Tools ready"
    return 0
}

function _homebrew_arm64_prefix {
    printf '%s\n' "${DOTFILES_HOMEBREW_ARM64_PREFIX:-/opt/homebrew}"
}

function _homebrew_intel_prefix {
    printf '%s\n' "${DOTFILES_HOMEBREW_INTEL_PREFIX:-/usr/local}"
}

function _homebrew_preferred_brew {
    if _is_apple_silicon; then
        printf '%s/bin/brew\n' "$(_homebrew_arm64_prefix)"
    else
        printf '%s/bin/brew\n' "$(_homebrew_intel_prefix)"
    fi
}

function _homebrew_candidate_brews {
    if _is_apple_silicon; then
        printf '%s/bin/brew\n' "$(_homebrew_arm64_prefix)"
        printf '%s/bin/brew\n' "$(_homebrew_intel_prefix)"
    else
        printf '%s/bin/brew\n' "$(_homebrew_intel_prefix)"
        printf '%s/bin/brew\n' "$(_homebrew_arm64_prefix)"
    fi
}

function _activate_brew {
    local brew_bin="$1"
    eval "$("$brew_bin" shellenv)"
}

function _ensure_brew {
    local arch_bin candidate preferred installer brew_status

    if [[ "$(uname -s)" == "Darwin" ]]; then
        _ensure_xcode_clt || return 1
    fi

    preferred=$(_homebrew_preferred_brew)
    if [[ -x "$preferred" ]]; then
        _activate_brew "$preferred"
        return 0
    fi

    if ! _is_apple_silicon && command -v brew &> /dev/null; then
        return 0
    fi

    if ! _is_apple_silicon; then
        for candidate in $(_homebrew_candidate_brews); do
            if [[ -x "$candidate" ]]; then
                _activate_brew "$candidate"
                return 0
            fi
        done
    fi

    if _is_apple_silicon; then
        echo "Native Homebrew not found — installing $(_homebrew_arm64_prefix) Homebrew..."
    else
        echo "Homebrew not found — installing..."
    fi
    _ensure_sudo_cached || { echo "❌ sudo access required to install Homebrew"; return 1; }
    installer=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || {
        echo "❌ Homebrew installer download failed"
        return 1
    }
    if _is_apple_silicon; then
        arch_bin="${DOTFILES_ARCH_BIN:-/usr/bin/arch}"
        NONINTERACTIVE=1 "$arch_bin" -arm64 /bin/bash -c "$installer"
    else
        NONINTERACTIVE=1 /bin/bash -c "$installer"
    fi
    brew_status=$?
    if [[ $brew_status -ne 0 ]]; then
        echo "❌ Homebrew install failed"
        return 1
    fi

    if [[ -x "$preferred" ]]; then
        _activate_brew "$preferred"
        return 0
    fi
    if _is_apple_silicon; then
        echo "❌ Native Homebrew install completed but $preferred was not created"
        return 1
    fi
    for candidate in $(_homebrew_candidate_brews); do
        if [[ -x "$candidate" ]]; then
            _activate_brew "$candidate"
            return 0
        fi
    done
    echo "❌ Homebrew installed but brew not found on PATH"
    return 1
}

function _brew_update_once {
    if [[ "${DOTFILES_SKIP_BREW_UPDATE:-0}" == 1 ]]; then
        _install_progress "Homebrew metadata update skipped (DOTFILES_SKIP_BREW_UPDATE=1)"
        return 0
    fi
    [[ "${_DOTFILES_BREW_UPDATED:-0}" == 1 ]] && return 0
    command -v brew &> /dev/null || return 1

    _install_progress "Homebrew: updating metadata once"
    if brew update; then
        _install_progress "Homebrew: metadata current"
    else
        _install_progress "Homebrew: update failed, using cached metadata"
    fi
    _DOTFILES_BREW_UPDATED=1
}

function _brew_formula_outdated {
    local formula="$1"
    local outdated
    outdated=$(brew outdated --formula --quiet "$formula" 2>/dev/null || true)
    [[ -n "$outdated" ]]
}

function _brew_install {
    local app=$1
    if ! command -v brew &> /dev/null; then
        _install_step_fail "$app" "brew not available"
        return 1
    fi
    _brew_update_once

    if brew list --formula "$app" &> /dev/null; then
        if _brew_formula_outdated "$app"; then
            _install_step_start "$app" "upgrading Homebrew formula..."
            if brew upgrade "$app"; then
                _install_step_done_changed "$app" "upgraded (brew)"
            else
                _install_step_fail "$app" "brew upgrade failed"
                return 1
            fi
        else
            _install_step_done "$app" "already current (brew)"
        fi
        return 0
    fi

    _install_step_start "$app" "installing Homebrew formula..."
    if brew install "$app"; then
        _install_step_done_changed "$app" "installed (brew)"
    else
        _install_step_fail "$app" "brew install failed"
        return 1
    fi
}

function _macports_awscli_port_name {
    # Real ports are py311-awscli (v1, Platforms: darwin any) and py312-awscli2
    # (v2, darwin >= 20). There is no top-level "awscli2" port — install must use
    # the py*-prefixed names. Prefer bottles/binary archives from MacPorts when
    # available instead of forcing Homebrew source builds on older macOS.
    local dmaj
    dmaj=$(uname -r | cut -d. -f1)
    if [[ -n "$dmaj" && "$dmaj" =~ ^[0-9]+$ && "$dmaj" -ge 20 ]]; then
        echo "py312-awscli2"
    else
        echo "py311-awscli"
    fi
}

function _macports_name_for {
    # Translate a brew formula name to its MacPorts equivalent.
    # Returns the MacPorts name on stdout, or empty string if there is no
    # direct port (caller should handle fallback).
    #
    # When adding a new `_pkg_install <foo>` call in install/packages.bash,
    # add the corresponding port mapping here. Verify the port name at
    # https://ports.macports.org/search/?q=<foo>&name=on — port names often
    # diverge from brew formula names (e.g. brew "node" → port "nodejs22").
    local brew_name="$1"
    local PORT_PYTHON=python312 PORT_NODE=nodejs22 PORT_NPM=npm10 PY=py312
    case "$brew_name" in
        python3)    echo "$PORT_PYTHON" ;;
        node)       echo "$PORT_NODE" ;;
        npm)        echo "$PORT_NPM" ;;
        pipx)       echo "pipx" ;;
        virtualenv) echo "${PY}-virtualenv" ;;
        flake8)     echo "${PY}-flake8" ;;
        awscli)     _macports_awscli_port_name ;;
        flyctl)     echo "" ;;  # not packaged — caller falls back
        # Same name in both managers:
        jq|uv|shellcheck|screen|tmux|cmatrix|gh|git|wget|tree|ccache)
                    echo "$brew_name" ;;
        *)          echo "$brew_name" ;;  # optimistic default
    esac
}

function _install_flyctl_direct {
    if command -v flyctl &> /dev/null; then
        _link_flyctl_user_bin
        _install_step_start "flyctl" "checking direct installer updates..."
        if flyctl version update &>/dev/null; then
            _install_step_done "flyctl" "direct installer current"
        else
            _install_step_done "flyctl" "update check failed, leaving in place"
        fi
        return 0
    fi
    _install_step_start "flyctl" "installing via official installer..."
    if curl -fsSL https://fly.io/install.sh | sh; then
        _link_flyctl_user_bin
        _install_step_done_changed "flyctl" "installed (no MacPorts port available)"
    else
        _install_step_fail "flyctl" "official installer failed"
        return 1
    fi
}

function _link_flyctl_user_bin {
    if [[ -x "$HOME/.fly/bin/flyctl" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sfn "$HOME/.fly/bin/flyctl" "$HOME/.local/bin/flyctl"
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

function _install_uv_direct {
    if command -v uv &> /dev/null; then
        _install_step_done "uv" "already installed at $(command -v uv)"
        return 0
    fi
    _install_step_start "uv" "installing via official installer..."
    if curl -LsSf https://astral.sh/uv/install.sh | sh; then
        _install_step_done_changed "uv" "installed"
    else
        _install_step_fail "uv" "installer failed"
        return 1
    fi
}

function _port_already_selected {
    # True when `port select` already points <group> at <target>, so we can
    # skip the sudo call. Avoids a password prompt on every run for packages
    # that are already current (the select is idempotent but still needs root).
    local group="$1" target="$2" current
    current=$(/opt/local/bin/port select --show "$group" 2>/dev/null \
        | sed -n "s/.*is '\\([^']*\\)'.*/\\1/p")
    [[ "$current" == "$target" ]]
}

function _port_select_if_needed {
    # Some MacPorts packages require `port select` to expose a canonical binary.
    # Only invoke sudo when the selection actually needs to change — otherwise a
    # fully up-to-date machine would still prompt for a password every run.
    local brew_name="$1"
    case "$brew_name" in
        python3)
            _port_already_selected python3 python312 && return 0
            _ensure_sudo_cached || return 0
            sudo /opt/local/bin/port select --set python3 python312 &>/dev/null || true
            ;;
        awscli)
            _port_already_selected awscli py312-awscli2 && return 0
            _port_already_selected awscli py311-awscli && return 0
            _ensure_sudo_cached || return 0
            sudo /opt/local/bin/port select --set awscli py312-awscli2 &>/dev/null \
                || sudo /opt/local/bin/port select --set awscli py311-awscli &>/dev/null \
                || true
            ;;
    esac
}

function _pkg_install {
    # Install a package via the preferred package manager for this OS.
    # On macOS <15: MacPorts (with name translation); falls back to brew.
    # On Linux: system package manager with selected direct installer fallbacks.
    # On macOS 15+: Homebrew.
    local brew_name="$1"
    if _is_linux; then
        _linux_pkg_install "$brew_name"
        return $?
    fi

    if _prefer_macports; then
        _ensure_macports || return 1
        _macports_selfupdate_once || return 1
        local port_name
        port_name=$(_macports_name_for "$brew_name")
        if [[ -z "$port_name" ]]; then
            # No MacPorts equivalent — handle known escape hatches.
            case "$brew_name" in
                flyctl) _install_flyctl_direct; return $? ;;
                *) _brew_install "$brew_name"; return $? ;;
            esac
        fi
        if /opt/local/bin/port -q installed "$port_name" 2>/dev/null | awk '{print $1}' | grep -qx "$port_name"; then
            if /opt/local/bin/port -q outdated "$port_name" 2>/dev/null | awk '{print $1}' | grep -qx "$port_name"; then
                _install_step_start "$port_name" "upgrading MacPorts port..."
                _ensure_sudo_cached || { _install_step_fail "$port_name" "sudo required"; return 1; }
                if sudo /opt/local/bin/port -N upgrade "$port_name"; then
                    _install_step_done_changed "$port_name" "upgraded (MacPorts)"
                else
                    _install_step_fail "$port_name" "MacPorts upgrade failed"
                    return 1
                fi
            else
                _install_step_done "$port_name" "already current (MacPorts)"
            fi
            _port_select_if_needed "$brew_name"
            return 0
        fi
        _install_step_start "$port_name" "installing via MacPorts..."
        _ensure_sudo_cached || { _install_step_fail "$port_name" "sudo required"; return 1; }
        if sudo /opt/local/bin/port -N install "$port_name"; then
            _install_step_done_changed "$port_name" "installed (MacPorts)"
            _port_select_if_needed "$brew_name"
            return 0
        else
            _install_step_fail "$port_name" "MacPorts install failed"
            return 1
        fi
    fi
    _brew_install "$brew_name"
}

function _brew_cask_install {
    local cask=$1
    if ! command -v brew &> /dev/null; then
        _install_step_fail "$cask" "brew not available"
        return 1
    fi
    _brew_update_once

    if brew list --cask "$cask" &> /dev/null; then
        local outdated
        if ! outdated=$(brew outdated --cask --greedy --quiet "$cask" 2>/dev/null); then
            outdated=$(brew outdated --cask --quiet "$cask" 2>/dev/null || true)
        fi
        if [[ -n "$outdated" ]]; then
            _install_step_start "$cask" "upgrading Homebrew cask..."
            if brew upgrade --cask --greedy "$cask" || brew upgrade --cask "$cask"; then
                _install_step_done_changed "$cask" "upgraded (cask)"
            else
                _install_step_fail "$cask" "cask upgrade failed"
                return 1
            fi
        else
            _install_step_done "$cask" "already current (cask)"
        fi
        return 0
    fi
    _install_step_start "$cask" "installing Homebrew cask..."
    local install_out install_status
    if install_out=$(brew install --cask "$cask" 2>&1); then
        install_status=0
    else
        install_status=$?
    fi
    if [[ $install_status -eq 0 ]]; then
        _install_step_done_changed "$cask" "installed (cask)"
        return 0
    fi
    # App exists outside brew's Caskroom (manual install, auto-update drift,
    # or wiped Caskroom). Adopt the existing artifact instead of refusing.
    if grep -q "It seems there is already an App at" <<<"$install_out"; then
        local adopt_out adopt_status
        if adopt_out=$(brew install --cask --adopt "$cask" 2>&1); then
            adopt_status=0
        else
            adopt_status=$?
        fi
        if [[ $adopt_status -eq 0 ]]; then
            _install_step_done_changed "$cask" "adopted existing app (cask)"
            return 0
        fi
        install_out="$adopt_out"
    fi
    printf '%s\n' "$install_out" > "$(_install_out_target)"
    _install_step_fail "$cask" "cask install failed"
    return 1
}

function _pip_install {
    local app=$1
    if ! which pipx &> /dev/null; then
        _install_step_fail "$app" "pipx not available"
        return 1
    fi

    if pipx runpip "$app" show "$app" &>/dev/null; then
        _install_step_start "$app" "checking pipx upgrade..."
        local out
        out=$(pipx upgrade "$app" 2>&1) || { _install_step_fail "$app" "pipx upgrade failed"; return 1; }
        if grep -q "already at latest version" <<<"$out"; then
            _install_step_done "$app" "already current (pipx)"
        else
            _install_step_done_changed "$app" "upgraded (pipx)"
        fi
        return 0
    fi

    if which "$app" &> /dev/null; then
        _install_step_done "$app" "command exists outside pipx, leaving it"
        return 0
    fi

    _install_step_start "$app" "installing with pipx..."
    if pipx install "$app"; then
        _install_step_done_changed "$app" "installed (pipx)"
    else
        _install_step_fail "$app" "pipx install failed"
        return 1
    fi
}

function backup {
    local backup_dir="$1"
    mkdir -p "$backup_dir"
    echo "Backing up all your precious configs"

    echo -ne "bash     (###             )  --  (25%)\r"
    if [[ -d ~/.bash ]]; then
        cp -a ~/.bash* "$backup_dir/"
    fi
    sleep 1

    echo -ne "vim      (######          )  --  (50%)\r"
    if [[ -d ~/.vim ]]; then
        cp -a ~/.vim* "$backup_dir/"
    fi
    sleep 1

    echo -ne "aws      (#########       )  --  (75%)\r"
    if [[ -d ~/.aws ]]; then
        cp -a ~/.aws* "$backup_dir/"
    fi
    sleep 1

    echo -ne "dotfiles (################)  --  (100%)\r"
    for file in ~/.bashrc ~/.gitconfig ~/.gitignore_global ~/.profile ~/.screenrc ~/.vimrc; do
        if [[ -e "$file" ]]; then
            cp -a "$file" "$backup_dir/"
        fi
    done
    sleep 1
    echo ""
    echo "Backup completed: $backup_dir"
}

# --- `all` orchestration: run every section, never abort on one failure ------
#
# The `all` flow used to `|| exit 1` after most sections, so a single flaky
# section (a network-dependent installer, an EEXIST collision, one bad package)
# aborted the entire run before the later sections (claude/mcp)
# ever executed. That is the recurring "install.sh all won't complete" failure.
# Instead, record each section's outcome and keep going, then print a summary
# and exit nonzero at the very end if anything failed — so the user always gets
# a complete run plus an exact list of what to re-run.

_DOTFILES_ALL_FAILED=()

function _all_run {
    # _all_run <label> <relative-source-file|""> <function> [args...]
    # Sources <relative-source-file> (if given), runs the section, and records
    # a failure instead of aborting. Always returns 0 so the caller continues.
    local label="$1" file="$2" fn="$3"
    shift 3
    if [[ -n "$file" ]]; then
        # shellcheck source=/dev/null
        source "$DOTFILES_REPO_DIR/$file"
    fi
    _section_run "$label" "$fn" "$@" || _DOTFILES_ALL_FAILED+=("$label")
    return 0
}

function _all_summary {
    if [[ ${#_DOTFILES_ALL_FAILED[@]} -eq 0 ]]; then
        printf '\n%b✓%b install all completed — every section succeeded\n' "$C_GREEN" "$C_RESET"
        return 0
    fi
    printf '\n%b✗%b install all finished with %d failed section(s): %s\n' \
        "$C_RED" "$C_RESET" "${#_DOTFILES_ALL_FAILED[@]}" "${_DOTFILES_ALL_FAILED[*]}"
    printf '  The rest of the install still ran. Re-run a failed section for full output, e.g.:\n'
    local s
    for s in "${_DOTFILES_ALL_FAILED[@]}"; do
        printf '    ./install.sh %s --verbose\n' "$s"
    done
    return 1
}

# User-prefix for managed npm agent CLIs (~/.local). Matches packages.bash.
function _dotfiles_user_prefix {
    printf '%s\n' "${DOTFILES_NPM_PREFIX:-$HOME/.local}"
}

# Resolve an agent CLI executable on PATH, bypassing shell function wrappers.
function _agent_bin_path {
    type -P "$1" 2>/dev/null || true
}

# Classify how an agent CLI is installed. Optional second arg is the npm package
# name when the command is npm-managed (e.g. claude -> @anthropic-ai/claude-code).
function _classify_agent_install {
    local cmd="$1"
    local package="${2:-}"
    local resolved prefix

    resolved=$(_agent_bin_path "$cmd")
    if [[ -z "$resolved" ]]; then
        printf '%s\n' "missing"
        return 0
    fi

    prefix=$(_dotfiles_user_prefix)
    if [[ "$resolved" == "$prefix/bin/$cmd" ]]; then
        if [[ -n "$package" ]] && command -v npm &>/dev/null; then
            NPM_CONFIG_PREFIX="$prefix" npm list -g "$package" --depth=0 &>/dev/null \
                && { printf '%s\n' "npm-managed"; return 0; }
        fi
        printf '%s\n' "user-prefix-bin"
        return 0
    fi

    if [[ "$resolved" == *"/.local/share/claude/"* ]]; then
        printf '%s\n' "native-standalone"
        return 0
    fi

    if [[ "$resolved" == *"/.local/share/cursor-agent/"* || "$resolved" == *"/.composio/"* ]]; then
        printf '%s\n' "official-curl"
        return 0
    fi

    if [[ "$resolved" == *"/Caskroom/"* ]]; then
        printf '%s\n' "brew-cask"
        return 0
    fi

    if [[ "$resolved" == *"/opt/homebrew/"* || "$resolved" == *"/usr/local/"* ]]; then
        if [[ -L "$resolved" ]] && readlink "$resolved" 2>/dev/null | grep -q node_modules; then
            printf '%s\n' "brew-global-npm"
            return 0
        fi
        printf '%s\n' "brew-other"
        return 0
    fi

    printf '%s\n' "other"
}

# Remove a brew-prefix (or other off-prefix) global npm agent install so
# ~/.local can own the command.
function _remove_off_prefix_npm_agent {
    local cmd="$1"
    local package="$2"
    local classify brew_prefix user_prefix

    classify=$(_classify_agent_install "$cmd" "$package")
    user_prefix=$(_dotfiles_user_prefix)

    if ! command -v npm &>/dev/null; then
        if [[ "$classify" == "brew-global-npm" ]]; then
            _install_progress "$cmd: brew global npm detected but npm unavailable for migration"
            return 1
        fi
        return 0
    fi

    if command -v brew &>/dev/null; then
        brew_prefix=$(brew --prefix 2>/dev/null || true)
        if [[ -n "$brew_prefix" && "$brew_prefix" != "$user_prefix" ]] \
            && PATH="$PATH" NPM_CONFIG_PREFIX="$brew_prefix" npm list -g "$package" --depth=0 &>/dev/null; then
            _install_progress "$cmd: removing duplicate brew global npm package from $brew_prefix"
            PATH="$PATH" NPM_CONFIG_PREFIX="$brew_prefix" npm uninstall -g "$package" &>/dev/null || true
        fi
    fi

    [[ "$classify" == "brew-global-npm" ]] || return 0

    _install_progress "$cmd: migrating brew global npm ($(_agent_bin_path "$cmd")) to $user_prefix"

    npm uninstall -g "$package" &>/dev/null || true
    hash -r 2>/dev/null || true
}

function _claude_is_native_standalone {
    local resolved
    resolved=$(_agent_bin_path claude)
    [[ -n "$resolved" && "$resolved" == *"/.local/share/claude/"* ]]
}

# Resolve the Cursor IDE CLI inside Cursor.app (extension installs / open files).
# Not cursor-agent — that is a separate binary.
function _cursor_app_cli_target {
    if [[ -n "${DOTFILES_CURSOR_APP_CLI_TARGET:-}" && -e "${DOTFILES_CURSOR_APP_CLI_TARGET}" ]]; then
        printf '%s\n' "$DOTFILES_CURSOR_APP_CLI_TARGET"
        return 0
    fi
    case "$(uname -s)" in
        Darwin)
            local target="/Applications/Cursor.app/Contents/Resources/app/bin/code"
            if [[ -e "$target" ]]; then
                printf '%s\n' "$target"
                return 0
            fi
            ;;
    esac
    return 1
}

# Canonical Cursor IDE CLI for install/backup scripts. Prefers ~/.local/bin/cursor
# when it symlinks to Cursor.app, then the app bundle path, then PATH lookup.
# Avoids Homebrew shims winning during install when PATH puts brew first.
function _cursor_ide_bin_path {
    local prefix launcher target resolved

    target=$(_cursor_app_cli_target) || target=""

    if [[ "$(uname -s)" == "Darwin" && -n "$target" ]]; then
        prefix=$(_dotfiles_user_prefix)
        launcher="$prefix/bin/cursor"
        if [[ -L "$launcher" && -x "$launcher" ]]; then
            resolved=$(readlink "$launcher" 2>/dev/null || true)
            if [[ "$resolved" == "$target" || "$resolved" == *"Cursor.app"* ]]; then
                printf '%s\n' "$launcher"
                return 0
            fi
        fi
        printf '%s\n' "$target"
        return 0
    fi

    prefix=$(_dotfiles_user_prefix)
    launcher="$prefix/bin/cursor"
    if [[ -x "$launcher" ]]; then
        printf '%s\n' "$launcher"
        return 0
    fi

    resolved=$(_agent_bin_path cursor)
    [[ -n "$resolved" ]] && printf '%s\n' "$resolved"
}

# Remove /opt/homebrew/bin/cursor (or Intel equivalent) when it only duplicates
# the Cursor.app CLI. apps.bash uses --no-binaries, but older installs may leave a shim.
function _remove_brew_cursor_cli_shim {
    [[ "$(uname -s)" != "Darwin" ]] && return 0
    command -v brew &>/dev/null || return 0

    local brew_prefix brew_cursor target link_target
    brew_prefix=$(brew --prefix 2>/dev/null || true)
    [[ -n "$brew_prefix" ]] || return 0
    brew_cursor="$brew_prefix/bin/cursor"
    [[ -e "$brew_cursor" ]] || return 0

    target=$(_cursor_app_cli_target) || return 0

    if [[ -L "$brew_cursor" ]]; then
        link_target=$(readlink "$brew_cursor" 2>/dev/null || true)
        if [[ "$link_target" == "$target" || "$link_target" == *"Cursor.app"* ]]; then
            _install_progress "cursor CLI: removing Homebrew shim at $brew_cursor"
            rm -f "$brew_cursor"
        fi
    elif [[ -f "$brew_cursor" ]]; then
        # Brew wrapper script that execs the app CLI — safe to drop once ~/.local/bin is linked.
        if head -1 "$brew_cursor" 2>/dev/null | grep -q bash; then
            _install_progress "cursor CLI: removing Homebrew wrapper at $brew_cursor"
            rm -f "$brew_cursor"
        fi
    fi
}

# Symlink ~/.local/bin/cursor to the Cursor.app CLI (extension installs).
# Replaces the small shim dropped by cursor.com/install when present.
function _link_cursor_cli {
    local launcher target prefix

    target=$(_cursor_app_cli_target) || return 1

    prefix=$(_dotfiles_user_prefix)
    launcher="$prefix/bin/cursor"
    mkdir -p "$(dirname "$launcher")" || return 1

    if [[ -e "$launcher" && ! -L "$launcher" ]]; then
        _install_progress "cursor CLI: removing official-installer shim at $launcher"
        rm -f "$launcher"
    fi

    ln -sfn "$target" "$launcher"
    _remove_brew_cursor_cli_shim
}

function print_usage {
    echo "Usage: $0 [--verbose|-v] [--help|-h|help] <command>"
    echo ""
    echo "Commands:"
    echo "  vim         - Install vim configuration"
    echo "  dotfiles    - Install all dotfiles and .folders (includes shell config)"
    echo "  hostname    - Verify and sync macOS hostname settings (ComputerName, LocalHostName, HostName)"
    echo "  backup      - Backup existing configuration"
    echo "  packages    - Install required CLI packages (brew + pipx)"
    echo "  ssh           - Install SSH config (generic github.com block)"
    echo "  bootstrap     - Fresh Mac: CLT + Homebrew + gh auth + clone dotfiles (see scripts/bootstrap-macos.sh)"
    echo "  ssh-keys      - Install ~/.ssh/config and register a GitHub SSH key via gh (optional; not in \`all\`)"
    echo "  apps        - Install GUI apps via Homebrew cask (Chrome + Cursor)"
    echo "  dictation   - Install Linux push-to-talk dictation (Voxtype)"
    echo "  iterm       - Install iTerm2 + sync preferences plist + register as default terminal"
    echo "  cursor      - Install Cursor configuration (bash terminal)"
    echo "  claude      - Install Claude Code configuration (settings + MCP cleanup)"
    echo "  codex       - Install Codex CLI configuration and enabled plugins"
    echo "  agents-doctor - Report agent CLI paths, versions, duplicate installs, and MCP status"
    echo "  mcp         - Install all enabled MCP servers for Codex/Cursor as configured"
    echo "  composio    - Install Composio MCP for Claude Code, Claude Desktop, Cursor, and Codex"
    echo "  composio-auth - Run dot-composio-auth (login|status|reset) for Composio MCP OAuth"
    echo "  grepler     - Install Grepler MCP for Claude Code, Claude Desktop, Cursor, and Codex"
    echo "  playwright  - Install Playwright MCP (browser extension mode) for all MCP clients"
    echo "  grepler-agent - Install the Grepler Agent daemon (heartbeats + Claude Code plan reporter)"
    echo "  all         - Run backup, dotfiles, ssh, vim, packages, apps, IDE configs, and MCP."
    echo "                Resilient: a failed section is recorded and the run continues; a summary"
    echo "                at the end lists any failures and how to re-run them (exit 1 if any failed)."
    echo "  shell       - Configure shell settings (bash as default, zsh compatibility, terminal colors)"
    echo ""
    echo "Flags:"
    echo "  --verbose   - Show full command output instead of the compact progress summary"
    echo "  --help, -h, help - Show this message (exits 0)"
    echo ""
    echo "Install tuning (optional environment variables):"
    echo "  DOTFILES_ALLOW_ROSETTA=1         Do not re-exec installer as arm64 on Apple Silicon"
    echo "  DOTFILES_SKIP_MACPORTS_UPDATE=1  Skip \`port selfupdate\` during package installs"
    echo "  DOTFILES_SKIP_BREW_UPDATE=1      Skip \`brew update\` metadata prefetch"
    echo "  DOTFILES_SKIP_AWSCLI_PKG=1       Skip AWS CLIV2.pkg fallback on macOS (after MacPorts/Homebrew fail)"
    echo "  DOTFILES_SKIP_IMPECCABLE_SKILL=1 Skip global Impeccable skill (\`npx skills\`) in \`packages\`"
    echo "  DOTFILES_SYNC_HOSTNAME=1         Run the interactive hostname sync during \`all\` (off by default so \`all\` doesn't block; use \`./install.sh hostname\` anytime)"
    echo "  DOTFILES_CURSOR_SKIP_EXTENSION_PRUNE=1  Keep Cursor extensions not listed in ide/cursor/extensions.txt"
    echo "  DOTFILES_CLAUDE_SKIP_CHROME=1      Skip passing --chrome from the \`claude\` shell wrapper"
    echo "  DOTFILES_SUDO_PASSWORD=...        One-shot sudo password for non-TTY installs (agent/CI only; export per session, never commit)"
}
