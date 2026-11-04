# Separate provisioning from dotfiles

## Status

Proposed

## Context

The laptop project provisions a machine; personal shell and application configuration has a separate lifecycle. The future `dots` manager is being developed separately and does not yet have an approved integration with this installer.

## Decision

The laptop installer owns machine provisioning and its own prerequisites. Personal dotfiles, their deployment, updates, and conflict handling belong to the separate dots manager. Do not install, invoke, or integrate that manager without explicit approval. Treat existing dotfiles and startup files as user data and preserve them unless a separately approved step specifies otherwise.

## Consequences

Provisioning can be tested and released independently of dotfiles. Users may need a separate configuration step. The fate of legacy `~/.laptop.local` customization and the eventual integration interface remain open decisions; neither is implicitly carried forward or removed by this ADR.
