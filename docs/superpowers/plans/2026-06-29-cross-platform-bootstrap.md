# Cross-Platform Bootstrap & Legacy/Linux Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the one-line `curl` installer work from anywhere — modern macOS, legacy macOS (<15, Intel + Apple Silicon), and Debian/Ubuntu Linux — and close the concrete cross-platform gaps found in the audit.

**Architecture:** The pain the user hit ("sudo never prompted, then everything built from Homebrew source") traces to two root causes: (1) `_ensure_sudo_cached` only reads a password from `/dev/tty` inside captured sections, so the top-level prime under `curl | bash` / `bash -c "$(curl …)"` silently fails; (2) `scripts/bootstrap-macos.sh` unconditionally installs Homebrew and runs `brew install gh git curl jq` with no OS-version awareness, forcing source builds on legacy Macs before `install.sh all`'s MacPorts preference ever runs. The fix is to (a) make sudo priming `/dev/tty`-first, (b) replace the macOS-only bootstrap with an OS-aware `scripts/bootstrap.sh` that installs **nothing** pre-clone beyond what's strictly needed to clone (CLT/git), then delegates package-manager choice to the existing `install.sh all` dispatcher, and (c) fix the specific Linux/legacy gaps the audit surfaced.

**Tech Stack:** Bash 3.2-compatible shell scripts; the repo's existing `tests/<area>/run_tests.sh` harness (pure-function unit tests that `source install/_helpers.bash`).

## Global Constraints

- **Bash 3.2 compatible** — no `declare -A`, `${var^^}`/`${var,,}`, `mapfile`/`readarray`, or `&>>`. macOS ships bash 3.2 as `/bin/bash`.
- **Linux target is Debian/Ubuntu (apt) only.** dnf/yum paths remain best-effort and untested; do not expand them in this plan. Note this explicitly where relevant rather than silently dropping coverage.
- **Never run a schema/data-model migration.** N/A here (shell/install tooling only), but do not add anything that touches a datastore.
- **Copies, not symlinks** — installation copies files to `~`; backups go to `/tmp/dotfiles_backup_<timestamp>/`. Don't change this model.
- **Validate every change** with: `bash -n` parse checks, `shellcheck` when available, and the relevant `tests/<area>/run_tests.sh`.
- **Frequent commits** — one per task. Conventional-commit style messages matching the repo's history (`feat:`, `fix:`, `test:`, `docs:`).
- The public repo is `thechrisfischer/mydot`; the documented one-liner uses `raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/...`.

---

## File Structure

- `install/_helpers.bash` — modify `_ensure_sudo_cached` (Task 0.1); add `gh` apt-repo helper `_linux_install_gh` (Task 1.2); make `_macports_name_for` version-aware (Task 2.1).
- `.bash/functions/dash.bash` — **delete** (Task 1.1: remove dash + dcli entirely).
- `scripts/bootstrap.sh` — **create**: OS-aware universal bootstrap (Task 0.2).
- `scripts/bootstrap-macos.sh` — modify to a thin back-compat shim that execs `bootstrap.sh` (Task 0.2).
- `install/apps.bash` — already does the apt keyring/repo dance for Chrome; reused as the pattern reference (Task 1.2).
- `tests/sudo/run_tests.sh` — **create** (Task 0.1).
- `tests/bootstrap/run_tests.sh` — modify to cover OS detection in `bootstrap.sh` (Task 0.2).
- `tests/shell/run_tests.sh` — modify: remove the dash test block + registrations (Task 1.1).
- `tests/linux-packages/run_tests.sh` — modify: drop orphaned `install/external-fs.bash` ref (Task 1.3), broaden mappings + add `gh` repo assertion (Tasks 1.2, 3.1).
- `tests/macports/run_tests.sh` — modify: add `_macports_name_for` + `_macports_awscli_port_name` coverage (Tasks 2.1, 2.2).
- `README.md`, `docs/fresh-mac-bootstrap.md`, `CLAUDE.md` — modify one-liners + platform matrix + min-OS doc (Tasks 0.3, 3.2).

---

# Phase 0 — Universal, OS-aware bootstrap (the user's actual pain)

### Task 0.1: Make sudo priming `/dev/tty`-first so `curl | bash` works

**Root cause:** `_ensure_sudo_cached` only routes the password prompt to `/dev/tty` when `_DOTFILES_SECTION_CAPTURE=1`. The top-level prime in `install.sh all` (line ~139) and in the bootstrap run outside any captured section, so under `curl | bash` (stdin = the script pipe, `[[ -t 0 ]]` false) it falls into the final `else` and fails with "no TTY" — non-fatal in `all`, so every sudo section then fails one-by-one. Fix: try `/dev/tty` whenever it is writable, independent of the capture flag.

