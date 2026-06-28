# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A personal dotfiles repository for macOS (with Linux compatibility) that manages bash configuration, IDE settings, vim, MCP servers, and system utilities. Files are copied (not symlinked) to `~` during installation.

## Installation

Credentials live in `~/.bash/credentials.bash`, which is gitignored and sourced by `prefs.bash` if present. Fill it in yourself (e.g. `export GREPLER_TOKEN=...`, `export ANTHROPIC_API_KEY=...`); the repo no longer ships a secret-sync backend.

```bash
./install.sh all          # Full install (Linux skips macOS-only apps)
./install.sh dotfiles     # Just dotfiles (prompts for config on first run)
./install.sh ssh              # Install SSH config (generic github.com block)
./install.sh bootstrap      # macOS prerequisites: CLT + Homebrew + gh auth (see docs/fresh-mac-bootstrap.md)
./install.sh vim          # Vim config + vim-plug
./install.sh packages     # CLI packages (Homebrew/MacPorts on macOS; apt/dnf/yum on Linux)
./install.sh apps         # GUI apps via Homebrew cask (Chrome + Cursor; macOS)
./install.sh iterm        # iTerm2 cask + sync prefs plist + register as default terminal
./install.sh cursor       # Cursor IDE config
./install.sh claude       # Claude Code settings + MCP cleanup
./install.sh agents-doctor # Agent CLI paths, versions, duplicate installs, MCP status
./install.sh composio     # Composio MCP registration for Claude Code, Cursor, Codex, plus Desktop fallback
./install.sh composio-auth login  # Print native Composio MCP OAuth steps for each client
./install.sh grepler      # Grepler MCP registration for Claude Code, Claude Desktop, Cursor, and Codex
./install.sh shell        # Set bash as default + zsh compat + terminal colors
./install.sh hostname     # Sync macOS hostname settings
./install.sh backup       # Backup existing configs to /tmp/
```

### Legacy macOS and optional install tuning

On Apple Silicon, `install.sh` re-execs itself under **arm64** when launched from a Rosetta shell and `_ensure_brew` prefers native Homebrew at `/opt/homebrew`; Intel Homebrew at `/usr/local` is not accepted as the default package path. macOS **&lt; 15** prefers **MacPorts** for CLI packages (Homebrew often lacks bottles). Useful environment variables:

| Variable | Effect |
| --- | --- |
| `DOTFILES_ALLOW_ROSETTA=1` | Skip the Apple Silicon arm64 re-exec guard. Use only when intentionally testing x86/Rosetta paths. |
| `DOTFILES_SKIP_MACPORTS_UPDATE=1` | Skip `port selfupdate` during installs |
| `DOTFILES_SKIP_BREW_UPDATE=1` | Skip `brew update` metadata prefetch |
| `DOTFILES_SKIP_AWSCLI_PKG=1` | Skip AWS `CLIV2.pkg` fallback on macOS after MacPorts/Homebrew fail |
| `DOTFILES_SKIP_IMPECCABLE_SKILL=1` | Skip global Impeccable skill (`npx skills`) in `packages` |
| `DOTFILES_CLAUDE_SKIP_CHROME=1` | `claude` wrapper: do not pass `--chrome` by default (Claude in Chrome integration) |

Standalone `./install.sh packages` on legacy macOS caches **sudo** up front when MacPorts is preferred (same ergonomics as `all`). Use `./install.sh --help`, `-h`, or `help` to print **`DOTFILES_*`** tuning variables (exits **0**); an unknown subcommand prints the same text and exits **1**.

Focused shell tests exist under `tests/`. Validate changes with parse checks, shellcheck when available, and relevant test scripts:
```bash
bash -n install.sh install/*.bash mcp/*.bash .bash/prefs.bash .bash/prompt.bash .bash/functions/*.bash
tests/shell/run_tests.sh
tests/mcp/run_tests.sh
tests/cursor/run_tests.sh
tests/claude/run_tests.sh
tests/agents-doctor/run_tests.sh
tests/bootstrap/run_tests.sh
tests/packages/run_tests.sh
tests/linux-packages/run_tests.sh
tests/macports/run_tests.sh
```

