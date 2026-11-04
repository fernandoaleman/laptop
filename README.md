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

The bootstrap installs Gum at `~/.local/bin/gum` and invokes it by absolute
path. A matching verified binary is reused offline. Adding `~/.local/bin` to
PATH is deferred to the future dotfiles setup.

The modular payload is a development checkpoint, not a released installer.
`tools/build-payload.py` builds a gzip-compressed ustar archive from an explicit
file list, excluding `install.sh`. It normalizes archive metadata and uses the
development version in `payload-version`. Build with Python 3 and its standard
library; byte-for-byte release builds require a pinned Python/zlib environment.
For a local development archive, run
`python3 tools/build-payload.py /tmp/laptop-payload-0.0.0-dev.tar.gz`; the
builder refuses to overwrite an existing output.
Run `python3 tests/payload.py` for isolated packaging, integrity, archive-safety,
and runner tests. The payload runner supports `--check` and `--apply`; its
current components are harmless examples and require an absolute payload root
and Gum path. The tests inject a fixture URL and its real digest into a temporary
bootstrap copy; this does not bypass verification in the release bootstrap.
With verified Gum already installed at `~/.local/bin/gum`, check the harmless
components directly from a trusted development checkout with
`PAYLOAD_ROOT="$PWD" GUM_BIN="$HOME/.local/bin/gum" /bin/bash install/run.sh --check`.
This direct invocation trusts the local checkout; it is not release verification.

The bootstrap's payload mode remains unavailable until a real versioned payload
is published and its URL and verified SHA-256 are reviewed into the matching
bootstrap. A reviewed, version-pinned bootstrap digest must be distributed via
a trusted channel before a production command is offered; a checksum downloaded
beside an archive is not an independent trust source. No Homebrew or full
provisioning is implemented. Failed runs clean owned temporary directories;
after a hard kill or power loss, an owned temporary directory may remain.
Once enabled, `--payload` installs or verifies Gum before checking the payload.

Release-candidate tooling is experimental and does not publish or enable the
installer. A candidate source must contain its exact `vMAJOR.MINOR.PATCH-rc.N`
in `payload-version`; the builder accepts `--version VERSION` and requires an
output named `laptop-payload-VERSION.tar.gz`. `tools/prepare-bootstrap.py` binds
an independently reviewed payload digest into a candidate copy outside the
repository. Its printed bootstrap digest still requires independent review.
`tools/verify-release.py` requires a full source commit and separately reviewed
payload, bootstrap, and verifier SHA-256 digests. Before running it, obtain the
reviewed source commit and verifier digest from an authenticated independent
review channel, and compare the verifier file with that digest using a trusted
external SHA-256 utility. For local checkpoints, the operator can receive the
reviewed digest directly from the user in the authenticated project conversation
and independently compare it before execution:

```sh
printf '%s  %s\n' "$REVIEWED_VERIFIER_SHA256" tools/verify-release.py | shasum -a 256 -c
```

This trusts that conversation and the external checksum utility; a digest read
only from the same checkout is not an independent review. Do not trust a verifier to authenticate itself or
treat a Git commit identifier alone as proof of review. The verifier additionally
requires its running bytes to match both the supplied digest and the verifier
blob in that exact source commit. It rebuilds source blobs in two temporary
directories, checks payload contents and metadata, reconstructs the candidate,
and prints a JSON report. It requires `--local-only` and never approves a
release. Builds in one environment do not prove independent
cross-environment reproducibility. The source commit and build tools must be
reviewed before running them; the verifier executes the committed builder.
Run the verifier and committed builder in a disposable environment without
network access, secrets, or publishing credentials; a trusted commit check does
not sandbox code. Use a trusted Git executable and controlled PATH; Git
environment sanitization does not authenticate executables on PATH.
The proposed Linux AMD64 build image is `python:3.12.16-bookworm` pinned to
`sha256:034c3e9d991f148d14c32ff8350286b91420baca7757d37819c7a9cc771317a0`.
Its runtime Python and zlib versions must be verified before release use.

Before any release, pin and verify the Linux build image and Python/zlib, rebuild
from the final approved commit independently, and compare the reviewed digests.
Separately approve release settings, tag creation, and publication. Require
immutable releases, reject existing tags and asset names, publish a draft with
all assets, verify the tag points to the reviewed commit, verify provenance and
re-download the assets before publishing. Authenticate the initial bootstrap
instructions independently before offering an installation command.
On failure stop; correct the source and use a new release identity if necessary.
Release verification on a development machine may use Python and Git; neither
is required by the installer runtime. No production release is available yet.

For development, run `make setup` to check the required tools and install
missing Homebrew formulae and prek Git hooks. Existing non-prek hooks are
preserved and must be resolved before setup can install hooks. Prek supplies
the pinned committed executable in its managed hook environment.

Run the static checks with ShellCheck, shfmt, typos, and actionlint installed:

```sh
make check
```

This checks Bash syntax, shell lint, formatting, spelling, workflow semantics,
and isolated tests without installing anything. CI runs on pushes to `master`
and pull requests targeting `master`: it runs these checks on Linux and the
bootstrap fixtures with Apple's bundled Bash on macOS 27. macOS 26 is not
included in the automated CI matrix.
GitHub-hosted macOS runners have preinstalled development tools, so passing
fixtures do not prove fresh-Mac installation. Test installation separately on an
explicitly authorized Apple Silicon Mac.
The commit-message hook enforces Conventional Commits, such as
`feat: add development tooling`.

To check a local customization script separately:

```sh
shellcheck ~/.laptop.local
```