**Files:**
- Modify: `install/_helpers.bash` — `_ensure_sudo_cached`
- Test: `tests/sudo/run_tests.sh` (create)

**Interfaces:**
- Consumes: `_dotfiles_sudo` (existing wrapper), `_spawn_sudo_keepalive` (existing), `DOTFILES_SUDO_PASSWORD` (existing env escape hatch).
- Produces: `_ensure_sudo_cached` — unchanged signature (no args; returns 0 on cached sudo, 1 otherwise). New behavior: a writable `/dev/tty` is used to prompt even when stdin is not a TTY.

- [ ] **Step 1: Write the failing test**

Create `tests/sudo/run_tests.sh`. The test exercises the *decision path* without ever invoking real sudo, by stubbing `_dotfiles_sudo` and `_spawn_sudo_keepalive` and asserting which prompt branch runs. Add a factored helper `_sudo_prompt_channel` (pure, returns `tty`|`stdin`|`none`) that `_ensure_sudo_cached` will use, so the branch is unit-testable.

```bash
#!/bin/bash
# Tests sudo prompt channel selection (no real sudo invoked).
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
cd "$REPO_ROOT" || exit 1
fail() { echo "FAIL: $*" >&2; exit 1; }

# tty available + stdin not a tty (the curl|bash case) → choose tty, not none
expect_channel() {
    local tty_writable="$1" stdin_tty="$2" want="$3"
    (
        # shellcheck disable=SC1091
        source "$REPO_ROOT/install/_helpers.bash"
        _DOTFILES_TEST_TTY_WRITABLE="$tty_writable"
        _DOTFILES_TEST_STDIN_TTY="$stdin_tty"
        got=$(_sudo_prompt_channel)
        [[ "$got" == "$want" ]] || { echo "tty=$tty_writable stdin=$stdin_tty expected=$want got=$got" >&2; exit 1; }
    ) || fail "_sudo_prompt_channel tty=$tty_writable stdin=$stdin_tty → $want"
}

expect_channel 1 0 tty      # curl|bash: no stdin tty but /dev/tty writable
expect_channel 0 1 stdin    # normal interactive: stdin is a tty
expect_channel 1 1 tty      # both: prefer /dev/tty (robust under capture)
expect_channel 0 0 none     # headless CI: neither → caller must use DOTFILES_SUDO_PASSWORD
echo "sudo prompt-channel tests passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/sudo/run_tests.sh`
Expected: FAIL — `_sudo_prompt_channel: command not found`.

- [ ] **Step 3: Add `_sudo_prompt_channel` and rewire `_ensure_sudo_cached`**

In `install/_helpers.bash`, add the pure helper (test seams via `_DOTFILES_TEST_*` so the suite need not touch a real tty):

```bash
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
```

Then replace the prompt-branch block in `_ensure_sudo_cached` (the `if [[ "${_DOTFILES_SECTION_CAPTURE:-0}" == 1 ]] … elif [[ -t 0 ]] … else …` ladder) with a channel-driven version:

```bash
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
```

