# MCP Server Configurations

MCP (Model Context Protocol) servers extend local AI clients with external data sources.
This directory contains MCP helper code and historical server notes for this dotfiles repo.

`./install.sh claude` installs Claude Code settings and runs MCP cleanup.

Composio, Grepler, and Playwright are enabled. Install every enabled MCP server with:

```bash
./install.sh mcp
```

MCP credentials are read from `~/.bash/credentials.bash` (gitignored; fill it in
yourself) when a server needs local credential injection. Composio uses
client-managed OAuth. Grepler reads `GREPLER_TOKEN` through its wrapper.

The Grepler installer writes `~/.local/bin/grepler-mcp` and registers the wrapper in Claude Code, Claude Desktop, Cursor, and Codex. The wrapper sources `GREPLER_TOKEN` from `~/.bash/credentials.bash` or `~/.grepler/credentials.env` at runtime, so generated MCP configs do not contain token literals. Composio registers `https://connect.composio.dev/mcp` as a native remote HTTP OAuth MCP in Claude Code, Cursor, and Codex. Claude Desktop gets an optional legacy `mcp-remote` proxy only when `npx` is available. Start a new Codex session and restart Cursor/Claude apps after MCP changes.

**Credentials:** Grepler requires `GREPLER_TOKEN` in `~/.bash/credentials.bash` (gitignored — set it yourself). Composio OAuth is handled by each MCP client.

- **Claude Code**: supports `url` for streamable HTTP/SSE servers.
- **Claude Desktop**: uses **mcp-remote** proxy (`npx mcp-remote <url>`) for remote servers when needed; manages extensions natively.
- **Cursor**: supports `url`; no proxy needed.
- **Codex**: uses `codex mcp add` for stdio and streamable HTTP servers.

## Current Install Flow

```bash
./install.sh claude
```

This merges Claude Code settings and removes stale MCP entries.

```bash
./install.sh mcp
```

This installs all enabled MCP servers listed in `DOTFILES_MCP_SERVERS` in `mcp/install.bash`. Retired servers are swept from client configs by `_cleanup_stale_mcp_servers`; your own unmanaged MCP servers are left untouched.

```bash
./install.sh composio
```

This registers Composio in Claude Code, Cursor, and Codex. It also adds a
best-effort Claude Desktop legacy proxy when `npx` is installed.

```bash
codex mcp login composio
```

Complete Composio MCP OAuth for Codex. Claude Code and Cursor have their own MCP approval flows, and app-specific connectors are approved in the Composio dashboard. `dot-composio-auth login` prints the native client steps. See [`composio-auth.md`](composio-auth.md).

```bash
./install.sh grepler
```

This registers Grepler in Claude Code, Claude Desktop, Cursor, and Codex.

```bash
./install.sh playwright
```

