# Task 0.2 Report — OS-aware universal `scripts/bootstrap.sh`

## What Was Implemented

**Three files changed** in commit `89cf0b8`:

1. **`scripts/bootstrap.sh`** (new, 128 lines) — Universal OS-aware bootstrap. Exposes two pure testable functions: `_bootstrap_os` (echoes `macos`|`linux`|`unsupported`) and `_bootstrap_macos_pkg_strategy <version>` (echoes `macports` for major<15, `homebrew` for ≥15). `_main` orchestrates: detects OS, installs only CLT (macOS) or git via apt (Linux), primes sudo via /dev/tty, clones over public HTTPS, then calls `./install.sh ssh` + `./install.sh all`. `set -euo pipefail` lives inside `_main`, not at top level — so `source bootstrap.sh --source-only` defines functions without triggering pipefail in the test subshell. The `--source-only` guard at the bottom (`return 0 2>/dev/null || exit 0`) handles both sourced and non-sourced execution contexts.

2. **`scripts/bootstrap-macos.sh`** (overwritten, 10 lines) — Back-compat shim. `exec /bin/bash "$DIR/bootstrap.sh"` when sibling file exists; otherwise `curl`-fetches the universal script. Old URL still works.

3. **`tests/bootstrap/run_tests.sh`** (appended) — New block in a subshell sources `bootstrap.sh --source-only` then asserts four `_bootstrap_macos_pkg_strategy` cases (13.6.1→macports, 10.14.6→macports, 15.0→homebrew, 26.0→homebrew). Uses the file's existing `fail` and `REPO_ROOT` conventions verbatim.

## TDD Evidence

**RED** — after appending test, before creating `bootstrap.sh`:
```
$ bash tests/bootstrap/run_tests.sh
bootstrap tests passed
tests/bootstrap/run_tests.sh: line 96: /Users/cfischer/Code/mydot/scripts/bootstrap.sh: No such file or directory
FAIL: bootstrap macOS strategy detection
```
Exit code 1. Correct failure reason: file missing.

**GREEN** — after creating `bootstrap.sh` and shim:
```
$ bash tests/bootstrap/run_tests.sh
bootstrap tests passed
bootstrap detection tests passed
```
Exit code 0. All existing + new assertions pass.

**Parse check:**
```
$ bash -n scripts/bootstrap.sh scripts/bootstrap-macos.sh install.sh
parse ok
```

**Shellcheck** — two non-fatal findings, both intentional:
- SC2024 (warning): `sudo -v < /dev/tty > /dev/tty` — the redirection is deliberate (reads password from tty, keeps output on tty even under `curl | bash`).
- SC2317 (info): `exit 0` after `return 0 2>/dev/null` appears unreachable — this is the sourced-vs-non-sourced guard; unreachable in the sourced case by design.

## Files Changed

- `/Users/cfischer/Code/mydot/scripts/bootstrap.sh` — created
- `/Users/cfischer/Code/mydot/scripts/bootstrap-macos.sh` — replaced with shim
- `/Users/cfischer/Code/mydot/tests/bootstrap/run_tests.sh` — appended new test block

## Self-Review

**Completeness:** bootstrap.sh created, shim in place, tests appended, existing assertions pass, new assertions pass. ✅

**Quality:** Matches repo style (bash 3.2 compatible, uname-s detection, emoji status lines, `DOTFILES_*` env vars). No `declare -A`, no `${var^^}`, no `mapfile`. ✅

**Discipline (YAGNI):** No dnf/yum Linux paths added. `install.sh` not modified. Docs not touched (Task 0.3). ✅

**Testing:** `--source-only` guard verified to not run `_main` (no `xcode-select` or network calls during tests). Four strategy detection cases cover both boundary values and interior values. ✅

## Concerns / Deviations

None. The brief's appended test snippet dropped in cleanly without adaptation — the existing file's function-based structure with `fail` and `REPO_ROOT` is fully compatible with the subshell pattern in the snippet. The shellcheck warnings are pre-existing in the brief's code and are intentional.

---

## Fix: gh install on Debian private-fork path (code-review finding)

**What changed:** Added `_bootstrap_install_gh_apt` local helper function to `scripts/bootstrap.sh` and called it from the `_clone_dotfiles` Linux branch in place of the broken bare `sudo apt-get install -y gh || true`.

**Root cause:** `gh` is not in stock Debian/Ubuntu apt repos. The old one-liner silently no-oped, then `gh auth login` / `gh repo clone` hit command-not-found and aborted the bootstrap under `set -e`.

**Fix:** `_bootstrap_install_gh_apt` mirrors `_linux_install_gh` in `install/_helpers.bash` exactly:
1. `sudo mkdir -p -m 755 /etc/apt/keyrings`
2. `curl … | sudo gpg --dearmor --yes -o /etc/apt/keyrings/githubcli-archive-keyring.gpg`
3. `sudo chmod go+r` the keyring
4. Write `deb [arch=$(dpkg --print-architecture) signed-by=…] https://cli.github.com/packages stable main` to `/etc/apt/sources.list.d/github-cli.list` via `sudo tee`
5. `sudo apt-get update && sudo apt-get install -y gh`

Self-contained (no sourcing of `install/_helpers.bash`). Bash 3.2 compatible (no `declare -A`, `${var^^}`, `mapfile`, `&>>`).

**Verification:**
```
$ bash -n scripts/bootstrap.sh && echo PARSE_OK
PARSE_OK

$ shellcheck scripts/bootstrap.sh
# Only pre-existing SC2024/SC2317 — no new warnings

$ bash tests/bootstrap/run_tests.sh
bootstrap tests passed
bootstrap detection tests passed

$ bash -c 'source scripts/bootstrap.sh --source-only && type _bootstrap_install_gh_apt && echo SEAM_OK'
_bootstrap_install_gh_apt is a function
…
SEAM_OK
```

**Files changed:** `scripts/bootstrap.sh` only (16 lines added).
