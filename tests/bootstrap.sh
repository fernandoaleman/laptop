#!/usr/bin/env bash

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/laptop-bootstrap-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
REAL_SHASUM=$(command -v shasum)
export REAL_SHASUM
STUBS="$TEST_ROOT/stubs"
mkdir -p "$STUBS" "$TEST_ROOT/tmp" "$TEST_ROOT/payload/gum_2.0.2_Darwin_arm64/completions" "$TEST_ROOT/payload/gum_2.0.2_Darwin_arm64/manpages"

cat >"$STUBS/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) [ "${FAIL_OS:-0}" = 0 ] || exit 1; printf '%s\n' "${TEST_OS:-Darwin}" ;;
  -m) [ "${FAIL_ARCH:-0}" = 0 ] || exit 1; printf '%s\n' "${TEST_ARCH:-arm64}" ;;
esac
EOF
cat >"$STUBS/sysctl" <<'EOF'
#!/bin/sh
case "$2" in
  hw.optional.arm64) [ "$1" = -n ] && [ "${FAIL_HW:-0}" = 0 ] || exit 1; printf '%s\n' "${TEST_HW:-1}" ;;
  sysctl.proc_translated)
    [ "${FAIL_TRANSLATED:-0}" = 0 ] || exit 1
    if [ "${TEST_TRANSLATED:-0}" = missing ]; then
      [ "$1" = -in ] || exit 1
    else
      [ "$1" = -in ] || exit 1
      printf '%s\n' "${TEST_TRANSLATED:-0}"
    fi ;;
  *) exit 1 ;;
esac
EOF
cat >"$STUBS/curl" <<'EOF'
#!/bin/sh
printf 'download\n' >> "$TEST_CURL_LOG"
[ "${FAIL_DOWNLOAD:-0}" = 0 ] || exit 1
[ "$1" = -fsSL ] && [ "$2" = -o ] || exit 1
cp "$TEST_ARCHIVE" "$3"
EOF
cat >"$STUBS/shasum" <<'EOF'
#!/bin/sh
case "$3" in
  */gum.tar.gz)
    actual=$("$REAL_SHASUM" "$@") || exit 1
    if [ "${actual%% *}" = "$TEST_FIXTURE_SHA256" ]; then
      printf '4777a69b1170b8db23c95d5889fb32186cfda1a3ac950d339aa17e3513633890  %s\n' "$3"
    else
      printf '%s\n' "$actual"
    fi ;;
  */gum)
    actual=$("$REAL_SHASUM" "$@") || exit 1
    if [ "${actual%% *}" = "$TEST_FIXTURE_BINARY_SHA256" ] && [ "${FAIL_BINARY_HASH:-0}" = 0 ]; then
      printf '74cab6235944c0e39e69edfceef81150064687dd29cacec5ec1e954637f55d0c  %s\n' "$3"
    else
      printf '%s\n' "$actual"
    fi ;;
  *) exec "$REAL_SHASUM" "$@" ;;
esac
EOF
cat >"$STUBS/mkdir" <<'EOF'
#!/bin/sh
[ "${FAIL_MKDIR:-0}" = 0 ] || exit 1
exec /bin/mkdir "$@"
EOF
chmod +x "$STUBS/"*
PATH="$STUBS:$PATH"
export PATH

payload="$TEST_ROOT/payload/gum_2.0.2_Darwin_arm64"
for file in LICENSE README.md completions/gum.bash completions/gum.fish completions/gum.zsh manpages/gum.1.gz; do
  printf 'fixture\n' >"$payload/$file"
done
cat >"$payload/gum" <<'EOF'
#!/bin/sh
printf '%s\n' 'fixture gum style'
printf '%s\n' "$@"
EOF
chmod +x "$payload/gum"
TEST_FIXTURE_BINARY_SHA256=$("$REAL_SHASUM" -a 256 "$payload/gum")
TEST_FIXTURE_BINARY_SHA256=${TEST_FIXTURE_BINARY_SHA256%% *}
export TEST_FIXTURE_BINARY_SHA256
TEST_ARCHIVE="$TEST_ROOT/gum-fixture.tar.gz"
export TEST_ARCHIVE
tar -czf "$TEST_ARCHIVE" -C "$TEST_ROOT/payload" \
  gum_2.0.2_Darwin_arm64/LICENSE \
  gum_2.0.2_Darwin_arm64/README.md \
  gum_2.0.2_Darwin_arm64/completions/gum.bash \
  gum_2.0.2_Darwin_arm64/completions/gum.fish \
  gum_2.0.2_Darwin_arm64/completions/gum.zsh \
  gum_2.0.2_Darwin_arm64/manpages/gum.1.gz \
  gum_2.0.2_Darwin_arm64/gum
