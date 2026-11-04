# Project instructions

- Develop only in `~/code/fernandoaleman/laptop`. Preserve unrelated work and follow existing repository instructions.
- Use `~/code/1000bulbs/laptop` and `~/code/fernandoaleman/dots-omarchy` as read-only references for V2 modernization.
- Use `~/code/fernandoaleman/dotfiles` as a read-only reference for existing shell and dotfiles configuration. The separately developed `~/code/dots` project is the future dotfiles manager.
- The remote test MacBook is `macbook-pro`; do not access or modify it without explicit authorization.
- In Herdr workspace `laptop`, `laptop-lead` orchestrates; `laptop-personal`, `laptop-work`, `laptop-compat`, and `laptop-review` provide independent read-only findings. The orchestrator is the sole writer.
- Keep `master` as the main branch. Use short-lived feature branches, local validation, GitHub Actions CI, Codex review, and approved squash merges.
- Require explicit approval before committing, pushing, opening PRs, merging, deleting branches, or destructive operations.
- Run `make check` before proposing a commit. Never execute the installer or change macOS settings during static validation.
- V2 currently targets Apple Silicon macOS. Linux support is a future goal, not part of the current implementation.
- The approved V2 entry point is `install.sh`, replacing the existing `laptop` installer when that change is explicitly authorized.
- The installer must support a single-command fresh-machine bootstrap without requiring Git, Homebrew, or Xcode Command Line Tools beforehand.
- Use modular Bash installation components and a versioned, integrity-verified repository archive. Keep the bootstrap compatible with the Bash version bundled with macOS.
- Install Gum before Homebrew using an official, verified Apple Silicon binary. Installation components must be idempotent and independently testable.
- Keep machine provisioning separate from dotfiles management. The `laptop` repository installs and prepares the machine; the future `dots` manager handles personal configuration. Do not integrate the projects without explicit approval.
- Use lightweight ADRs under `docs/adr/` for significant architectural decisions. Obtain approval before accepting an ADR; supersede accepted decisions rather than silently rewriting them.
- The default interactive shell (Bash versus Zsh) remains undecided. Installer scripts use Bash.
- Do not create or modify agent skills without separate approval; shared skills belong under `.agents/skills` when approved.

## GitHub tracking

- Use GitHub Issues as the primary tracker for substantive laptop development; avoid duplicate or retrospective issues for completed work.
- Group coherent multi-issue work in meaningful milestones. Define scope, acceptance criteria, dependencies, and relevant PR links in each issue.
- Use `Refs` for partial work and `Closes` only when merging fully satisfies the issue.
- Require explicit authorization for tracker changes. Close issues and milestones only when their acceptance criteria are satisfied.

## Provisioning inventory and approval policy

- Before adding packages, Brewfile entries, applications, tools, services, runtimes, macOS defaults, or shell configuration, compare relevant implementations in the personal laptop repository, `~/code/fernandoaleman/dots-omarchy`, `~/code/fernandoaleman/dotfiles`, and `~/code/1000bulbs/laptop`, plus upstream Omarchy when appropriate. Inspect references read-only; develop only in the personal laptop repository.
- Produce an itemized inventory with each candidate's name, purpose, source, dependencies, potential conflicts or duplication, and recommended disposition: Install, Skip, Replace, or Defer.
- Obtain explicit user approval for each candidate before adding it to provisioning components, Brewfiles, or configuration. Never copy an entire package list or installation section without individual review.
- Treat Homebrew and prerequisites; formulae and Brewfile entries; casks and graphical applications; CLI and developer tools; runtimes and version managers; background services and agents; macOS defaults and system preferences; interactive and login shell configuration; and dotfiles integration as separate decision categories. Stop at each category boundary until explicitly approved.
- Revisit Bash versus Zsh before changing the interactive or login shell. Bash 3.2 installer compatibility does not decide the interactive shell. Do not change the login shell, shell startup files, or persistent PATH without separate approval.
- Personal dotfiles belong to the future dots manager; do not automatically install, configure, or integrate it during laptop provisioning. Approval to implement an installer component is separate from approval to execute it on the MacBook.

## Draft pull request workflow

- Use a GitHub draft pull request as the default collaboration and review mechanism for every feature branch that changes repository files.
- Create feature branches from the latest approved `master`.
- Implement only the current approved task or checkpoint.
- Group changes into logical Conventional Commits rather than committing after every file edit.
- Run `make check` and applicable validation before proposing a commit.
- After approval to commit and publish, push the feature branch and create a draft PR against `master`, or update its existing draft PR.
- Keep the same draft PR open throughout implementation and iterative review.
- Report the draft PR URL, commit SHA, changed files, validation results, and unresolved issues after each published checkpoint.
- Use the draft PR to support external review and follow-up changes.
- Do not automatically mark draft PRs ready for review.
- Mark a draft PR ready only after explicit approval that implementation is complete.
- Once ready, verify GitHub Actions CI, Codex review, and any required checks.
- Squash-merge ("squerge") only with explicit approval.
- Do not treat the existence of a draft PR as authorization for additional commits, pushes, or implementation work.
- Stop after every assigned task and wait for the next instruction.

A draft PR is the default workflow, not automatic authorization to publish changes. Existing mandatory approval gates remain in effect unless the user explicitly authorizes a bounded operation.

## Orchestrator execution and approval policy

### Autonomous execution within approved scope

The orchestrator may independently execute routine commands needed to complete the current explicitly approved task, including:

- Reading repository files and inspecting Git status and diffs.
- Creating or modifying files within the approved scope.
- Running local tests, linting, formatting, and static analysis.
- Delegating read-only investigation and review to specialists.
- Troubleshooting failures within the approved task boundaries.

Do not request approval for every routine command.

### Mandatory approval gates

Obtain explicit user approval before:

- Creating, amending, or deleting commits.
- Pushing, force-pushing, or modifying remote branches.
- Opening, updating, closing, or merging pull requests.
- Creating or deleting tags or releases.
- Creating, switching, or deleting branches when not already authorized.
- Installing software or changing system configuration.
- Accessing or modifying remote machines, including macbook-pro.
- Performing destructive operations or modifying files outside the approved scope.
- Accessing secrets or changing credentials.

Do not treat an earlier approval as authorization for later tasks.

### Task completion and handoff

Complete only the task specified in the current user prompt.

When finished:

1. Summarize actions taken.
2. Report files modified and validation results.
3. Identify unresolved issues or risks.
4. Recommend the next logical step without executing it.
5. STOP and wait for the next explicit user instruction.

Do not automatically start the next task, create additional work, commit, push, or merge.

### Specialist coordination

The orchestrator is the only agent authorized to modify repository files within an approved task.

Specialists operate in read-only mode and return findings to the orchestrator.

The orchestrator must collect specialist results before reporting that delegated work is complete.
