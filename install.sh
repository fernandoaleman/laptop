#!/bin/bash
# Bootstrap checkpoint: platform validation and Gum only.

set -eu

GUM_VERSION=2.0.2
# Reviewed against the official v2.0.2 checksum list and release artifact.
GUM_ARCHIVE_SHA256=4777a69b1170b8db23c95d5889fb32186cfda1a3ac950d339aa17e3513633890
# SHA-256 of the Gum binary extracted from the verified official archive.
GUM_BINARY_SHA256=74cab6235944c0e39e69edfceef81150064687dd29cacec5ec1e954637f55d0c
GUM_URL=https://github.com/charmbracelet/gum/releases/download/v2.0.2/gum_2.0.2_Darwin_arm64.tar.gz
GUM_MEMBER=gum_2.0.2_Darwin_arm64/gum
GUM_BIN="${HOME}/.local/bin/gum"
# No release payload has been published or independently pinned yet.
PAYLOAD_VERSION=0.0.0-dev
PAYLOAD_URL=
PAYLOAD_SHA256=
TEMP_DIR=
PAYLOAD_TEMP=
CANDIDATE=

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [ -n "$CANDIDATE" ]; then rm -f "$CANDIDATE"; fi
  if [ -n "$TEMP_DIR" ]; then rm -rf "$TEMP_DIR"; fi
  if [ -n "$PAYLOAD_TEMP" ]; then rm -rf "$PAYLOAD_TEMP"; fi
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
  if [ -L "$GUM_BIN" ]; then fail 'Refusing to replace a Gum symlink.'; fi
  if [ -e "$GUM_BIN" ]; then
    [ -f "$GUM_BIN" ] && [ -x "$GUM_BIN" ] || fail 'Existing Gum path is not an executable regular file.'
    existing_hash=$(shasum -a 256 "$GUM_BIN") || fail 'Could not hash existing Gum.'
    [ "${existing_hash%% *}" = "$GUM_BINARY_SHA256" ] || fail 'Existing Gum differs from the verified binary; refusing to overwrite it.'
    log_success "Gum $GUM_VERSION already installed"
    return
  fi
  umask 077
  TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/laptop-gum.XXXXXX") || fail 'Could not create a private temporary directory.'
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  archive="$TEMP_DIR/gum.tar.gz"
  # The verified v2.0.2 archive is 4.7 MB; cap download at 8 MiB.
  (set +o posix && ulimit -f 8192 && curl -fsSL -o "$archive" "$GUM_URL") || fail 'Could not download Gum within the size limit.'
  archive_hash=$(shasum -a 256 "$archive") || fail 'Could not hash the Gum archive.'
  [ "${archive_hash%% *}" = "$GUM_ARCHIVE_SHA256" ] || fail 'Gum archive checksum mismatch.'

  # Bound the expanded tar (officially about 14 MB) and each listing.
  unpacked="$TEMP_DIR/gum.tar"
  (set +o posix && ulimit -f 24576 && gzip -dc "$archive" >"$unpacked") || fail 'Could not decompress Gum within the size limit.'
  (set +o posix && ulimit -f 64 && tar -tf "$unpacked" >"$TEMP_DIR/member-names") || fail 'Could not inspect Gum archive within the listing limit.'
  members=$(cat "$TEMP_DIR/member-names") || fail 'Could not read Gum archive members.'
  expected_members='gum_2.0.2_Darwin_arm64/LICENSE
gum_2.0.2_Darwin_arm64/README.md
gum_2.0.2_Darwin_arm64/completions/gum.bash
gum_2.0.2_Darwin_arm64/completions/gum.fish
gum_2.0.2_Darwin_arm64/completions/gum.zsh
gum_2.0.2_Darwin_arm64/manpages/gum.1.gz
gum_2.0.2_Darwin_arm64/gum'
  [ "$members" = "$expected_members" ] || fail 'Unexpected or unsafe Gum archive contents.'
  (set +o posix && ulimit -f 64 && tar -tvf "$unpacked" >"$TEMP_DIR/members.txt") || fail 'Could not inspect Gum archive types within the listing limit.'
  awk 'substr($0, 1, 1) != "-" { bad = 1 } END { if (NR != 7 || bad) exit 1 }' "$TEMP_DIR/members.txt" || fail 'Gum archive contains non-regular entries.'
  # The verified binary is 13.9 MB; cap the extracted file at 16 MiB.
  (set +o posix && ulimit -f 16384 && tar -xOf "$unpacked" "$GUM_MEMBER" >"$TEMP_DIR/gum") || fail 'Could not extract Gum within the size limit.'
  [ -s "$TEMP_DIR/gum" ] || fail 'The extracted Gum binary is empty.'
  binary_hash=$(shasum -a 256 "$TEMP_DIR/gum") || fail 'Could not hash the Gum binary.'
  [ "${binary_hash%% *}" = "$GUM_BINARY_SHA256" ] || fail 'Gum binary checksum mismatch.'

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