Leave the leading `_dotfiles_sudo -n -v` fast-path (already-cached) check at the top of the function unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/sudo/run_tests.sh`
Expected: `sudo prompt-channel tests passed`

Run: `bash -n install.sh install/_helpers.bash && shellcheck install/_helpers.bash 2>/dev/null || true`
Expected: no parse errors.

- [ ] **Step 5: Commit**

```bash
git add install/_helpers.bash tests/sudo/run_tests.sh
git commit -m "fix(install): prompt for sudo via /dev/tty so curl|bash priming works"
```

---

### Task 0.2: OS-aware universal `scripts/bootstrap.sh` (no forced Homebrew)

**Root cause of "everything built via brew":** `bootstrap-macos.sh` always installs Homebrew and `brew install gh git curl jq`. On legacy macOS those have no bottles → source builds. None of it is needed pre-clone: the Xcode CLT already provides `git` and `curl`, and a **public** clone needs no `gh`. So the new bootstrap installs only CLT (macOS) or `git` (Linux/apt), primes sudo `/dev/tty`-first, clones over public HTTPS, and hands off to `install.sh all`, which already prefers MacPorts on macOS <15 and apt on Linux. `gh`/`jq` are installed lazily **only** if the public clone fails (private/fork).

**Files:**
- Create: `scripts/bootstrap.sh`
- Modify: `scripts/bootstrap-macos.sh` (becomes a shim)
- Test: `tests/bootstrap/run_tests.sh`

**Interfaces:**
- Produces: `scripts/bootstrap.sh` exposes pure functions `_bootstrap_os` (echoes `macos`|`linux`|`unsupported`) and `_bootstrap_macos_pkg_strategy` (echoes `macports`|`homebrew` from a passed version string) for unit testing. `_main` orchestrates.
- Consumes (post-clone): `./install.sh ssh`, `./install.sh all`. Honors `DOTFILES_REPO`, `DOTFILES_GITHUB`, `DOTFILES_SKIP_INSTALL_ALL`, `GITHUB_TOKEN`, `DOTFILES_SUDO_PASSWORD`.

- [ ] **Step 1: Write the failing test**

Append to `tests/bootstrap/run_tests.sh` (keep existing assertions). These cover the pure detection helpers without running the installer:

```bash
# --- bootstrap.sh OS + macOS package-strategy detection ---
( set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/scripts/bootstrap.sh" --source-only
  # macOS <15 → macports, >=15 → homebrew
  [[ "$(_bootstrap_macos_pkg_strategy 13.6.1)" == macports ]] || { echo "13.6 should be macports" >&2; exit 1; }
  [[ "$(_bootstrap_macos_pkg_strategy 10.14.6)" == macports ]] || { echo "10.14 should be macports" >&2; exit 1; }
  [[ "$(_bootstrap_macos_pkg_strategy 15.0)"   == homebrew ]] || { echo "15.0 should be homebrew" >&2; exit 1; }
  [[ "$(_bootstrap_macos_pkg_strategy 26.0)"   == homebrew ]] || { echo "26.0 should be homebrew" >&2; exit 1; }
) || fail "bootstrap macOS strategy detection"
echo "bootstrap detection tests passed"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/bootstrap/run_tests.sh`
Expected: FAIL — `scripts/bootstrap.sh` does not exist / `_bootstrap_macos_pkg_strategy: command not found`.

- [ ] **Step 3: Create `scripts/bootstrap.sh`**

```bash
#!/bin/bash
# Universal bootstrap for a brand-new machine (macOS modern/legacy, Debian/Ubuntu).
#
# Installs nothing it doesn't have to: on macOS it ensures only the Xcode
# Command Line Tools (which provide git + curl); on Linux/apt it ensures git.
# It primes sudo via /dev/tty (so `curl | bash` works), clones over public
# HTTPS, then hands off to ./install.sh all — which already prefers MacPorts on
# macOS <15, Homebrew on macOS 15+, and apt on Linux. gh/jq are installed only
# if a public clone fails (private/fork).
#
# Usage (works piped or via -c):
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap.sh)"
#   curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap.sh | bash
#
# Env: DOTFILES_REPO, DOTFILES_GITHUB, DOTFILES_SKIP_INSTALL_ALL, GITHUB_TOKEN,
#      DOTFILES_SUDO_PASSWORD (headless sudo).

DOTFILES_REPO="${DOTFILES_REPO:-$HOME/Code/mydot}"
DOTFILES_GITHUB="${DOTFILES_GITHUB:-thechrisfischer/mydot}"

_bootstrap_os() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)  echo linux ;;
        *)      echo unsupported ;;
    esac
}

_bootstrap_macos_pkg_strategy() {
    # Echo the package manager install.sh will prefer, from a version string.
    # macOS <15 → macports (no Homebrew bottles), 15+ → homebrew. Informational
    # only (install.sh makes the real choice); used for the bootstrap banner.
    local pv="$1" major
    major="${pv%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || { echo homebrew; return 0; }
    if [[ "$major" -lt 15 ]]; then echo macports; else echo homebrew; fi
}

# Read sudo password from /dev/tty even under `curl | bash`. No-op if already cached.
_bootstrap_prime_sudo() {
    command -v sudo >/dev/null 2>&1 || return 0
    sudo -n -v 2>/dev/null && return 0
    if [[ -n "${DOTFILES_SUDO_PASSWORD:-}" ]]; then
        printf '%s\n' "$DOTFILES_SUDO_PASSWORD" | sudo -S -v 2>/dev/null && return 0
    fi
    if { [ -w /dev/tty ]; } 2>/dev/null; then
        echo "→ Caching sudo (you'll be prompted once)..." > /dev/tty
        sudo -v < /dev/tty > /dev/tty 2>&1 || { echo "⚠️  sudo not cached — some steps may prompt or fail" >&2; return 1; }
        return 0
    fi
    echo "⚠️  no TTY for sudo — set DOTFILES_SUDO_PASSWORD or run from a terminal" >&2
    return 1
}

