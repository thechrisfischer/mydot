# Chrome extensions (manual + Google Sync)

Chrome extensions are **not** installed by dotfiles. With Google Sync enabled
(Settings → Sync → **Extensions**), installs on one signed-in profile propagate
to your other machines automatically.

Per-extension **logins** (claude.ai, OpenAI, etc.) are still per-machine.

## Claude Code browser stack

Dotfiles wires all three Claude Code browser integrations:

| Tool | Dotfiles install | Chrome extension | Notes |
|------|------------------|------------------|-------|
| **Playwright MCP** | `./install.sh mcp` (`playwright`) | [Playwright MCP Bridge](https://chromewebstore.google.com/detail/playwright-mcp-bridge/mmlmfjhmonkocbjadbfplnigmagldckm) | User MCP; drives open tabs via `--extension` |
| **Claude in Chrome** | `./install.sh claude` + `claude` wrapper (`--chrome` default) | [Claude in Chrome](https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn) | `claude-in-chrome` MCP when connected; requires direct Anthropic plan |
| **chrome-devtools** | `./install.sh claude` (`chrome-devtools-mcp` plugin) | none | Built-in plugin MCP; DevTools Protocol |

Skip default `--chrome` with `claude --no-chrome` or **`DOTFILES_CLAUDE_SKIP_CHROME=1`**.

## Standard extension set

Install once on a synced Chrome profile:

| Extension | ID | Purpose |
|-----------|-----|---------|
| [Claude in Chrome](https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn) | `fcoeoabgfenejglbffodgkkbkcdhcgfn` | Claude Code `/chrome`, authenticated browser automation |
| [Codex](https://chromewebstore.google.com/detail/codex/hehggadaopoacecdllhhajmbjkdcmajg) | `hehggadaopoacecdllhhajmbjkdcmajg` | Codex app → Chrome plugin |
| [Playwright MCP Bridge](https://chromewebstore.google.com/detail/playwright-mcp-bridge/mmlmfjhmonkocbjadbfplnigmagldckm) | `mmlmfjhmonkocbjadbfplnigmagldckm` | **Official** — AI/MCP drives your open tabs (`--extension`) |

### Not the same as Playwright CRX

[Playwright CRX](https://chromewebstore.google.com/detail/playwright-crx/jambeljnbnfbkcpnoiaedcabbgmnnlcd) (`jambeljnbnfbkcpnoiaedcabbgmnnlcd`) is a **third-party recorder** (ruifigueira / [playwright-crx](https://github.com/ruifigueira/playwright-crx)): record & replay scripts in the browser. It does **not** connect to Playwright MCP or Cursor agents.

Use **MCP Bridge** for agent browser control; add **Playwright CRX** only if you want in-browser test recording.

## Playwright MCP (extension + server)

The MCP Bridge extension pairs with the dotfiles `playwright` MCP server
(`~/.local/bin/playwright-mcp` → `npx @playwright/mcp --extension`), registered
in Claude Code, Cursor, Codex, and Claude Desktop by `./install.sh mcp`.

## Verify sync

```text
chrome://extensions          — extensions enabled
chrome://sync-internals      — extension sync active
```

## Troubleshooting Claude in Chrome

If Claude Code cannot connect to the extension:

1. Confirm the extension is enabled in `chrome://extensions`.
2. Run `/chrome` → **Reconnect extension** (or restart Chrome after first setup).
3. If Claude Desktop is also installed, its native messaging host can steal the extension — see [Anthropic docs](https://code.claude.com/docs/en/chrome#extension-not-detected).