TEST_FIXTURE_SHA256=$("$REAL_SHASUM" -a 256 "$TEST_ARCHIVE")
TEST_FIXTURE_SHA256=${TEST_FIXTURE_SHA256%% *}
TEST_CURL_LOG="$TEST_ROOT/curl.log"
export TEST_FIXTURE_SHA256 TEST_CURL_LOG

TMPDIR="$TEST_ROOT/tmp"
export TMPDIR
count=0
new_home() {
  count=$((count + 1))
  HOME="$TEST_ROOT/home-$count"
  export HOME
  mkdir -p "$HOME"
}

assert_clean_tmp() {
  local entries
  if ! entries=$(find "$1" -mindepth 1 -print); then
    printf 'FAIL: could not inspect temporary directory: %s\n' "$1" >&2
    return 1
  fi
  if [ -n "$entries" ]; then
    printf 'FAIL: temporary files remain in %s\n' "$1" >&2
    return 1
  fi
}

# Exercise the cleanup assertion itself, including an actual traversal failure.
assert_clean_tmp "$TMPDIR"
mkdir "$TEST_ROOT/nonempty"
printf 'leftover\n' >"$TEST_ROOT/nonempty/file"
if assert_clean_tmp "$TEST_ROOT/nonempty" >"$TEST_ROOT/assert-output" 2>&1; then
  printf '%s\n' 'FAIL: cleanup assertion accepted remaining files' >&2
  exit 1
fi
grep -Fq 'temporary files remain' "$TEST_ROOT/assert-output"
if assert_clean_tmp "$TEST_ROOT/missing" >"$TEST_ROOT/assert-output" 2>&1; then
  printf '%s\n' 'FAIL: cleanup assertion accepted a failed traversal' >&2
  exit 1
fi
grep -Fq 'could not inspect temporary directory' "$TEST_ROOT/assert-output"
printf '%s\n' 'PASS: cleanup assertion rejects leftovers and traversal failures'

file_metadata() {
  local result
  if result=$(stat -f '%i %z %m' "$1" 2>/dev/null); then
    printf '%s\n' "$result"
  elif result=$(stat -c '%i %s %Y' "$1" 2>/dev/null); then
    printf '%s\n' "$result"
  else
    printf 'FAIL: could not read file metadata: %s\n' "$1" >&2
    return 1
  fi
}

# Simulate both stat implementations and failed probes that emit stdout.
stat() {
  case "$STAT_CASE:${1-}:${2-}" in
  'bsd:-f:%i %z %m' | 'gnu:-c:%i %s %Y') printf '%s\n' '11 22 33' ;;
  *)
    printf '%s\n' 'failed probe output'
    return 1
    ;;
  esac
}
STAT_CASE=bsd
[ "$(file_metadata fixture)" = '11 22 33' ] || {
  printf '%s\n' 'FAIL: BSD stat format' >&2
  exit 1
}
STAT_CASE=gnu
[ "$(file_metadata fixture)" = '11 22 33' ] || {
  printf '%s\n' 'FAIL: GNU stat format or probe contamination' >&2
  exit 1
}
STAT_CASE=fail
if file_metadata fixture >"$TEST_ROOT/stat-output" 2>/dev/null; then
  printf '%s\n' 'FAIL: failed stat probes succeeded' >&2
  exit 1
fi
[ ! -s "$TEST_ROOT/stat-output" ] || {
  printf '%s\n' 'FAIL: failed stat probe output leaked' >&2
  exit 1
}
unset -f stat
printf '%s\n' 'PASS: BSD and GNU metadata formats and failed probes'

expect_fail() {
  label=$1
  diagnostic=$2
  shift 2
  if "$@" >"$TEST_ROOT/output" 2>&1; then
    printf 'FAIL: %s unexpectedly succeeded\n' "$label" >&2
    exit 1
  fi
  if ! grep -Fq "$diagnostic" "$TEST_ROOT/output"; then
    printf 'FAIL: %s produced the wrong diagnostic\n' "$label" >&2
    cat "$TEST_ROOT/output" >&2
    exit 1
  fi
  assert_clean_tmp "$TMPDIR" || exit 1
  printf 'PASS: %s\n' "$label"
}