_ensure_xcode_clt() {
    xcode-select -p &>/dev/null && { echo "✅ Xcode Command Line Tools"; return 0; }
    echo "→ Installing Xcode Command Line Tools (accept the macOS dialog)..."
    xcode-select --install 2>/dev/null || true
    local waited=0
    until xcode-select -p &>/dev/null; do
        sleep 5; waited=$((waited + 5))
        (( waited >= 1800 )) && { echo "❌ Timed out waiting for CLT (30 min)" >&2; exit 1; }
    done
    echo "✅ Xcode Command Line Tools ready"
}

_ensure_git_linux() {
    command -v git &>/dev/null && { echo "✅ git present"; return 0; }
    if command -v apt-get &>/dev/null; then
        _bootstrap_prime_sudo || true
        sudo apt-get update && sudo apt-get install -y git
    else
        echo "❌ Only Debian/Ubuntu (apt) is supported by this bootstrap. Install git manually, then re-run." >&2
        exit 1
    fi
}

_clone_dotfiles() {
    mkdir -p "$(dirname "$DOTFILES_REPO")"
    if [[ -d "$DOTFILES_REPO/.git" ]]; then
        echo "→ Updating existing checkout at $DOTFILES_REPO"
        git -C "$DOTFILES_REPO" pull --ff-only || true
        return 0
    fi
    echo "→ Cloning $DOTFILES_GITHUB → $DOTFILES_REPO"
    git clone "https://github.com/$DOTFILES_GITHUB.git" "$DOTFILES_REPO" 2>/dev/null && return 0
    echo "  public clone failed — authenticating with gh (private/fork) and retrying"
    if ! command -v gh &>/dev/null; then
        if [[ "$(_bootstrap_os)" == macos ]] && command -v brew &>/dev/null; then brew install gh
        elif command -v apt-get &>/dev/null; then _bootstrap_prime_sudo || true; sudo apt-get install -y gh || true
        fi
    fi
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then printf '%s\n' "$GITHUB_TOKEN" | gh auth login -h github.com --with-token
    else gh auth login -h github.com -p https -w; fi
    gh repo clone "$DOTFILES_GITHUB" "$DOTFILES_REPO"
}

_main() {
    set -euo pipefail
    local os; os="$(_bootstrap_os)"
    echo "=== mydot bootstrap ($os) ==="
    case "$os" in
        macos)
            local pv; pv="$(/usr/bin/sw_vers -productVersion 2>/dev/null || echo '')"
            [[ -n "$pv" ]] && echo "→ macOS $pv → install.sh will prefer: $(_bootstrap_macos_pkg_strategy "$pv")"
            _ensure_xcode_clt
            _bootstrap_prime_sudo || true
            ;;
        linux)
            _ensure_git_linux
            _bootstrap_prime_sudo || true
            ;;
        *)  echo "❌ Unsupported OS: $(uname -s)" >&2; exit 1 ;;
    esac
    _clone_dotfiles
    cd "$DOTFILES_REPO"
    echo "→ SSH config"; ./install.sh ssh || echo "⚠️  install.sh ssh failed (non-fatal)"
    if [[ "${DOTFILES_SKIP_INSTALL_ALL:-0}" == 1 ]]; then
        echo "=== Bootstrap complete (DOTFILES_SKIP_INSTALL_ALL=1) ==="
        echo "Next: cd $DOTFILES_REPO && ./install.sh all"; exit 0
    fi
    echo "→ Running ./install.sh all"; ./install.sh all
    echo "=== Bootstrap complete ==="
}

# Allow `source bootstrap.sh --source-only` for unit tests (defines functions, no run).
if [[ "${1:-}" == "--source-only" ]]; then return 0 2>/dev/null || exit 0; fi
_main "$@"
```

- [ ] **Step 4: Replace `scripts/bootstrap-macos.sh` with a back-compat shim**

Keep the old URL working (it's in the wild). Overwrite the file body with:

```bash
#!/bin/bash
# Back-compat shim — the bootstrap is now OS-aware. Use scripts/bootstrap.sh.
# Kept so the previously-published one-liner URL keeps working.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$DIR/bootstrap.sh" ]]; then
    exec /bin/bash "$DIR/bootstrap.sh" "$@"
