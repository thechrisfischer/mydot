# Fresh Mac bootstrap

How to go from a **brand-new Mac** (no Xcode, Homebrew, or git) to a working
dotfiles install.

## Recommended: one-line bootstrap (HTTPS first)

On a fresh Mac, in Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap-macos.sh)"
```

This script:

1. Installs **Xcode Command Line Tools** (macOS GUI prompt)
2. Installs **Homebrew** (sudo password)
3. Installs **gh**, git, curl, jq
4. **`git clone`** `https://github.com/thechrisfischer/mydot` to `~/Code/mydot` (no GitHub login required)
5. Runs **`./install.sh ssh`** (installs the SSH config)
6. Runs **`./install.sh all`**

> **Note:** `gh auth login` is only needed as a fallback when cloning a private or forked repo.

### Optional environment variables

```bash
# Forked it? Pass your fork's repo and use your fork's raw URL.
# (Changing the URL alone clones upstream, not your fork.)
DOTFILES_GITHUB='<you>/mydot' \
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/<you>/mydot/main/scripts/bootstrap-macos.sh)"

# Clone only — run install yourself
DOTFILES_SKIP_INSTALL_ALL=1 \
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap-macos.sh)"

# Headless / CI (instead of browser login)
GITHUB_TOKEN='ghp_...' \
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/thechrisfischer/mydot/main/scripts/bootstrap-macos.sh)"
```

## Manual path (if you already have Homebrew + gh)

```bash
mkdir -p ~/Code
git clone https://github.com/thechrisfischer/mydot ~/Code/mydot
cd ~/Code/mydot
./install.sh ssh
./install.sh all
```

> **Note:** If cloning a private or forked repo, run `gh auth login -h github.com -p https -w` and `gh auth setup-git` before the `git clone` step.

## SSH keys (bring your own)

The repo ships only a generic `github.com` block in `system/ssh/config`
(installed to `~/.ssh/config.d/dotfiles` by `./install.sh ssh`). It does not
sync or generate any private key. Create your own and add it to GitHub:

```bash
ssh-keygen -t ed25519 -C "you@example.com"
# then add ~/.ssh/id_ed25519.pub to GitHub for git@ remotes
```

Keep machine- or host-specific SSH config in a private `~/.ssh/config.d/*.local`
file (not committed to the repo).

## Credentials (bring your own)

Secrets live in `~/.bash/credentials.bash` (gitignored). There is no secret-sync
backend — fill it in yourself with plain `export` lines for whatever the tooling
needs, e.g.:

```bash
export GREPLER_TOKEN="..."
export ANTHROPIC_API_KEY="..."
```

`prefs.bash` sources the file if present.

## After bootstrap

1. Install Chrome extensions (sync): see `ide/chrome/README.md`
2. Re-run failed sections: `./install.sh all` prints re-run commands at the end

## Source of truth

- SSH config template: `system/ssh/config`
- This doc: `docs/fresh-mac-bootstrap.md`
- Bootstrap script: `scripts/bootstrap-macos.sh`