This registers Playwright MCP (`--extension` mode) in Claude Code, Claude Desktop,
Cursor, and Codex. Requires the [Playwright MCP Bridge](https://chromewebstore.google.com/detail/playwright-mcp-bridge/mmlmfjhmonkocbjadbfplnigmagldckm) Chrome extension (see `ide/chrome/README.md`).

## Active MCP Servers

### Composio
- **Purpose**: Aggregated remote MCP access to Composio's connectors
- **Type**: Remote HTTP OAuth MCP
- **URL**: `https://connect.composio.dev/mcp`
- **Config**: Registered as `composio` in Claude Code, Cursor, and Codex; Claude Desktop legacy proxy is best effort
- **Auth**: Client-managed OAuth. Codex uses `codex mcp login composio`; Claude Code uses `/mcp` -> reconnect; Cursor uses MCP settings. Connect individual apps in the Composio dashboard. See [`composio-auth.md`](composio-auth.md).

### Grepler
- **Purpose**: Remote Grepler MCP server for Gmail, Calendar, Sheets, Slack, Notion, LinkedIn, context tools, and operator tools — also subsumes several retired integrations
- **Type**: Stdio wrapper around `npx mcp-remote`
- **URL**: `https://grepler.dev/mcp/` by default; override with `GREPLER_URL`
- **Config**: Registered as `grepler` in Claude Code, Claude Desktop, Cursor, and Codex
- **Auth**: Bearer token from `~/.bash/credentials.bash` or `~/.grepler/credentials.env` (`GREPLER_TOKEN`)

### Playwright
- **Purpose**: Browser automation via your open Chrome tabs (logged-in sessions, cookies)
- **Type**: Stdio wrapper around pinned `npx @playwright/mcp@<version> --extension` (see `PLAYWRIGHT_MCP_VERSION` in `mcp/playwright.bash`)
- **Chrome extension**: [Playwright MCP Bridge](https://chromewebstore.google.com/detail/playwright-mcp-bridge/mmlmfjhmonkocbjadbfplnigmagldckm) (`mmlmfjhmonkocbjadbfplnigmagldckm`) — not Playwright CRX (recorder)
- **Config**: Registered as `playwright` in Claude Code, Claude Desktop, Cursor, and Codex via `~/.local/bin/playwright-mcp`
- **Auth**: Optional `PLAYWRIGHT_MCP_EXTENSION_TOKEN` in `~/.bash/credentials.bash` (from extension UI) to skip tab-approval prompts

## Claude Code browser stack (beyond `./install.sh mcp`)

 `./install.sh claude` also enables the other two Claude Code browser tools (see `ide/chrome/README.md`):

| Tool | Install path | MCP name in `/mcp` |
|------|--------------|-------------------|
| Playwright MCP | `./install.sh mcp` | `playwright` (user MCP) |
| Claude in Chrome | `./install.sh claude` + `claude` wrapper (`--chrome` default) | `claude-in-chrome` when connected |
| chrome-devtools | `./install.sh claude` (`chrome-devtools-mcp@claude-plugins-official`) | `chrome-devtools` (plugin MCP) |

Skip default `--chrome` with `claude --no-chrome` or **`DOTFILES_CLAUDE_SKIP_CHROME=1`**.

## Retired MCP Servers

Listed in `_cleanup_stale_mcp_servers` (`mcp/_helpers.bash`) so subsequent installs sweep them out of every client config:
- `lifelog`, `glowscape` — functionality available through Grepler
- `airtable`, `dovetail`, `snowflake`, `limitless`, `metabase`, `deco`, `alexa`, `reclaim`

### Syncing extensions into Claude Code (`dot-claude-sync`)

Use the `dot-claude-sync` shell function (in `.bash/functions/`) to mirror **all** enabled Claude Desktop extensions into `~/.claude.json` in one shot, without touching individual MCP install scripts. It reads each extension's `manifest.json` + matching `Claude Extensions Settings/<id>.json`, resolves `${__dirname}` to absolute paths, inlines non-sensitive `user_config` values, and emits sensitive values as `${ENV_VAR}` refs (uppercase of the user_config key — Claude Code expands these from the shell at launch, so set them in `~/.bash/credentials.bash`). Each entry gets `_source: "claude-extension:<id>"`, which lets a re-run sweep extensions you've since uninstalled or disabled in Desktop.

```bash
dot-claude-sync --dry-run   # preview
dot-claude-sync             # write
```

Re-run after installing, updating, or disabling a Desktop extension. macOS only.

## Team Setup

1. Clone this repo:
   ```bash
   git clone https://github.com/thechrisfischer/mydot.git ~/Code/mydot
   ```

2. Install dotfiles:
   ```bash
   cd ~/Code/mydot && ./install.sh dotfiles
   ```

3. Install Claude settings:
   ```bash
   ./install.sh claude
   ```

4. Restart Claude Code.

## Remote URL–based MCP

- **Claude Code** (`~/.claude.json`): supports a `url` field for streamable HTTP/SSE servers.
- **Claude Desktop** (`claude_desktop_config.json`): does **not** support a raw `url` key. Use **mcp-remote** proxy: `npx mcp-remote <url>` when a Desktop fallback is needed. Requires Node.js.
- **Cursor** (`~/.cursor/mcp.json`): supports `url`; no proxy needed.

## Configuration locations

| Client          | Config file |
|-----------------|-------------|
| Claude Code     | `~/.claude.json` |
| Claude Desktop  | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Cursor          | `~/.cursor/mcp.json` |
| Codex           | `~/.codex/config.toml` |

## Adding a New MCP Server

1. Add `mcp/<name>.bash`.
2. Define `install_<name>` inside that file.
3. Source `mcp/_helpers.bash` inside the installer.
4. Use the existing helper that matches the server shape:
   - `_register_codex_mcp_server` for stdio servers.
   - `_register_codex_url_mcp_server` for remote HTTP servers.
   - `_register_cursor_mcp_server` for Cursor stdio servers.
   - `_register_cursor_url_mcp_server` for Cursor remote HTTP servers.
5. Add `<name>` to `DOTFILES_MCP_SERVERS` in `mcp/install.bash`.
6. Add an individual `<name>)` target in `install.sh` only if focused re-runs are useful.
7. Run `./install.sh --verbose mcp`.
8. Verify with `codex mcp list`.

Credential rule: generated config should reference env var names or wrapper scripts, not token literals. Prefer wrappers for GUI clients that may not inherit shell environment.

### Adding a Credential

1. Add the variable (e.g. `export GREPLER_TOKEN=...`) to `~/.bash/credentials.bash` (gitignored).
2. Open a new shell so it is sourced.
3. Re-run the installer that consumes the variable.