fi
# Running detached via curl (no sibling file): fetch the universal script.
GH="${DOTFILES_GITHUB:-thechrisfischer/mydot}"
exec /bin/bash -c "$(curl -fsSL "https://raw.githubusercontent.com/$GH/main/scripts/bootstrap.sh")" "$@"
```

- [ ] **Step 5: Run tests + parse checks**

Run: `bash tests/bootstrap/run_tests.sh`
Expected: existing assertions + `bootstrap detection tests passed`.

Run: `bash -n scripts/bootstrap.sh scripts/bootstrap-macos.sh && shellcheck scripts/bootstrap.sh 2>/dev/null || true`
Expected: no parse errors.

Run (smoke, no install): `DOTFILES_SKIP_INSTALL_ALL=1 DOTFILES_REPO=/tmp/mydot_smoke bash -n scripts/bootstrap.sh`
Expected: parses clean.

- [ ] **Step 6: Commit**

```bash
git add scripts/bootstrap.sh scripts/bootstrap-macos.sh tests/bootstrap/run_tests.sh
git commit -m "feat(bootstrap): OS-aware universal installer; stop forcing Homebrew on legacy macOS"
```

---

### Task 0.3: Point the documented one-liners at `bootstrap.sh`

**Files:**
- Modify: `README.md` (lines ~10, ~54), `docs/fresh-mac-bootstrap.md` (lines ~11, ~31, ~35, ~39), `CLAUDE.md` (bootstrap references).

- [ ] **Step 1: Update the one-liner URL and description**

In `README.md` and `docs/fresh-mac-bootstrap.md`, replace `scripts/bootstrap-macos.sh` with `scripts/bootstrap.sh` in every `curl` one-liner, and change descriptions like "Installs Xcode CLT, then Homebrew, before cloning" to: "Installs only what's needed to clone (Xcode CLT on macOS / git on Debian-Ubuntu), then clones and runs `./install.sh all`, which prefers MacPorts on macOS <15, Homebrew on 15+, and apt on Linux." Add a one-line note that the old `bootstrap-macos.sh` URL still works.

- [ ] **Step 2: Verify no stale references remain**

Run: `grep -rn "bootstrap-macos.sh" README.md docs/ CLAUDE.md`
Expected: only the back-compat note mentions it; all live one-liners point at `bootstrap.sh`.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/fresh-mac-bootstrap.md CLAUDE.md
git commit -m "docs: point one-liner at OS-aware bootstrap.sh; clarify legacy/Linux behavior"
```

---

# Phase 1 — Linux real bugs (Debian/Ubuntu)

### Task 1.1: Remove `dash` + `dcli` entirely

**Decision (user):** Remove the Dashlane `dash` wrapper and its `dcli` dependency outright. This also eliminates the only `pbcopy` consumer in the repo, so no clipboard abstraction is needed (YAGNI). `dcli` is **not** installed by `install/packages.bash` (the "Run: install.sh packages" hint in `dash.bash` is aspirational), so removal is self-contained.

**Files:**
- Delete: `.bash/functions/dash.bash`
- Modify: `tests/shell/run_tests.sh` — remove the dash test block (the `# ─── dash (Dashlane wrapper) tests` section: helper `_dash_test_setup`, `_dash_test_results_with_otpauth`, and every `test_dash_*` function, roughly lines ~864–1151) **and** the matching registration calls in the runner list (the `test_dash_*` lines, roughly ~1213–1227).
- Modify: `CLAUDE.md` — remove the `dash` bullet (~line 83) and drop `dash` from the two "short, unambiguous tools (`awsso`, `dash`, `llmfix`, `bash-backup`)" sentences (~lines 74, 155).
- Modify: `README.md` — remove the `dash`/`dcli` mention (~line 101: "Additional knobs (**dcli**, …)").

**Interfaces:**
- Produces: nothing. Removes the `dash` shell function and all references.

- [ ] **Step 1: Delete the function file**

```bash
git rm .bash/functions/dash.bash
```

- [ ] **Step 2: Remove the dash tests + registrations from `tests/shell/run_tests.sh`**

Open `tests/shell/run_tests.sh`. Delete the contiguous dash section that starts at the banner comment `# ─── dash (Dashlane wrapper) tests ───` and runs through the last `test_dash_*` function definition (`test_dash_help_lists_unlock_and_shortcut`), stopping **before** `test_install_iterm_shell_integration_copies_script`. Then delete the block of `test_dash_*` invocation lines in the runner registration list near the end of the file. Verify nothing else references the removed helpers:

```bash
grep -n "dash\|dcli\|DASH_MOCK\|_dash_" tests/shell/run_tests.sh
```
Expected: no matches.