new_home
/bin/bash "$ROOT/install.sh" --check-platform >"$TEST_ROOT/output"
[ ! -e "$HOME/.local" ] || exit 1
printf '%s\n' 'PASS: native Apple Silicon platform'
expect_fail 'Linux' 'macOS is required' env TEST_OS=Linux /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'Intel Mac' 'Apple Silicon hardware is required' env TEST_HW=0 TEST_ARCH=x86_64 /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'Rosetta translation' 'not under Rosetta' env TEST_TRANSLATED=1 TEST_ARCH=x86_64 /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'translated sysctl disagreement' 'not under Rosetta' env TEST_TRANSLATED=1 /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'unexpected translation result' 'Unexpected Rosetta translation state' env TEST_TRANSLATED=unexpected /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'hardware probe failure' 'Could not determine Apple Silicon hardware' env FAIL_HW=1 /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'translation probe failure' 'Could not determine Rosetta translation state' env FAIL_TRANSLATED=1 /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'OS probe failure' 'Could not determine the operating system' env FAIL_OS=1 /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'architecture probe failure' 'Could not determine the process architecture' env FAIL_ARCH=1 /bin/bash "$ROOT/install.sh" --gum-only
env TEST_TRANSLATED=missing /bin/bash "$ROOT/install.sh" --check-platform >"$TEST_ROOT/output"
printf '%s\n' 'PASS: missing translation key on native arm64'
expect_fail 'missing translation key with translated architecture' 'not under Rosetta' env TEST_TRANSLATED=missing TEST_ARCH=x86_64 /bin/bash "$ROOT/install.sh" --gum-only
[ ! -e "$TEST_CURL_LOG" ] && [ ! -e "$HOME/.local" ] || {
  printf '%s\n' 'FAIL: platform checks caused side effects' >&2
  exit 1
}

new_home
/bin/bash "$ROOT/install.sh" >"$TEST_ROOT/output"
[ -x "$HOME/.local/bin/gum" ] || exit 1
printf '%s\n' 'PASS: verified Gum installation'
ln "$HOME/.local/bin/gum" "$TEST_ROOT/reused-gum"
before=$(file_metadata "$HOME/.local/bin/gum") || exit 1
before_hash=$("$REAL_SHASUM" -a 256 "$HOME/.local/bin/gum") || {
  printf '%s\n' 'FAIL: could not hash Gum before reuse' >&2
  exit 1
}
curl_count=$(wc -l <"$TEST_CURL_LOG") || {
  printf '%s\n' 'FAIL: could not count downloads before reuse' >&2
  exit 1
}
env FAIL_DOWNLOAD=1 /bin/bash "$ROOT/install.sh" --gum-only >"$TEST_ROOT/output" || {
  printf '%s\n' 'FAIL: offline Gum reuse failed' >&2
  exit 1
}
grep -q 'fixture gum style' "$TEST_ROOT/output" || {
  printf '%s\n' 'FAIL: Gum reuse output missing' >&2
  exit 1
}
grep -Fq 'Gum 2.0.2 already installed' "$TEST_ROOT/output" || {
  printf '%s\n' 'FAIL: Gum reuse diagnostic missing' >&2
  exit 1
}
[ "$HOME/.local/bin/gum" -ef "$TEST_ROOT/reused-gum" ] || {
  printf '%s\n' 'FAIL: Gum hard-link identity changed' >&2
  exit 1
}
after=$(file_metadata "$HOME/.local/bin/gum") || exit 1
[ "$before" = "$after" ] || {
  printf 'FAIL: Gum metadata changed: %s -> %s\n' "$before" "$after" >&2
  exit 1
}
after_hash=$("$REAL_SHASUM" -a 256 "$HOME/.local/bin/gum") || {
  printf '%s\n' 'FAIL: could not hash Gum after reuse' >&2
  exit 1
}
[ "$before_hash" = "$after_hash" ] || {
  printf '%s\n' 'FAIL: Gum SHA-256 changed' >&2
  exit 1
}
after_curl_count=$(wc -l <"$TEST_CURL_LOG") || {
  printf '%s\n' 'FAIL: could not count downloads after reuse' >&2
  exit 1
}
[ "$curl_count" = "$after_curl_count" ] || {
  printf '%s\n' 'FAIL: curl invoked during offline reuse' >&2
  exit 1
}
printf '%s\n' 'PASS: matching Gum reused offline without curl or replacement'

new_home
mkdir -p "$HOME/.local/bin"
printf 'unrelated\n' >"$HOME/.local/bin/gum"
chmod +x "$HOME/.local/bin/gum"
expect_fail 'unknown existing Gum' 'refusing to overwrite' /bin/bash "$ROOT/install.sh" --gum-only
grep -q unrelated "$HOME/.local/bin/gum"

