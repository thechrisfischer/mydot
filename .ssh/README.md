# SSH in dotfiles

A generic `github.com` SSH config lives in **`system/ssh/config`** (installed to
`~/.ssh/config.d/dotfiles` by `./install.sh ssh`). Add your own hosts in a
private `~/.ssh/config.d/*.local` file.

Bring your own SSH key: generate one with `ssh-keygen` and add it to GitHub for
`git@` remotes. The repo does not ship or sync any private key.