- [ ] **Step 3: Run the shell test suite**

Run: `bash tests/shell/run_tests.sh`
Expected: suite passes with the dash tests gone (no "unbound variable" / "command not found" for removed helpers). If the runner counts tests, the count drops by the number of removed `test_dash_*` functions.

- [ ] **Step 4: Strip docs references**

Edit `CLAUDE.md`: delete the `- **`dash`** — Dashlane vault access…` bullet, and change both occurrences of "a few short, unambiguous tools (`awsso`, `dash`, `llmfix`, `bash-backup`)" to "(`awsso`, `llmfix`, `bash-backup`)". Edit `README.md` line ~101: change "Additional knobs (**dcli**, **AWS PKG**, **Impeccable skill**)…" to "Additional knobs (**AWS PKG**, **Impeccable skill**)…". Verify:

```bash
grep -rIn "\bdash\b\|dcli\|[Dd]ashlane" CLAUDE.md README.md .bash/ install/ tests/ | grep -vi "dashboard\|docs/superpowers"
```
Expected: no matches.

- [ ] **Step 5: Parse-check + commit**

Run: `bash -n install.sh install/*.bash .bash/functions/*.bash`
Expected: clean (dash.bash gone, nothing references it).

```bash
git add -A
git commit -m "chore: remove dash/dcli Dashlane wrapper and its tests + docs"
```

---

### Task 1.2: Install `gh` from GitHub's apt repo on Debian/Ubuntu

**Bug:** `_linux_packages_for` maps `gh` → `gh`, but `gh` isn't in stock Debian/Ubuntu repos; plain `apt install gh` fails. Chrome already does the keyring+repo dance in `install/apps.bash:48-54` — mirror it for `gh`.

**Files:**
- Modify: `install/_helpers.bash` — add `_linux_install_gh`, route `gh` through it in `_linux_pkg_install`.
- Test: `tests/linux-packages/run_tests.sh` — assert the routing decision.

**Interfaces:**
- Produces: `_linux_install_gh` — ensures the `cli.github.com` apt keyring + source list exist, then `apt-get update && apt-get install -y gh`. Returns 0/1.
- Modifies `_linux_pkg_install`: when `name == gh` and pm is apt, delegate to `_linux_install_gh`.

- [ ] **Step 1: Write the failing test**

Add to `tests/linux-packages/run_tests.sh` a check that the gh apt source URL is correct (pure string assertion against a factored constant), so we don't shell out to apt in CI:

```bash
# gh apt repo wiring
( set -euo pipefail
  # shellcheck disable=SC1091
  source "$REPO_ROOT/install/_helpers.bash"
  url="$(_gh_apt_source_line)"
  case "$url" in
    *cli.github.com/packages*stable\ main*) : ;;
    *) echo "unexpected gh apt source: $url" >&2; exit 1 ;;
  esac
) || fail "gh apt source line"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/linux-packages/run_tests.sh`
Expected: FAIL — `_gh_apt_source_line: command not found`.

- [ ] **Step 3: Implement the helpers**

In `install/_helpers.bash`:

```bash
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
    if sudo apt-get install -y gh &>/dev/null; then
        _install_step_done_changed "gh" "installed (apt + cli.github.com)"
    else
        _install_step_fail "gh" "apt install failed"; return 1
    fi
}
```

Then in `_linux_pkg_install`, before the generic `packages=$(_linux_packages_for …)` path, add:

```bash
    if [[ "$name" == gh && "$pm" == apt ]]; then
        _linux_install_gh; return $?
    fi
```

- [ ] **Step 4: Run tests + parse checks**