new_home
mkdir -p "$HOME/.local/bin"
cp "$payload/gum" "$HOME/.local/bin/gum"
printf '# modified\n' >>"$HOME/.local/bin/gum"
modified_hash=$("$REAL_SHASUM" -a 256 "$HOME/.local/bin/gum")
expect_fail 'modified existing Gum' 'refusing to overwrite' env FAIL_DOWNLOAD=1 /bin/bash "$ROOT/install.sh" --gum-only
[ "$modified_hash" = "$("$REAL_SHASUM" -a 256 "$HOME/.local/bin/gum")" ] || exit 1

new_home
mkdir -p "$HOME/.local/bin"
ln -s "$TEST_ROOT/absent" "$HOME/.local/bin/gum"
expect_fail 'existing Gum symlink' 'Gum symlink' /bin/bash "$ROOT/install.sh" --gum-only
[ -L "$HOME/.local/bin/gum" ] || exit 1

new_home
mkdir -p "$HOME/.local/bin/gum"
expect_fail 'existing Gum directory' 'not an executable regular file' /bin/bash "$ROOT/install.sh" --gum-only
new_home
expect_fail 'download failure' 'Could not download Gum' env FAIL_DOWNLOAD=1 /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'checksum mismatch' 'checksum mismatch' env TEST_FIXTURE_SHA256=incorrect /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'binary checksum mismatch' 'Gum binary checksum mismatch' env FAIL_BINARY_HASH=1 /bin/bash "$ROOT/install.sh" --gum-only
expect_fail 'destination creation failure' 'Could not create ~/.local/bin' env FAIL_MKDIR=1 /bin/bash "$ROOT/install.sh" --gum-only

new_home
mkdir -p "$HOME/.local/bin"
chmod 500 "$HOME/.local/bin"
if [ ! -w "$HOME/.local/bin" ]; then
  expect_fail 'unwritable destination permissions' 'destination directory is not writable' /bin/bash "$ROOT/install.sh" --gum-only
else
  printf '%s\n' 'INFO: destination permissions are writable to this user; testing the check with a stub'
fi
chmod 700 "$HOME/.local/bin"
cat >"$TEST_ROOT/unwritable-bash-env" <<'EOF'
# Simulate the destination write check for users who can bypass mode bits.
[() {
  case "$#:${1-}:${2-}" in
    "3:-w:$HOME/.local/bin") return 1 ;;
  esac
  builtin [ "$@"
}
EOF
expect_fail 'unwritable destination check' 'destination directory is not writable' env BASH_ENV="$TEST_ROOT/unwritable-bash-env" /bin/bash "$ROOT/install.sh" --gum-only
assert_clean_tmp "$HOME/.local/bin" || exit 1

printf 'unexpected\n' >"$TEST_ROOT/payload/extra"
tar -czf "$TEST_ROOT/unsafe.tar.gz" -C "$TEST_ROOT/payload" extra
unsafe_hash=$("$REAL_SHASUM" -a 256 "$TEST_ROOT/unsafe.tar.gz")
expect_fail 'unexpected archive contents' 'Unexpected or unsafe Gum archive contents' env TEST_ARCHIVE="$TEST_ROOT/unsafe.tar.gz" TEST_FIXTURE_SHA256="${unsafe_hash%% *}" /bin/bash "$ROOT/install.sh" --gum-only

mv "$payload/gum" "$TEST_ROOT/gum-regular"
ln -s "$TEST_ROOT/gum-regular" "$payload/gum"
tar -czf "$TEST_ROOT/link.tar.gz" -C "$TEST_ROOT/payload" \
  gum_2.0.2_Darwin_arm64/LICENSE \
  gum_2.0.2_Darwin_arm64/README.md \
  gum_2.0.2_Darwin_arm64/completions/gum.bash \
  gum_2.0.2_Darwin_arm64/completions/gum.fish \
  gum_2.0.2_Darwin_arm64/completions/gum.zsh \
  gum_2.0.2_Darwin_arm64/manpages/gum.1.gz \
  gum_2.0.2_Darwin_arm64/gum
link_hash=$("$REAL_SHASUM" -a 256 "$TEST_ROOT/link.tar.gz")
expect_fail 'archive symlink' 'non-regular entries' env TEST_ARCHIVE="$TEST_ROOT/link.tar.gz" TEST_FIXTURE_SHA256="${link_hash%% *}" /bin/bash "$ROOT/install.sh" --gum-only

new_home
ln -s "$TEST_ROOT/absent" "$HOME/.local"
expect_fail 'symlinked destination parent' 'symlinked destination directory' /bin/bash "$ROOT/install.sh" --gum-only
printf '%s\n' 'All isolated bootstrap tests passed.'