## Architecture

### Bash Config (`.bash/`)
The shell config is split into modular files, all sourced by `.bashrc`:
- **`config.bash`** — User-specific settings, committed directly. Variables: `DOTFILES_GIT_NAME`, `DOTFILES_GIT_EMAIL`, `DOTFILES_BRANCH_PREFIX`, `DOTFILES_DIR`, `DOTFILES_HOSTS_API_URL`, `DOTFILES_PIPX_PYTHON`, `DOTFILES_SKIP_MODULES`. Optional **`DOTFILES_FAST_SHELL`** / **`DOTFILES_FAST_PROMPT`** lighten startup Heroku/gcloud completion and git dirty checks in the prompt. **`config.bash.example`** is the template when creating a fresh config.
- **`prefs.bash`** — PATH, env vars, aliases, pipx config (sources `config.bash` early, sources `credentials.bash` if present). Honors **`DOTFILES_FAST_SHELL`** by skipping optional Heroku + Google Cloud SDK completion sourcing.
- **`functions/`** — One file per function, auto-loaded by `_loader.bash`. Respects `DOTFILES_SKIP_MODULES`
- **`functions.bash`** — Shim that sources `functions/_loader.bash` (kept for backward compat)
- **`prompt.bash`** — PS1 prompt with git branch/dirty state (or branch-only when **`DOTFILES_FAST_PROMPT=1`**), venv display, error-aware coloring. Updates Screen window titles via `PROMPT_COMMAND` (lighter titles in fast prompt mode).
- **`credentials.bash`** — Local credential cache (gitignored). Fill it in yourself with `export VAR=...` lines for any secrets the tooling needs (e.g. `GREPLER_TOKEN`, `ANTHROPIC_API_KEY`); sourced by `prefs.bash` if present

