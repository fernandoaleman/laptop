# Bash installer and deferred interactive shell

## Status

Proposed

## Context

The fresh Mac bootstrap must run under Apple's bundled Bash 3.2. Installation scripts and the user's interactive login shell have separate purposes; selecting an installer language does not settle the user's shell preference.

## Decision

Write installer scripts in Bash. The entry point and all code it executes before any explicitly established interpreter transition must work with bundled Bash 3.2. Prefer Bash 3.2-compatible components until a newer-interpreter boundary is justified and separately approved. Test the bootstrap with Bash 3.2 and test any later boundary explicitly.

Do not choose or change the user's interactive or login shell as part of this decision. The choice between Bash and Zsh, any shell installation, startup-file changes, and login-shell changes require a later decision and authorization.

## Consequences

Bash 3.2 compatibility constrains syntax and available features; ordinary syntax checks on newer Bash are insufficient. The installer can provision a machine without deciding how personal configuration or the interactive shell is managed. A later interpreter transition or shell choice must document its prerequisites, verification, and recovery.
