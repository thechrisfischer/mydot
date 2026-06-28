# Cursor Configuration

Cursor IDE settings, keybindings, snippets, and extensions live here.

## Installation

```bash
cd ~/Code/dotfiles
./install.sh cursor   # merge settings + sync extensions from extensions.txt
./install.sh apps     # Cursor.app via Homebrew cask (macOS)
```

`./install.sh cursor` will:

- Merge `settings.json` with your local Cursor settings (dotfiles keys win on conflict)
- Copy `keybindings.json` and snippets when present
- Install extensions listed in `extensions.txt`
- Remove extensions **not** in `extensions.txt` (prune) unless `DOTFILES_CURSOR_SKIP_EXTENSION_PRUNE=1`
- Link `~/.local/bin/cursor` to the Cursor.app CLI when the app is installed (and remove a duplicate Homebrew `cursor` shim if present)

Install/backup scripts resolve the IDE CLI via `_cursor_ide_bin_path` (`~/.local/bin/cursor` → app bundle), not whatever Homebrew puts on PATH. **`cursor-agent`** is separate (official agent installer in `packages`).

Back up local changes into git with `dot-cursor-backup`.

Chrome extensions (Claude in Chrome, Codex, Playwright MCP Bridge) are **not**
managed here — they sync via Google Chrome when signed in. See `ide/chrome/README.md`.

## After Installation

1. Restart Cursor completely
2. Open a new terminal and verify bash: `echo $SHELL` → `/bin/bash`

## Troubleshooting

### Terminal still shows zsh
Restart Cursor and confirm `settings.json` was merged under `~/Library/Application Support/Cursor/User/`.

### Extensions not syncing
Ensure the IDE CLI resolves to Cursor.app: `type -P cursor` should print `~/.local/bin/cursor` (symlink to `Cursor.app/.../bin/code`) after `./install.sh cursor` on macOS. Re-run `./install.sh apps` or `./install.sh cursor` if `/opt/homebrew/bin/cursor` reappears.
