#!/bin/bash
# Bootstrap checkpoint: platform validation and Gum only.

set -eu

GUM_VERSION=2.0.2
# Reviewed against the official v2.0.2 checksum list and release artifact.
GUM_ARCHIVE_SHA256=4777a69b1170b8db23c95d5889fb32186cfda1a3ac950d339aa17e3513633890
GUM_URL=https://github.com/charmbracelet/gum/releases/download/v2.0.2/gum_2.0.2_Darwin_arm64.tar.gz
GUM_MEMBER=gum_2.0.2_Darwin_arm64/gum
GUM_BIN="${HOME}/.local/bin/gum"
TEMP_DIR=
CANDIDATE=

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$CANDIDATE" ]; then rm -f "$CANDIDATE"; fi
  if [ -n "$TEMP_DIR" ]; then rm -rf "$TEMP_DIR"; fi
}

check_platform() {
  os=$(uname -s) || fail 'Could not determine the operating system.'
  [ "$os" = Darwin ] || fail 'macOS is required; Linux is not supported yet.'
  hardware=$(sysctl -n hw.optional.arm64 2>/dev/null) || fail 'Could not determine Apple Silicon hardware.'
  [ "$hardware" = 1 ] || fail 'Apple Silicon hardware is required.'
  architecture=$(uname -m) || fail 'Could not determine the process architecture.'
  [ "$architecture" = arm64 ] || fail 'Run this bootstrap as a native arm64 process, not under Rosetta.'
  # macOS sysctl -i ignores an unknown OID, returning success with no value.
  # Treat that as native only after the hardware and architecture checks pass.
  translated=$(sysctl -in sysctl.proc_translated 2>/dev/null) || fail 'Could not determine Rosetta translation state.'
  case "$translated" in
  0 | '') ;;
  1) fail 'Run this bootstrap natively on Apple Silicon, not under Rosetta.' ;;
  *) fail 'Unexpected Rosetta translation state.' ;;
  esac
}

log() {
  printf '\n'
  "$GUM_BIN" style --foreground '#0087ff' --bold "==> $1"
}

log_success() {
  "$GUM_BIN" style --foreground '#33BD25' "✔ $1"
}

log_warning() {
  "$GUM_BIN" style --foreground '#ffff00' "⚠ $1"
}

log_error() {
  "$GUM_BIN" style --foreground '#ff0000' "✖ $1" >&2
}

install_gum() {
  [ ! -L "${HOME}/.local" ] && [ ! -L "${HOME}/.local/bin" ] || fail 'Refusing to install through a symlinked destination directory.'
  umask 077
  TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/laptop-gum.XXXXXX") || fail 'Could not create a private temporary directory.'
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  archive="$TEMP_DIR/gum.tar.gz"
  curl -fsSL -o "$archive" "$GUM_URL" || fail 'Could not download Gum.'
  archive_hash=$(shasum -a 256 "$archive") || fail 'Could not hash the Gum archive.'
  [ "${archive_hash%% *}" = "$GUM_ARCHIVE_SHA256" ] || fail 'Gum archive checksum mismatch.'

  members=$(tar -tzf "$archive") || fail 'Could not inspect the Gum archive.'
  expected_members='gum_2.0.2_Darwin_arm64/LICENSE
gum_2.0.2_Darwin_arm64/README.md
gum_2.0.2_Darwin_arm64/completions/gum.bash
gum_2.0.2_Darwin_arm64/completions/gum.fish
gum_2.0.2_Darwin_arm64/completions/gum.zsh
gum_2.0.2_Darwin_arm64/manpages/gum.1.gz
gum_2.0.2_Darwin_arm64/gum'
  [ "$members" = "$expected_members" ] || fail 'Unexpected or unsafe Gum archive contents.'
  tar -tvzf "$archive" >"$TEMP_DIR/members.txt" || fail 'Could not inspect Gum archive types.'
  awk 'substr($0, 1, 1) != "-" { bad = 1 } END { exit bad }' "$TEMP_DIR/members.txt" || fail 'Gum archive contains non-regular entries.'
  tar -xOzf "$archive" "$GUM_MEMBER" >"$TEMP_DIR/gum" || fail 'Could not extract the Gum binary.'
  [ -s "$TEMP_DIR/gum" ] || fail 'The extracted Gum binary is empty.'
  binary_hash=$(shasum -a 256 "$TEMP_DIR/gum") || fail 'Could not hash the Gum binary.'
  binary_hash=${binary_hash%% *}

  if [ -L "$GUM_BIN" ]; then fail 'Refusing to replace a Gum symlink.'; fi
  if [ -e "$GUM_BIN" ]; then
    [ -f "$GUM_BIN" ] && [ -x "$GUM_BIN" ] || fail 'Existing Gum path is not an executable regular file.'
    existing_hash=$(shasum -a 256 "$GUM_BIN") || fail 'Could not hash existing Gum.'
    [ "${existing_hash%% *}" = "$binary_hash" ] || fail 'Existing Gum differs from the verified binary; refusing to overwrite it.'
    log_success "Gum $GUM_VERSION already installed"
    return
  fi

  bin_dir="${HOME}/.local/bin"
  mkdir -p "$bin_dir" || fail 'Could not create ~/.local/bin.'
  [ -w "$bin_dir" ] || fail 'The destination directory is not writable.'
  CANDIDATE=$(mktemp "$bin_dir/.laptop-gum.XXXXXX") || fail 'Could not create a temporary Gum destination.'
  cp "$TEMP_DIR/gum" "$CANDIDATE" || fail 'Could not copy the Gum binary.'
  chmod 755 "$CANDIDATE" || fail 'Could not make Gum executable.'
  ln "$CANDIDATE" "$GUM_BIN" || fail 'Gum destination appeared or could not be created; refusing to overwrite it.'
  rm -f "$CANDIDATE"
  CANDIDATE=
  log_success "Gum $GUM_VERSION installed"
}

main() {
  case "${1:---gum-only}" in
  --check-platform)
    [ "$#" -eq 1 ] || fail 'Usage: /bin/bash install.sh [--check-platform|--gum-only]'
    check_platform
    printf '%s\n' 'Supported: native Apple Silicon macOS.'
    ;;
  --gum-only)
    [ "$#" -le 1 ] || fail 'Usage: /bin/bash install.sh [--check-platform|--gum-only]'
    check_platform
    install_gum
    ;;
  *) fail 'Usage: /bin/bash install.sh [--check-platform|--gum-only]' ;;
  esac
}

main "$@"