### Bash Functions (`.bash/functions/`)
Most custom functions use the `dot-` prefix; a few short, unambiguous tools (`awsso`, `dash`, `llmfix`, `bash-backup`) don't. Each lives in its own file:
- **`awsso`** — Interactive picker for `aws sso login`. Reads `[sso-session ...]` blocks from `~/.aws/config`. Bare `awsso` shows a menu (or logs in directly when only one session exists); `awsso <name>` skips the menu; `awsso --all` logs into every session. After a single-session login, mirrors temporary credentials into `~/.aws/credentials` under both `[default]` and `[<matching profile>]` so tools that hit the default credential chain (no `AWS_PROFILE` / `--profile`) pick up the most recently logged-in session. `--all` skips the mirror (ambiguous which session should win).
- **`dot-aws-switch`** — Set the active AWS profile for the current shell. Bare `dot-aws-switch` shows a numbered picker of `[profile ...]` blocks; `dot-aws-switch <name>` sets directly; `dot-aws-switch --unset` clears `AWS_PROFILE`/`AWS_REGION`. Exports `AWS_REGION` from the chosen profile's `region =` line (and unsets it when the profile has none, to avoid stale leakage).
- **`dot-branch-name`** — Generate branch names: `{prefix}/{MMDD}/{feature}`
- **`dot-commit-llm`** — AI-generated commit messages (OpenAI/Anthropic/Claude API)
- **`dot-hosts`** — Host registry management (ping, lookup, sync to /etc/hosts)
- **`dot-kill`** — Kill processes by name (graceful then force)
- **`dot-gitclean`** — Delete merged branches + prune remotes
- **`dot-fly-switch`** — Switch Fly.io CLI context (work/personal)
- **`dash`** — Dashlane vault access via `dcli`. Subcommands: `search`, `get`, `otp`, `note`, `unlock`, `admin`. Also supports a bare-site shortcut: `dash <site>` (any non-reserved first arg) routes to `unlock`. `unlock <site>` runs search + get + otp + note in one shot; piped mode dumps every match as `TITLE:`/`LOGIN:`/`PASSWORD:`/`OTP_CODE:`/`NOTE:` lines. Every retrieval also scans the entry's `note` field for `otpauth://totp/...` URLs and auto-mints the 6-digit TOTP code (note-embedded seeds work alongside Dashlane's native OTP store — both paths run, both surface). TTY-aware emit — copies to clipboard when run interactively, prints to stdout when captured (so tool invocations can read the value directly). Every retrieval is appended to `~/.dash.log` (best-effort). First-run: `dash admin setup`.
- **`dot-cursor-backup`** — Export Cursor settings/extensions and commit to this repo
- **`dot-iterm-backup`** — Re-template the live `system/iterm2/com.googlecode.iterm2.plist` (which iTerm has been writing to directly) into `com.googlecode.iterm2.plist.template` with `$HOME` → `__DOTFILES_HOME__`, then commit/push
- **`dot-claude-sync`** — Mirror enabled Claude Desktop extensions into Claude Code's `mcpServers` in `~/.claude.json`. Reads each extension's `manifest.json` + matching `Claude Extensions Settings/<id>.json`, resolves `${__dirname}` to absolute paths, inlines non-sensitive `user_config` values, and emits sensitive values as `${ENV_VAR}` refs (uppercase of the user_config key — set the matching var in `credentials.bash`). Tags each entry with `_source: "claude-extension:<id>"` so re-runs sweep removed/disabled extensions. Re-run after installing or updating a Desktop extension.
- **`bash-backup`** — Back up `~/.bash` to this repo and push
- **`dot-flushcache`** — Flush DNS cache (macOS)
- **`dot-mac-spoof`** — Spoof MAC address (macOS)
- **`llmfix`** — Fix last failed command using ChatGPT
- **`claude`** — Wrapper that passes `--chrome` by default (Claude in Chrome); use `claude --no-chrome` or **`DOTFILES_CLAUDE_SKIP_CHROME=1`** to skip
- **`claude yolo`** — Wrapper for `claude --dangerously-skip-permissions` (also gets default `--chrome`)
- **`codex yolo`** — Wrapper for `codex --dangerously-bypass-approvals-and-sandbox`
- **`gemini yolo`** — Wrapper for `gemini --yolo` (auto-approve all tool calls); other `gemini` invocations fall through to the real CLI
- **`cursor yolo`** — Wrapper for `cursor-agent --force` (other `cursor` invocations fall through to the GUI launcher)

