#!/usr/bin/env bash
# A harmless prerequisite component.
set -eu
case "${1:-}" in
--check | --apply) exit 0 ;;
*)
  printf '%s\n' 'Usage: prepare.sh --check|--apply' >&2
  exit 2
  ;;
esac
