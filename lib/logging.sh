#!/usr/bin/env bash

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