### Installation (`install.sh` + `install/`)
Slim dispatcher that sources modular install scripts from `install/`:
- **`_helpers.bash`** — `_section_run()` (compact progress output), Apple Silicon Rosetta guard (`_maybe_reexec_arm64`), `timestamp()`, `_brew_install`, `_brew_cask_install`, `_pkg_install` (version-gated dispatcher), `_ensure_brew` (native `/opt/homebrew` on Apple Silicon), `_ensure_macports`, `_macports_pkg_slug` / `_macports_pkg_slug_from_version` (maps `sw_vers` output to MacPorts `.pkg` filenames, including OS X 10.x), `_prefer_macports`, `_pip_install`, `_ensure_sudo_cached` (caches sudo + spawns keepalive once, called before captured sections so password prompts don't land mid-output), `backup()`, `print_usage` (documents **`DOTFILES_*`** tuning vars). The **`all`** orchestration runs every section through **`_all_run`** (records a failure into `_DOTFILES_ALL_FAILED` and continues instead of aborting) and ends with **`_all_summary`** (lists failed sections + re-run commands, exits 1 if any failed). Only `_verify_repo_complete` aborts up front; missing sudo is a non-fatal warning. This is the fix for "`install.sh all` won't complete" — one flaky section no longer kills the whole run.
- **`dotfiles.bash`** — `install_dotfiles()` copies `.bash/`, `.vim/`, and the individual top-level dotfiles (`.bashrc`, `.gitconfig`, etc.) into `~/`
- **`ssh.bash`** — `install_ssh()` (installs `system/ssh/config` → `~/.ssh/config.d/dotfiles`, `ssh-add` on macOS).
- **`bootstrap.bash`** — `install_bootstrap()` (macOS: Xcode CLT, Homebrew, gh auth; see `docs/fresh-mac-bootstrap.md` and `scripts/bootstrap-macos.sh` for pre-clone one-liner)
- **`packages.bash`** — `install_packages()` (CLI tools: python3, node, jq, uv, shellcheck, pipx, gh, flyctl, screen, tmux, awscli, codex, Claude Code, Gemini CLI, cursor-agent, composio, Impeccable CLI, and the global Impeccable agent skill). Routes package installs through `_pkg_install`, which prefers **MacPorts on macOS <15**, native **Homebrew on macOS 15+**, and **apt/dnf/yum on Linux**. On macOS <15 both managers are installed so casks still work for GUI apps. **Agent CLI install tiers** (see `_classify_agent_install` in `install/_helpers.bash`): **official curl** (`cursor-agent`, `composio`) — self-managed, with `cursor-agent` refreshed by rerunning Cursor's official installer when packages run; **user-prefix npm** at `~/.local` (`codex` always; `gemini-cli` always; `claude-code` unless native standalone) — brew global npm copies are migrated via `_remove_off_prefix_npm_agent`, including hidden duplicates behind the `~/.local` PATH entry; **Cursor.app** via brew cask `--no-binaries` with `~/.local/bin/cursor` symlinked to the app bundle (`_link_cursor_cli`). Agent CLIs are resolved with **`_agent_bin_path`** (`type -P`, not `command -v`) so shell wrapper functions don't shadow binaries. **Codex** managed npm installs explicitly use `@openai/codex@latest`. **Claude Code** managed npm installs explicitly use `@anthropic-ai/claude-code@latest`; native standalone installs (`~/.local/share/claude/versions/`) are managed via `claude update` and `ide/claude/settings.json` pins `autoUpdatesChannel: latest`. **AWS CLI**: MacPorts port slug varies by Darwin version (`py312-awscli2` vs `py311-awscli`); fallbacks include AWS-signed **`CLIV2.pkg`** and **pipx** (CLI v1). Optional **`DOTFILES_*`** env vars for legacy machines — see *Legacy macOS and optional install tuning* above.
- **`agents-doctor.bash`** — `install_agents_doctor()` prints resolved paths, all PATH matches, install classification, versions, npm-prefix package status for Codex/Claude, and Composio MCP registration status across Claude Code, Cursor, and Codex. Run with `./install.sh agents-doctor` or `./install.sh doctor`.
- **`apps.bash`** — `install_apps()` (universal GUI apps via `brew install --cask`: `google-chrome` + `cursor` on macOS; `google-chrome` via apt on Linux). Personal, account-gated apps are intentionally not installed.
- **`iterm.bash`** — `install_iterm()` (iTerm2 cask + points iTerm at `system/iterm2/` via `LoadPrefsFromCustomFolder` + `PrefsCustomFolder`, enables shell integration auto-load + movement-scroll prefs, installs `~/.iterm2_shell_integration.bash`, prompts user to set as default terminal via menu since macOS has no CLI for that). The repo *is* iTerm's preference store — iTerm reads from and writes back to `system/iterm2/com.googlecode.iterm2.plist` (gitignored), no quit-and-overwrite dance needed (cfprefsd updates iTerm live). On first install only, the rendered plist is generated from `com.googlecode.iterm2.plist.template` with `__DOTFILES_HOME__` → `$HOME`; subsequent runs leave the rendered file alone so iTerm's saved changes aren't clobbered. To pick up upstream template changes, delete `system/iterm2/com.googlecode.iterm2.plist` and re-run. To capture local prefs back into git as a fork-safe template, use `dot-iterm-backup`. Bash loads integration via `.bash/iterm.bash` (after `prompt.bash`) with `ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX=1` so iTerm can detect/fix stuck mouse reporting after SSH/tmux drops.
- **`vim.bash`** — `install_vim()` (downloads vim-plug, plugins auto-install on first vim open)
- **`shell.bash`** — `configure_shell()` (bash as default, .zshrc compat shim, Terminal.app colors)
- **`cursor.bash`** — `install_cursor()` (merge settings/keybindings like Claude Code; sync extensions from `extensions.txt` with install + optional prune; link `~/.local/bin/cursor` to Cursor.app). Skip extension prune with **`DOTFILES_CURSOR_SKIP_EXTENSION_PRUNE=1`**. Does not install `workspaceStorage` (machine-local; backup via `dot-cursor-backup` only).
- **`claude.bash`** — `install_claude()` (merges settings including `claudeInChromeDefaultEnabled` and `chrome-devtools-mcp` plugin, installs Claude plugins, cleans stale MCPs; prints browser-stack reminders — see `ide/chrome/README.md`)
- **`hostname.bash`** — `configure_hostname()` (syncs macOS ComputerName/LocalHostName/HostName)

Copies files from repo to `~` (not symlinks). Backups go to `/tmp/dotfiles_backup_<timestamp>/`.

### MCP Servers (`mcp/`)
MCP servers extend local AI clients with external data sources. Registered in these configs:
- `~/.claude.json` (Claude Code)
- `~/Library/Application Support/Claude/claude_desktop_config.json` (Claude Desktop, macOS only)
- `~/.cursor/mcp.json` (Cursor)
- `~/.codex/config.toml` (Codex)

Helper functions in `mcp/_helpers.bash`:
- **`_register_mcp_server`** / **`_register_desktop_mcp_server`** / **`_register_cursor_mcp_server`** — stdio servers
- **`_register_url_mcp_server`** / **`_register_desktop_url_mcp_server`** / **`_register_cursor_url_mcp_server`** — HTTP/SSE URL servers
- **`_register_codex_mcp_server`** — Codex stdio servers via `codex mcp add`, with a direct config fallback
- **`_register_codex_url_mcp_server`** — Codex streamable HTTP MCP servers via `codex mcp add --url`, with optional bearer env var and direct config fallback
- **`_register_extension_mcp_server`** — Claude Desktop extension binary, registers in Code + Cursor only (Desktop manages natively)
- **`_cleanup_stale_mcp_servers`** — removes retired servers from Claude Code, Claude Desktop, Cursor, Codex, and stale `~/.mcp/` disk files
- **`_cleanup_extension_managed_from_desktop`** — removes extension-managed entries from Desktop config

Active MCPs are Composio, Grepler, and Playwright, all managed by this repo. `./install.sh mcp` registers each server in `DOTFILES_MCP_SERVERS`. Retired servers are swept out by `_cleanup_stale_mcp_servers`; your own unmanaged MCP servers are left untouched. Composio (`mcp/composio.bash`) registers `https://connect.composio.dev/mcp` as a native remote HTTP OAuth MCP in Claude Code, Cursor, and Codex; Codex login is `codex mcp login composio`, Claude Code login is `/mcp` -> `composio` -> `Reconnect`, and app-specific connectors are approved in the Composio dashboard. It also installs `~/.local/bin/composio-mcp` as a legacy `mcp-remote` wrapper and adds a best-effort Claude Desktop proxy when `npx` is available. See `mcp/composio-auth.md`. Grepler (`mcp/grepler.bash`) installs `~/.local/bin/grepler-mcp`, sources `GREPLER_TOKEN`, and execs `npx mcp-remote` against `https://grepler.dev/mcp/` with bearer auth. Playwright (`mcp/playwright.bash`) installs `~/.local/bin/playwright-mcp` (`npx @playwright/mcp --extension`) in Claude Code, Claude Desktop, Cursor, and Codex; pair with the Playwright MCP Bridge Chrome extension (`ide/chrome/README.md`). Optional `PLAYWRIGHT_MCP_EXTENSION_TOKEN` in `credentials.bash` skips tab-approval prompts.

Retired MCPs (`lifelog`, `glowscape`) are listed in `_cleanup_stale_mcp_servers` (`mcp/_helpers.bash`) so subsequent installs sweep their entries out of `~/.claude.json`, `~/.cursor/mcp.json`, the Claude Desktop config, and `~/.codex/config.toml`. Their functionality is available through Grepler.

**Two MCP install patterns:**
- **Pattern A — Local `.mcpb` extension MCPs**: user installs via Claude Desktop UI; `dot-claude-sync` mirrors into Claude Code. Account-independent because extensions are machine-local.
- **Pattern B — Remote URL MCPs**: prefer native remote HTTP registration where the client supports the server's auth flow (Composio OAuth in Claude Code, Cursor, Codex). Use a stdio wrapper at `~/.local/bin/<name>-mcp` for hosted MCPs that need local credential injection or clients that still need an `mcp-remote` proxy (Grepler, Claude Desktop fallback).

### IDE Config
- **`ide/cursor/`** — Cursor settings, keybindings, extensions list, snippets. Backed up via `dot-cursor-backup`
- **`ide/claude/`** — Claude Code `settings.json` (merged non-destructively during install; sets the auto-update channel to `latest`, enables Claude in Chrome by default, and enables the `chrome-devtools-mcp` plugin)
- **`ide/chrome/`** — Standard Chrome extension set + Claude Code browser stack docs (extensions sync via Google Chrome, not installed by dotfiles)

### System Config (`system/`)
- **`system/macos/`** — Terminal.app preferences, Homebrew color scheme, terminal-colors.sh
- **`system/iterm2/`** — `com.googlecode.iterm2.plist.template` (committed, with `__DOTFILES_HOME__` placeholders) and `com.googlecode.iterm2.plist` (gitignored, the live file iTerm reads/writes via `LoadPrefsFromCustomFolder`). Capture template-safe changes back into git with `dot-iterm-backup`.
- **`system/ssh/`** — `config`: a generic `github.com` SSH block installed to `~/.ssh/config.d/dotfiles`. Add your own hosts in a private `~/.ssh/config.d/*.local`.

### Apps (`apps/`)
- **`apps/mounts/`** — External filesystem management (SSH + S3). Python script + YAML config
- **`apps/network/`** — Network reporting utilities

## Conventions

- Most custom bash functions use the `dot-` prefix (e.g., `dot-kill`, `dot-hosts`, `dot-branch-name`, `dot-commit-llm`); a few short, unambiguous tools (`awsso`, `dash`, `llmfix`, `bash-backup`) don't
- Each function lives in its own file under `.bash/functions/` (named after the primary function)
- Tightly coupled private helpers (e.g., `_dot-hosts-*`) stay with their parent function's file
- Functions include `-h`/`--help` support with usage text
- Functions use color output and emoji for status indicators
- Platform detection via `uname -s` for macOS vs Linux differences
- Personal values go in `.bash/config.bash` with `DOTFILES_*` variable names
- Package installs in `install/packages.bash` go through `_pkg_install <brew-name>`, not `_brew_install` directly — the dispatcher in `_helpers.bash` handles MacPorts name translation for older macOS. Brew name → MacPorts name mapping lives in `_macports_name_for()` (e.g. `python3` → `python312`, `node` → `nodejs22`). `flyctl` has no MacPorts port and falls back to the official installer script.
- Credentials live in `.bash/credentials.bash` (gitignored; fill it in yourself — no secret-sync backend ships with the repo)
- The `.zshrc` is a compatibility shim that sources the bash config files
- Backup functions (`bash-backup`, `dot-cursor-backup`) auto-commit changes to this repo
- Users can skip individual function modules via `DOTFILES_SKIP_MODULES` in config
- Claude Desktop manages `.mcpb` extensions natively. Claude Code extension sync remains handled by `dot-claude-sync`. Active remote MCPs (`composio`, `grepler`) are installed through `./install.sh mcp` or their individual targets.
- New MCP servers: add `mcp/<name>.bash`, add a case in `install.sh` if it should be directly installable, append the name to `DOTFILES_MCP_SERVERS` in `mcp/install.bash`, and update `print_usage` plus README/CLAUDE docs. Follow Pattern B (stdio wrapper, 4-way registration) for any remote URL MCP — see `mcp/composio.bash` for the canonical example.
