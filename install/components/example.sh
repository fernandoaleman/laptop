#!/usr/bin/env bash
# A harmless component demonstrating the runner interface.
set -eu
case "${1:-}" in
--check | --apply) exit 0 ;;
*)
  printf '%s\n' 'Usage: example.sh --check|--apply' >&2
  exit 2
  ;;
esac
