# Single-command modular installer

## Status

Proposed

## Context

V2 must configure a fresh Apple Silicon Mac from one README command without requiring Git, Homebrew, or Xcode Command Line Tools beforehand. The existing `laptop` installer is a single script. The bootstrap must use Apple's bundled Bash 3.2 and install Gum from a verified official binary before Homebrew.

## Decision

- Provide a self-contained `install.sh` bootstrap and a small runner with focused Bash components for machine provisioning. The bootstrap rejects unsupported operating systems and architectures before changing the machine.
- The README command obtains the bootstrap for one approved version. The bootstrap obtains a matching versioned archive without Git, verifies it against a trusted expected digest before extraction or execution, and checks the extracted release identity before dispatch. Gum has its own pinned version and independently trusted digest and is installed to `~/.local/bin/gum` before Homebrew.
- Keep the version and archive digest tied to the bootstrap release. Avoid a self-referential archive digest: produce an archive of the modular payload that excludes the bootstrap, then embed its digest in the bootstrap. Do not resolve separate moving `latest` references for either artifact.
- Download to a private temporary directory; fail closed on network, checksum, version, platform, or extraction errors. Validate archive entries before extraction and reject unsafe paths and links. Clean owned temporary files on normal exit, failure, and catchable interruption without deleting pre-existing user data. A kill or power loss may leave a temporary directory; any later cleanup must identify installer-owned paths safely.
- The runner executes components in a documented order, reports the failed component and exit status, and stops on failure. Components check actual state, are safe to rerun after interruption, preserve existing user data, and can run independently with explicit prerequisites. Retrying is not a promise to undo completed system changes.
- Keep dependencies injectable for isolated tests. Test unsupported platforms, checksum and version mismatch, unsafe archives, failed downloads, interruption, reruns, and Gum-before-Homebrew ordering using temporary homes and stubs. Run bootstrap tests with actual Bash 3.2 in CI when a suitable runner is available. No complete installer or system changes run during static validation.

Suggested layout: `install.sh` (bootstrap), `install/` (runner and small components), `lib/` (shared logging and helpers), and `tests/` (isolated fixtures). The approved Gum logging functions should be preserved when implemented.

## Consequences

Network access is required for the normal one-command bootstrap. No preinstalled Git, Homebrew, or Xcode Command Line Tools are assumed; later steps may install required tools. The MacBook remains untouched until an explicitly approved, incremental live test. Linux is reserved for future work.

Open decisions before implementation or release: exact artifact hosting and reproducible packaging, release/version selection and metadata, how the README command authenticates the bootstrap and how digest values are reviewed and published, Gum release and verification method, archive safety checks compatible with macOS tools, supported component invocation interface, and transcript location. An unrecognized existing `~/.local/bin/gum` must not be overwritten; the managed-binary identification, update, and unwritable-directory policies remain open. A digest obtained solely alongside an artifact does not independently authenticate it. Signed manifests versus reviewed pinned digests remains undecided.