install_payload() {
  umask 077
  PAYLOAD_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/laptop-payload.XXXXXX") || fail 'Could not create a private payload directory.'
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  archive="$PAYLOAD_TEMP/payload.tar.gz"
  (set +o posix && ulimit -f 5120 && curl -fsSL -o "$archive" "$PAYLOAD_URL") || fail 'Could not download payload.'
  payload_hash=$(shasum -a 256 "$archive") || fail 'Could not hash payload.'
  [ "${payload_hash%% *}" = "$PAYLOAD_SHA256" ] || fail 'Payload checksum mismatch.'
  archive_size=$(wc -c <"$archive") || fail 'Could not inspect payload size.'
  [ "$archive_size" -le 5242880 ] || fail 'Payload archive is too large.'
  unpacked="$PAYLOAD_TEMP/payload.tar"
  (set +o posix && ulimit -f 12288 && gzip -dc "$archive" >"$unpacked") || fail 'Could not decompress payload archive.'
  (set +o posix && ulimit -f 1024 && tar -tf "$unpacked" >"$PAYLOAD_TEMP/members") || fail 'Could not inspect payload archive.'
  members=$(cat "$PAYLOAD_TEMP/members") || fail 'Could not read payload members.'
  expected='payload-version
install/run.sh
install/components/prepare.sh
install/components/example.sh
lib/logging.sh'
  [ "$members" = "$expected" ] || fail 'Unexpected or unsafe payload archive contents.'
  (set +o posix && ulimit -f 1024 && tar -tvf "$unpacked" --numeric-owner >"$PAYLOAD_TEMP/metadata") || fail 'Could not inspect payload metadata.'
  awk '
    $1 != "-rw-r--r--" { bad = 1 }
    {
      size = ""
      if ($2 == "0/0") size = $3
      else if ($2 == "0" && $3 == "0" && $4 == "0") size = $5
      if (size !~ /^[0-9]+$/ || size > 1048576) bad = 1
    }
    END { if (NR != 5 || bad) exit 1 }
  ' "$PAYLOAD_TEMP/metadata" || fail 'Unsafe payload entry metadata or size.'
  root="$PAYLOAD_TEMP/root"
  mkdir -p "$root/install/components" "$root/lib" || fail 'Could not create payload directories.'
  root=$(cd "$root" && pwd -P) || fail 'Could not resolve payload directory.'
  for member in payload-version install/run.sh install/components/prepare.sh install/components/example.sh lib/logging.sh; do
    tar -xOf "$unpacked" "$member" >"$root/$member" || fail "Could not extract payload member: $member"
  done
  printf '%s\n' "$PAYLOAD_VERSION" | cmp -s - "$root/payload-version" || fail 'Payload version mismatch.'
  if PAYLOAD_ROOT=$root GUM_BIN=$GUM_BIN /bin/bash "$root/install/run.sh" --apply; then
    :
  else
    rc=$?
    printf 'Error: payload runner failed (exit %s).\n' "$rc" >&2
    exit "$rc"
  fi
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
  --payload)
    [ "$#" -eq 1 ] || fail 'Usage: /bin/bash install.sh [--check-platform|--gum-only|--payload]'
    check_platform
    [ -n "$PAYLOAD_URL" ] && [ -n "$PAYLOAD_SHA256" ] || fail 'No verified payload release is available yet.'
    case "$PAYLOAD_URL" in https://*) ;; *) fail 'Payload URL must use HTTPS.' ;; esac
    [ "${#PAYLOAD_SHA256}" -eq 64 ] || fail 'Invalid pinned payload checksum.'
    case "$PAYLOAD_SHA256" in *[!0-9a-f]*) fail 'Invalid pinned payload checksum.' ;; esac
    install_gum
    install_payload
    ;;
  *) fail 'Usage: /bin/bash install.sh [--check-platform|--gum-only|--payload]' ;;
  esac
}

main "$@"
