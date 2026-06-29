# Composio MCP auth

Composio Connect is a remote HTTP MCP server:

```text
https://connect.composio.dev/mcp
```

The current setup is OAuth-first. Do not register Composio through the old
`mcp-remote` wrapper with `COMPOSIO_API_KEY`; that path can fail with
`401` after authentication.

## Install

```bash
cd ~/Code/mydot
./install.sh composio
```

This registers Composio as remote HTTP in the native clients first:

| Client | Config |
|--------|--------|
| Claude Code | `~/.claude.json` -> `mcpServers.composio.url` |
| Cursor | `~/.cursor/mcp.json` -> `mcpServers.composio.url` |
| Codex | `~/.codex/config.toml` -> `[mcp_servers.composio] url = ...` |
| Claude Desktop | Optional legacy `mcp-remote` URL proxy when `npx` is installed |

`~/.local/bin/composio-mcp` is still installed as a legacy wrapper for hosts
that need `mcp-remote`, but the default clients should use native remote HTTP
where they support it.

## Login

Each MCP client owns its own OAuth token store, so approve Composio in the
client you are using.

```bash
dot-composio-auth login
```

This prints the native client login steps without touching legacy wrapper auth.

| Client | Login |
|--------|-------|
| Codex CLI | `codex mcp login composio` |
| Claude Code | `/mcp` -> `composio` -> `Reconnect` |
| Cursor | Restart Cursor, then connect/approve Composio in MCP settings |
| Claude Desktop | Use the connector UI when available, or let the legacy wrapper open browser OAuth |

After MCP OAuth, connect the specific apps you want to use in the Composio
dashboard. MCP OAuth authenticates the MCP server; app actions still depend on
their own Composio app connections.

After login, start a new agent/session if tools do not appear immediately.

## Verify

```bash
codex mcp list
dot-composio-auth status
```

Expected Codex registration:

```text
composio  https://connect.composio.dev/mcp
```

In Claude Code, `/mcp` should show Composio connected with the Composio meta
tools, including `COMPOSIO_SEARCH_TOOLS` and `COMPOSIO_MULTI_EXECUTE_TOOL`.

In Cursor, MCP settings should show Composio connected/approved. Start a new
Cursor agent after approval if tools do not appear in the current session.

## Clearing Stale Auth

If an old wrapper registration is still loaded, reinstall and restart the
client:

```bash
./install.sh composio
```

For native client reset instructions:

```bash
dot-composio-auth reset
```

That prints the client-owned logout/reconnect steps. For Codex native OAuth,
the underlying commands are:

```bash
codex mcp logout composio
codex mcp login composio
```

For Claude Code, use `/mcp` -> `composio` -> `Reconnect`.

If legacy `mcp-remote` state is stuck:

```bash
dot-composio-auth legacy-reset
```

`legacy-reset` removes only the token prefix that proves it is a working
legacy Composio session. It does not clear unrelated `mcp-remote` auth files.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `/mcp` shows command `/bin/bash ~/.local/bin/composio-mcp` | Run `./install.sh composio`, then start a new Claude Code session |
| Codex lists Composio but tools are missing | Run `codex mcp login composio`, then start a new Codex session |
| Cursor shows 0 tools or needs approval | Restart Cursor and approve/connect Composio in MCP settings |
| `dot-composio-auth status` reports missing native registration | Run `./install.sh composio`, then restart the affected client |
| App-specific action fails | Reconnect that app in the Composio dashboard |
| Multiple Composio OAuth tabs pop unexpectedly on a host running OpenClaw/Hermes | Each per-user MCP wrapper (`composio-mcp-<user>`, `composio-mcp-agent <user>`) opens a browser when no Bearer is cached. The atlas `composio-mcp-agent` wrapper in [openclaw/atlas](../../openclaw/atlas/bin/composio-mcp-agent) gates on `tokens.json` presence to suppress this; ensure it is installed via `bash ~/Code/openclaw/atlas/scripts/apply-config.sh`. Per-user Bearers are populated via the Slack "connect my composio" flow, not by interactive OAuth on the host. |
| `EADDRINUSE 127.0.0.1:48925` when starting `mcp-remote` against `connect.composio.dev/mcp` | Another `mcp-remote` against the same URL already holds the deterministic callback port. mcp-remote only binds it for interactive OAuth, so this only happens during fresh DCR; rare in steady state. Kill the older `mcp-remote` (`pgrep -af mcp-remote.*composio`), or wait for it to exit. |
