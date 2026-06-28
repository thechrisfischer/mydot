# Fresh Mac bootstrap

How to go from a **brand-new Mac** (no Xcode, Homebrew, or git) to a working
dotfiles install.

## Recommended: one-line bootstrap (HTTPS first)

On a fresh Mac, in Terminal (replace `<your-username>` with your GitHub fork):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/<your-username>/dotfiles/main/scripts/bootstrap-macos.sh)"
```

This script:

1. Installs **Xcode Command Line Tools** (macOS GUI prompt)
2. Installs **Homebrew** (sudo password)
3. Installs **gh**, git, curl, jq
4. Runs **`gh auth login -h github.com -p https -w`** (browser — no SSH key needed)
5. **`gh repo clone`** dotfiles to `~/Code/dotfiles`
6. Runs **`./install.sh ssh`** (installs the SSH config)
7. Runs **`./install.sh all`**

### Optional environment variables

```bash
# Override which repo to clone (defaults to the repo the script came from)
DOTFILES_GITHUB='<your-username>/dotfiles' \
  /bin/bash -c "$(curl -fsSL ...)"

# Clone only — run install yourself
DOTFILES_SKIP_INSTALL_ALL=1 \
  /bin/bash -c "$(curl -fsSL ...)"

# Headless / CI (instead of browser login)
GITHUB_TOKEN='ghp_...' \
  /bin/bash -c "$(curl -fsSL ...)"
```

## Manual path (if you already have Homebrew + gh)

```bash
gh auth login -h github.com -p https -w
gh auth setup-git
mkdir -p ~/Code
gh repo clone <your-username>/dotfiles ~/Code/dotfiles
cd ~/Code/dotfiles
./install.sh ssh
./install.sh all
```

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
