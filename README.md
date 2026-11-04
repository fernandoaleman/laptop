# Laptop

[![Test Status](https://github.com/fernandoaleman/laptop/actions/workflows/ci.yaml/badge.svg)](https://github.com/fernandoaleman/laptop/actions/workflows/ci.yaml)

Laptop is a script to set up a macOS laptop for web development.

It can be run multiple times safely on the same machine. It installs and
upgrades packages based on what is already installed.

## Requirements

- macOS Sequoia (15.x) on Apple Silicon and Intel

## Install laptop

Download the script:

```sh
curl --remote-name https://raw.githubusercontent.com/fernandoaleman/laptop/master/laptop
```

Run the script:

```sh
bash laptop 2>&1 | tee ~/laptop.log
```

Optionally, review the log:

```sh
less ~/laptop.log
```

## Debugging

Your last laptop run will be saved to `~/laptop.log`. Read through it and see if
you can find the issue. If not, open a [new GitHub
Issue](https://github.com/fernandoaleman/laptop/issues/new) and attach the log file
as an attachment.

## What This Script Sets Up

macOS tools:

- [Homebrew] for managing operating system libraries.

[Homebrew]: http://brew.sh/

Unix tools:

- [Bat] a fancy `cat` clone
- [Git] for version control
- [OpenSSL] for Transport Layer Security (TLS)
- [RCM] for managing company and personal dotfiles
- [Tmux] for saving project state and switching between projects
- [Zsh] as your shell

[Bat]: https://github.com/sharkdp/bat
[Git]: https://git-scm.com/
[OpenSSL]: https://www.openssl.org/
[RCM]: https://github.com/thoughtbot/rcm
[Tmux]: https://tmux.github.io/
[Zsh]: https://www.zsh.org/

GitHub tools:

- [GitHub CLI] for interacting with the GitHub API

[GitHub CLI]: https://cli.github.com/

## Customizations

You can add your own customizations by adding them to your `~/.laptop.local`
file, which is run at the end of the laptop script.

Put your customizations there.
For example:

```sh
#!/bin/sh

brew bundle --file=- <<EOF
brew "go"
EOF

fancy_echo "Cleaning up old Homebrew packages ..."
brew cleanup
```

Make sure your customizations can be run safely more than once.
See the `laptop` script for examples.

## Testing

The V2 bootstrap checkpoint can be checked without installing anything with
`/bin/bash install.sh --check-platform`. `/bin/bash install.sh --gum-only`
performs only platform validation and the verified Gum installation; it does
not yet install Homebrew or the rest of the machine. Live installation requires
explicit approval. Run the isolated fixture tests with `make test`.

For development, run `make setup` to check the required tools and install
missing Homebrew formulae and prek Git hooks. Existing non-prek hooks are
preserved and must be resolved before setup can install hooks. Prek supplies
the pinned committed executable in its managed hook environment.

Run the static checks with ShellCheck, shfmt, typos, and actionlint installed:

```sh
make check
```

This checks Bash syntax, shell lint, formatting, spelling, and workflow semantics
without running the installer. CI runs these checks on Linux; it does not test
macOS behavior.
The commit-message hook enforces Conventional Commits, such as
`feat: add development tooling`.

To check a local customization script separately:

```sh
shellcheck ~/.laptop.local
```
