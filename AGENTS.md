# Project instructions

- Develop only in `~/code/fernandoaleman/laptop`; use `~/code/1000bulbs/laptop` as a read-only V2 reference. Preserve unrelated work and follow existing repository instructions.
- The remote test MacBook is `macbook-pro`; do not modify it without explicit authorization.
- In Herdr workspace `laptop`, `laptop-lead` orchestrates; `laptop-personal`, `laptop-work`, `laptop-compat`, and `laptop-review` provide independent read-only findings. The orchestrator is the sole writer.
- Keep `master` as the main branch. Use short-lived feature branches, local validation, GitHub Actions CI, Codex review, and approved squash merges.
- Require explicit approval before committing, pushing, opening PRs, merging, deleting branches, or destructive operations.
- Run `make check` before proposing a commit. Never execute the `laptop` installer or change macOS settings during static validation.
- V2 requirements are goals, not authorization to implement them. Keep the installer named `laptop` until its rename is approved.
- Do not create or modify agent skills without separate approval; shared skills belong under `.agents/skills` when approved.
