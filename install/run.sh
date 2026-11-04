#!/usr/bin/env bash
set -eu

case "${1:-}" in
--check | --apply) mode=$1 ;;
*)
  printf '%s\n' 'Usage: run.sh --check|--apply' >&2
  exit 2
  ;;
esac
[ "$#" -eq 1 ] || exit 2
case "${PAYLOAD_ROOT:-}" in /*) ;; *)
  printf '%s\n' 'PAYLOAD_ROOT must be absolute.' >&2
  exit 2
  ;;
esac
case "${GUM_BIN:-}" in /*) ;; *)
  printf '%s\n' 'GUM_BIN must be absolute.' >&2
  exit 2
  ;;
esac
[ -x "$GUM_BIN" ] || {
  printf '%s\n' 'Gum is not executable.' >&2
  exit 1
}
# The verified payload root is selected at runtime; lint logging.sh separately.
# shellcheck disable=SC1091
. "$PAYLOAD_ROOT/lib/logging.sh"
for name in prepare example; do
  component="$PAYLOAD_ROOT/install/components/$name.sh"
  log "Running $name $mode"
  if /bin/bash "$component" "$mode"; then
    log_success "$name complete"
  else
    rc=$?
    log_error "$name failed (exit $rc)" || printf '%s\n' "$name failed (exit $rc)" >&2
    exit "$rc"
  fi
done
