# mydot

Personal development environment for macOS and Linux: bash configuration, coding-agent CLIs (Claude Code, Cursor, Codex), vim, MCP servers, and cross-platform install tooling. Files are **copied** (not symlinked) to `~` during installation.

## Quick Start

### Brand-new Mac (nothing installed yet)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap.sh)"
```

Installs only what's needed to clone (Xcode CLT on macOS, git on Debian/Ubuntu), then clones and runs `./install.sh all`, which prefers MacPorts on macOS <15, Homebrew on 15+, and apt on Linux. (The legacy `bootstrap-macos.sh` URL still works.)

See [`docs/fresh-mac-bootstrap.md`](docs/fresh-mac-bootstrap.md) for fresh-machine setup and troubleshooting.

### Already have Homebrew

```bash
git clone https://github.com/thechrisfischer/mydot.git ~/Code/mydot
cd ~/Code/mydot
./install.sh all
```

### Legacy quick start (SSH — only if you have an SSH key set up)

```bash
git clone git@github.com:thechrisfischer/mydot.git ~/Code/mydot
cd ~/Code/mydot
./install.sh all
```

### Credentials

Secrets live in `~/.bash/credentials.bash` (gitignored). There is no secret-sync
backend — fill it in yourself with plain `export` lines for whatever the tooling
needs, e.g.:

```bash
export GREPLER_TOKEN="..."
export ANTHROPIC_API_KEY="..."
export OPENAI_API_KEY="..."
```

`prefs.bash` sources the file if present. Do not commit it.

## Fork This First

This repo is designed to be forked and adapted. Before running the installer on your own machine, make these three changes in your fork:

1. **Repo identity** — The bootstrap script clones the repo identified by the `DOTFILES_GITHUB` env var (not by the URL you curl from). Simply changing the curl URL fetches your script but still clones upstream. To install YOUR fork, do one of:
   - Pass it inline:
     ```bash
     DOTFILES_GITHUB=<you>/mydot /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/<you>/mydot/main/scripts/bootstrap.sh)"
     ```
   - Or edit the `DOTFILES_GITHUB` default in your fork's `scripts/bootstrap.sh`, then run from your fork's URL.

2. **Git identity** — Set `DOTFILES_GIT_NAME`, `DOTFILES_GIT_EMAIL`, and `DOTFILES_DIR` (e.g. `$HOME/Code/mydot`) in `.bash/config.bash`. Copy `config.bash.example` as a starting point.

3. **Secrets** — Create `~/.bash/credentials.bash` with `export` lines for your tokens and API keys (gitignored; no secret-sync backend ships with this repo).

## Installation Commands

```bash
./install.sh all          # Full install (Linux skips macOS-only apps)
./install.sh dotfiles     # Copy dotfiles into ~/
./install.sh bootstrap      # macOS: CLT + Homebrew + gh auth (in-repo; see docs/fresh-mac-bootstrap.md)
./install.sh ssh          # Install SSH config (generic github.com block)
./install.sh vim          # Vim config + vim-plug (plugins install on first vim open)
./install.sh packages     # CLI packages (Homebrew/MacPorts on macOS; apt/dnf/yum on Linux)
./install.sh apps         # GUI apps via Homebrew cask: Chrome + Cursor (macOS; Linux gets Chrome)
./install.sh iterm        # iTerm2 app + custom prefs folder
./install.sh cursor       # Cursor IDE settings, keybindings, extensions
./install.sh claude       # Claude Code settings + MCP cleanup
./install.sh codex        # Codex plugin configuration
./install.sh agents-doctor # Agent CLI paths, versions, duplicate installs, MCP status
./install.sh mcp          # All enabled MCP servers
./install.sh composio     # Composio MCP registration for Claude Code, Cursor, Codex, plus Desktop fallback
./install.sh composio-auth login  # Print native Composio MCP OAuth steps for each client
./install.sh grepler      # Grepler MCP registration for Claude Code, Claude Desktop, Cursor, and Codex
./install.sh shell        # Bash as default + zsh compat + terminal colors
./install.sh hostname     # Sync macOS hostname settings
./install.sh backup       # Backup existing configs to /tmp/
```

Add `--verbose` to any command for full command output instead of the compact progress summary.

`./install.sh --help` (also `-h` or `help`) prints installer commands and **optional `DOTFILES_*` tuning variables** (minimal GUI installs, skip metadata syncs, AWS/Dashlane paths).

### Legacy macOS tuning (`DOTFILES_*`)

On Apple Silicon, `install.sh` restarts itself as arm64 when launched from Rosetta and uses native Homebrew at `/opt/homebrew`. On macOS **before 15**, **`packages`** prefers **MacPorts** so formulas are less likely to compile from Homebrew source. Highlights:

| Variable | Use |
| --- | --- |
| `DOTFILES_ALLOW_ROSETTA=1` | Skip the Apple Silicon arm64 re-exec guard for intentional x86/Rosetta testing. |
| `DOTFILES_MINIMAL_APPS=1` | **`apps`**: skip the Chrome default-browser wizard; still installs Drive, Chrome, Cursor, iTerm. |
| `DOTFILES_SKIP_MACPORTS_UPDATE=1` | Skip `port selfupdate`. |
| `DOTFILES_SKIP_BREW_UPDATE=1` | Skip `brew update` prefetch. |

Additional knobs (**dcli**, **AWS PKG**, **Impeccable skill**) match `./install.sh --help`. Full table: **CLAUDE.md** → *Legacy macOS and optional install tuning*.

### Platform Coverage

| Area | macOS | Linux |
| --- | --- | --- |
| Dotfiles | copied | copied |
| Packages | Homebrew/MacPorts | apt/dnf/yum + direct installers |
| GUI apps | Homebrew casks | skipped/manual |
| Cursor settings | `~/Library/Application Support/Cursor/User` | `~/.config/Cursor/User` |
| Claude Code settings | shared | shared |
| Codex plugins | shared | shared |
| MCP | shared | shared |
| iTerm/macOS defaults | installed | skipped |

## Repository Structure

```
mydot/
├── .bash/                      # Shell configuration
│   ├── config.bash             # User-specific settings (DOTFILES_* vars)
│   ├── prefs.bash              # PATH, env vars, aliases, pipx config
│   ├── prompt.bash             # PS1 with git branch, venv, error coloring
│   ├── functions.bash          # Backward-compat shim
│   └── functions/              # One file per dot-* function, auto-loaded
├── .vim/                       # Vim colorschemes + docs
├── .aws/                       # AWS CLI config (SSO-based)
├── .cursor/                    # Cursor IDE global config
├── .snowflake/                 # Snowflake CLI config template
├── .ssh/config/                # SSH host configuration
│
├── install.sh                  # Main dispatcher (sources install/*.bash)
├── install/
│   ├── _helpers.bash           # Progress display, package/pip helpers
│   ├── dotfiles.bash           # Copy dotfiles into ~/
│   ├── packages.bash           # CLI packages + direct installers
│   ├── apps.bash               # GUI apps via Homebrew cask
│   ├── vim.bash                # vim-plug download
│   ├── shell.bash              # Default shell + zsh compat + terminal colors
│   ├── cursor.bash             # Cursor settings + extensions
│   ├── claude.bash             # Claude Code settings + MCP cleanup
│   ├── codex.bash              # Codex plugin configuration
│   ├── ssh.bash                # SSH config install
│   └── hostname.bash           # macOS hostname sync
│
├── mcp/                        # MCP server configurations
│   ├── _helpers.bash           # Registration helpers for all 4 clients
│   ├── install.bash            # Enabled MCP server list + aggregate installer
│   ├── composio.bash           # Composio MCP installer for all clients
│   ├── grepler.bash            # Grepler MCP installer for all clients
│   └── README.md               # MCP server documentation
│
├── ide/
│   ├── cursor/                 # Cursor settings, keybindings, extensions, snippets
│   └── claude/                 # Claude Code settings.json
│
├── system/
│   ├── ssh/                    # Generic github.com SSH config
│   └── macos/                  # Terminal.app prefs, color scheme
│
├── apps/
│   ├── mounts/                 # External filesystem management (SSH + S3)
│   └── network/                # Network reporting utilities
│
├── .bashrc                     # Entry point: sources prefs → functions → prompt
├── .profile                    # Compatibility shim (sources .bashrc)
├── .zshrc                      # Zsh compat shim (sources bash config)
├── .vimrc                      # Vim config with vim-plug plugins
├── .screenrc                   # Screen: 256-color, truecolor, 30k scrollback, status bar
├── .gitconfig                  # Git config (name/email)
├── .gitignore_global           # Global gitignore
└── CLAUDE.md                   # Claude Code project instructions
```

## Bash Configuration

### Shell Startup Chain
`.bashrc` sources (in order): `prefs.bash` → `functions/_loader.bash` → `prompt.bash`

### Preferences (`.bash/prefs.bash`)
- PATH: Homebrew, `~/.local/bin`, pipx paths
- History: 10k entries, deduped, appended
- Aliases: `code`, `gstream`, `pp` (pull+push), `listen`, git shortcuts
- Platform-specific: macOS (`showfiles`/`hidefiles`, Cursor terminal workarounds), Linux (basic ls/ll)
- Sources `credentials.bash` if present

### Prompt (`.bash/prompt.bash`)
Multi-line prompt with:
- Git branch + dirty state (green check / red X)
- Python venv indicator
- Error-aware coloring (red `>` on failure, cyan on success)
- Screen window title updates via `PROMPT_COMMAND`

### Custom Functions (`.bash/functions/`)
All support `-h`/`--help`. Most use the `dot-` prefix; a few short, unambiguous tools (`awsso`, `dash`, `llmfix`, `bash-backup`) don't.

| Function | Purpose |
|----------|---------|
| `awsso` | Interactive picker for `aws sso login`; mirrors creds to `[default]` so tools that don't set `AWS_PROFILE` just work |
| `dot-aws-switch` | Pick / set `AWS_PROFILE` (and `AWS_REGION`) for the current shell |
| `dot-branch-name` | Generate branch names: `{prefix}/{MMDD}/{feature}` |
| `dot-commit-llm` | AI-generated commit messages (OpenAI/Anthropic) |
| `dot-hosts` | Host registry: ping, lookup, sync to `/etc/hosts` |
| `dot-kill` | Kill processes by name |
| `dot-gitclean` | Delete merged branches + prune remotes |
| `dot-fly-switch` | Switch Fly.io CLI context (work/personal) |
| `dot-cursor-backup` | Export Cursor settings and commit to repo |
| `bash-backup` | Back up `~/.bash` to repo and push |
| `dot-flushcache` | Flush DNS cache (macOS) |
| `dot-mac-spoof` | Spoof MAC address (macOS) |
| `llmfix` | Fix last failed command using ChatGPT |

Modules can be selectively disabled via `DOTFILES_SKIP_MODULES` in `config.bash`.

### Personalization (`.bash/config.bash`)

| Variable | Purpose |
|----------|---------|
| `DOTFILES_GIT_NAME` | Git author name |
| `DOTFILES_GIT_EMAIL` | Git author email |
| `DOTFILES_BRANCH_PREFIX` | Prefix for `dot-branch-name` |
| `DOTFILES_DIR` | Path to this repo |
| `DOTFILES_HOSTS_API_URL` | Host registry API URL |
| `DOTFILES_PIPX_PYTHON` | Python interpreter for pipx |
| `DOTFILES_SKIP_MODULES` | Space-separated function modules to skip |

## MCP Servers

MCP (Model Context Protocol) servers extend local AI clients with external data sources. Registration helpers exist for Claude Code, Claude Desktop, Cursor, and Codex:

| Client | Config File | URL Support |
|--------|-------------|-------------|
| Claude Code | `~/.claude.json` | `type: "http"` |
| Claude Desktop | `~/Library/.../claude_desktop_config.json` | optional `npx mcp-remote` proxy |
| Cursor | `~/.cursor/mcp.json` | `url` |
| Codex | `~/.codex/config.toml` | native remote HTTP OAuth |

`./install.sh claude` installs Claude Code settings and cleans stale MCP entries. `./install.sh codex` enables the Codex plugins managed by this repo without replacing unrelated local Codex config.

Active MCPs (Composio, Grepler) are enabled through the aggregate MCP installer:

```bash
./install.sh mcp
```

The Grepler installer writes `~/.local/bin/grepler-mcp` and registers that wrapper in Claude Code, Claude Desktop, Cursor, and Codex. The wrapper sources `GREPLER_TOKEN` from `~/.bash/credentials.bash` or `~/.grepler/credentials.env` at runtime, so generated MCP configs do not contain token literals. Composio uses native remote HTTP OAuth in Claude Code, Cursor, and Codex, with an optional Claude Desktop `mcp-remote` fallback when `npx` is available. After install, approve it in each client (`codex mcp login composio`, Claude Code `/mcp` -> reconnect, Cursor MCP settings), then connect app-specific connectors in the Composio dashboard. See `mcp/composio-auth.md`. Start a new Codex session and restart Cursor/Claude apps after changing MCP registrations.

See [mcp/README.md](mcp/README.md) for full MCP documentation.

## IDE Configuration

### Cursor (`ide/cursor/`)
- Bash as default terminal with login shell
- Vim mode with system clipboard
- Settings, keybindings, snippets, extensions list
- App install: `./install.sh apps`
- Settings install: `./install.sh cursor`
- Backup: `dot-cursor-backup` (exports and commits to repo)

### Claude Code (`ide/claude/`)
- `settings.json` merged non-destructively during install
- `autoUpdatesChannel` is managed as `latest`
- `packages` installs the managed npm CLI as `@anthropic-ai/claude-code@latest` under `~/.local` and removes duplicate Homebrew-prefix npm copies
- `install/claude.bash` cleans stale MCP entries
- Install: `./install.sh claude`

### Vim (`.vimrc`)
- vim-plug plugins: NERDTree, ALE, Solarized, airline, gitgutter
- Solarized dark colorscheme
- Smart search (incremental, highlighted, case-insensitive with smart case)
- 4-space tabs, smart indent

## System Configuration

### Screen (`.screenrc`)
- 256-color + truecolor (24-bit RGB) passthrough
- 30k line scrollback with mouse scrolling
- Dynamic status bar: `user@host | windows | git-branch cwd`
- Toggle: Ctrl-a f (hide) / Ctrl-a F (show)

### Terminal.app (`system/macos/`)
- Homebrew color scheme
- Terminal preferences backup
- Color configuration script (runs during `./install.sh shell`)

## Backup & Recovery

The installer creates backups before overwriting:
- Location: `/tmp/dotfiles_backup_<timestamp>/`
- Contents: `.bash*`, `.vim*`, `.aws*`, `.bashrc`, `.gitconfig`, `.profile`, `.screenrc`, `.vimrc`

Restore: `cp -r /tmp/dotfiles_backup_<timestamp>/* ~/`

Two auto-commit backup functions:
- `bash-backup` — backs up `~/.bash` to this repo
- `dot-cursor-backup` — exports Cursor settings to this repo

## Packages

Installed via `./install.sh packages`:

**macOS Homebrew/MacPorts**: python3, node, jq, uv, shellcheck, flake8, cmatrix, virtualenv, pipx, gh, flyctl, screen, tmux, reattach-to-user-namespace, awscli. Apple Silicon uses native `/opt/homebrew`; Intel `/usr/local` Homebrew is left as a compatibility path only.

**Linux apt/dnf/yum**: python3, nodejs/npm, jq, shellcheck, flake8, cmatrix, virtualenv, pipx, gh, screen, tmux, awscli

**Homebrew casks on macOS**: GUI apps from `./install.sh apps` (Google Drive, Chrome, Cursor, iTerm, Granola, Wispr Flow, Superhuman, Slack, Tailscale)

**pipx**: pip-search, autopep8

**npm/direct**: codex, Claude Code (`@anthropic-ai/claude-code@latest` in `~/.local`), cursor-agent, composio, impeccable CLI, Impeccable global agent skill

Agent CLIs are audited with `./install.sh agents-doctor`. Codex and Claude Code
are managed under `~/.local` with explicit npm `@latest` installs; Cursor Agent
is refreshed by rerunning Cursor's official installer when `packages` runs.

**Linux direct installers**: uv, flyctl, cursor-agent, composio. Codex and Claude Code use the same managed npm path as macOS.

## AWS

The repo ships no AWS config — bring your own `~/.aws/config`. Two helpers work
against whatever profiles you define there:

- `awsso` — interactive picker for `aws sso login` (reads your `[sso-session ...]` blocks)
- `dot-aws-switch` — set the active `AWS_PROFILE` for the current shell

## Troubleshooting

| Issue | Solution |
|-------|----------|
| pipx Python interpreter error | Set `DOTFILES_PIPX_PYTHON` in `config.bash` |
| Cursor terminal not using bash | Run `./install.sh cursor`, restart Cursor |
| Environment variables not loaded | Check `.bashrc` is sourced, check file permissions |
| MCP server not found in Desktop | Individual MCP installers are currently disabled; check `mcp/README.md` before re-enabling |