Run: `bash tests/linux-packages/run_tests.sh` → ends with `linux package tests passed`
Run: `bash -n install/_helpers.bash`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add install/_helpers.bash tests/linux-packages/run_tests.sh
git commit -m "fix(linux): install gh from cli.github.com apt repo on Debian/Ubuntu"
```

---

### Task 1.3: Remove orphaned `install/external-fs.bash` reference

**Bug:** `tests/linux-packages/run_tests.sh:30` parse-checks a non-existent `install/external-fs.bash`. (`bash -n` silently returns 0 on the missing trailing file, hiding it.)

**Files:**
- Modify: `tests/linux-packages/run_tests.sh:30`

- [ ] **Step 1: Remove the dead path**

In the `bash -n` line, delete the ` install/external-fs.bash` token. Final line:

```bash
bash -n install.sh install/_helpers.bash install/packages.bash install/apps.bash install/dictation.bash install/cursor.bash install/shell.bash
```

- [ ] **Step 2: Verify**

Run: `bash tests/linux-packages/run_tests.sh` → `linux package tests passed`
Run: `grep -rn external-fs . --include=*.sh --include=*.bash` → no matches.

- [ ] **Step 3: Commit**

```bash
git add tests/linux-packages/run_tests.sh
git commit -m "test(linux): drop orphaned external-fs.bash parse-check reference"
```

---

# Phase 2 — Legacy macOS robustness

### Task 2.1: Make `_macports_name_for` version-aware + test it

**Gap:** `_macports_name_for` hardcodes `python312`/`nodejs22`/`npm10`/`py312-*`. These are correct for current MacPorts but carry risk on very old OS. Add explicit tests pinning the contract, and a single test seam so a future bump is one edit. (Keep the current names — MacPorts maintains them across supported OS — but lock them under test so a regression is caught.)

**Files:**
- Modify: `install/_helpers.bash` — no behavior change required if current names are kept; factor the versioned port names into named constants at the top of `_macports_name_for` for clarity.
- Test: `tests/macports/run_tests.sh` — add `_macports_name_for` assertions.

**Interfaces:**
- `_macports_name_for <brew_name>` — unchanged signature; echoes MacPorts port name or empty string.

- [ ] **Step 1: Write the failing test**

Add to `tests/macports/run_tests.sh`:

```bash
expect_port() {
    local brew="$1" want="$2"
    ( # shellcheck disable=SC1091
      source "$REPO_ROOT/install/_helpers.bash"
      got=$(_macports_name_for "$brew")
      [[ "$got" == "$want" ]] || { echo "name_for $brew expected='$want' got='$got'" >&2; exit 1; }
    ) || fail "_macports_name_for $brew → $want"
}
expect_port python3 python312
expect_port node nodejs22
expect_port npm npm10
expect_port virtualenv py312-virtualenv
expect_port flake8 py312-flake8
expect_port jq jq
expect_port flyctl ""           # no port — caller falls back
# awscli is Darwin-version-gated:
expect_awscli() { local dmaj="$1" want="$2"
    ( # shellcheck disable=SC1091
      source "$REPO_ROOT/install/_helpers.bash"
      uname() { [[ "$1" == -r ]] && echo "${dmaj}.0.0" || command uname "$@"; }
      got=$(_macports_awscli_port_name)
      [[ "$got" == "$want" ]] || { echo "awscli dmaj=$dmaj expected=$want got=$got" >&2; exit 1; }
    ) || fail "_macports_awscli_port_name dmaj=$dmaj → $want"
}
expect_awscli 20 py312-awscli2   # macOS 11+ (Darwin 20)
expect_awscli 19 py311-awscli    # macOS 10.15 (Darwin 19)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/macports/run_tests.sh`
Expected: FAIL initially only if helper names diverge; if it passes immediately, that confirms the contract — proceed (the value here is the regression lock, not a code change).

- [ ] **Step 3: (If needed) factor port-name constants**

If you want the bump-in-one-place seam, near the top of `_macports_name_for` add:
```bash
    local PORT_PYTHON=python312 PORT_NODE=nodejs22 PORT_NPM=npm10 PY=py312
```
and reference them (`echo "$PORT_PYTHON"`, `echo "$PORT_NODE"`, `echo "$PORT_NPM"`, `echo "${PY}-virtualenv"`, `echo "${PY}-flake8"`). Behavior is identical; the test stays green.

- [ ] **Step 4: Run tests**

Run: `bash tests/macports/run_tests.sh` → ends with the suite's existing success line.
Run: `bash -n install/_helpers.bash`

- [ ] **Step 5: Commit**

```bash
git add install/_helpers.bash tests/macports/run_tests.sh
git commit -m "test(macports): lock port-name + awscli Darwin-gate mappings"
```

---

# Phase 3 — Coverage & polish

### Task 3.1: Broaden Linux package-map tests; fix pip-search/autopep8

**Gap:** Only 4 of ~15 `_linux_packages_for` mappings are tested; `pip-search`/`autopep8` fall through to passthrough names that don't exist in apt (they're pip tools and should route through pip, not apt).

**Files:**
- Modify: `install/_helpers.bash` — confirm pip-only tools aren't requested via `_linux_pkg_install` (they should go through `_pip_install`). If `_linux_packages_for` is ever asked for them, return empty so the caller's escape hatch triggers, and add `pip-search`/`autopep8` to the direct-install escape list alongside `uv`/`flyctl`, routing to `_pip_install`.
- Test: `tests/linux-packages/run_tests.sh` — assert all current mappings.

- [ ] **Step 1: Write the failing/expanded test**

Add assertions for every mapping currently in `_linux_packages_for`:

```bash
assert_mapping python3 apt "python3"
assert_mapping jq apt "jq"
assert_mapping shellcheck apt "shellcheck"
assert_mapping flake8 apt "python3-flake8"
assert_mapping pipx apt "pipx"
assert_mapping screen apt "screen"
assert_mapping tmux apt "tmux"
assert_mapping cmatrix apt "cmatrix"
assert_mapping awscli apt "awscli"
assert_mapping git apt "git"
assert_mapping wget apt "wget"
assert_mapping tree apt "tree"
assert_mapping ccache apt "ccache"
assert_mapping flyctl apt ""
assert_mapping virtualenv dnf "python3-virtualenv"
```

- [ ] **Step 2: Run to verify pass/fail**

Run: `bash tests/linux-packages/run_tests.sh`
Expected: PASS for existing mappings; if any differ from the live `case`, fix the test to match reality or the map if it's wrong.

- [ ] **Step 3: Route pip-only tools via pip**

If `install/packages.bash` calls `_pkg_install pip-search`/`_pkg_install autopep8` on Linux, change those call sites to `_pip_install pip-search` / `_pip_install autopep8` (matching how they're handled on macOS). Verify with:
Run: `grep -n "pip-search\|autopep8" install/packages.bash`

- [ ] **Step 4: Run tests**

Run: `bash tests/linux-packages/run_tests.sh` → `linux package tests passed`

- [ ] **Step 5: Commit**

```bash
git add install/_helpers.bash install/packages.bash tests/linux-packages/run_tests.sh
git commit -m "test(linux): cover all apt mappings; route pip-only tools via pip"
```

---

### Task 3.2: Document the support floor + refresh the platform matrix

**Files:**
- Modify: `README.md` (Platform Coverage table + a "Supported OS" line), `CLAUDE.md` (legacy section).

- [ ] **Step 1: State the floor and Linux scope**

Add to `README.md`: "**Supported OS:** macOS 10.6+ (Snow Leopard and newer; MacPorts auto-install is `.pkg`-based down to 10.6, 10.5 is manual) on Intel and Apple Silicon; Debian/Ubuntu (apt) on Linux. dnf/yum mappings exist but are best-effort and untested." Update the Platform Coverage table's "GUI apps / Linux" cell to "Chrome via apt (Debian/Ubuntu)".

- [ ] **Step 2: Verify + commit**

Run: `grep -n "Supported OS\|best-effort" README.md`

```bash
git add README.md CLAUDE.md
git commit -m "docs: state supported-OS floor and Debian/Ubuntu Linux scope"
```

---

## Final verification (run before opening a PR)

- [ ] Parse-check everything:
```bash
bash -n install.sh scripts/*.sh install/*.bash mcp/*.bash .bash/prefs.bash .bash/prompt.bash .bash/functions/*.bash
```
- [ ] Run the full suite:
```bash
for t in sudo bootstrap clipboard macports linux-packages packages shell mcp cursor claude agents-doctor; do
  echo "== $t =="; bash "tests/$t/run_tests.sh" || echo "FAILED: $t"; done
```
- [ ] `shellcheck` where available on changed files.
- [ ] Manual smoke (a Linux box or VM, and a legacy Mac if available):
  `DOTFILES_SKIP_INSTALL_ALL=1 /bin/bash -c "$(curl -fsSL …/scripts/bootstrap.sh)"` — confirm it clones without installing Homebrew on legacy macOS and without erroring on Linux.

---

## Notes / decisions deferred to review

- **dnf/yum + Arch:** out of scope per the user's Debian/Ubuntu-only target. Left best-effort and documented as untested.
- **Cursor GUI on Linux:** not added here (the audit notes Linux Cursor relies on `cursor-agent`); revisit if desired.
- **Clipboard abstraction:** dropped — removing `dash` (Task 1.1) eliminates the only `pbcopy` consumer, so a cross-platform `_dot_clipcopy` would be dead code (YAGNI). Reintroduce only if a future function needs clipboard access.
- **Legacy-macOS hardware verification:** Tasks 0.2 and 2.1 cannot be fully verified without a real legacy Mac. The plan compensates with pure-function unit tests and a `DOTFILES_SKIP_INSTALL_ALL=1` smoke path; flag any real-hardware run results in the PR.
