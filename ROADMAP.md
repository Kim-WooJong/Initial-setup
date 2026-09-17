# Initial-setup Roadmap

This roadmap focuses on stability first, then a gradual migration toward a more reliable rclone-based synchronization workflow.

## Current Direction

The project is in a **stabilization phase**.

Near-term priorities:

- keep normal setup predictable and repeatable
- reduce unnecessary complexity
- improve recovery and conflict handling
- validate behavior on real Windows, macOS, and Linux systems
- avoid large architectural changes until the current workflow is proven stable

The current default synchronization backend remains `directory`.

---

## 0.12.x Stabilization

Before moving toward 1.0, the project should continue improving reliability rather than adding many new features.

### Priorities

- fix runtime and cross-platform compatibility issues
- keep repeated `nu setup.nu` runs idempotent
- improve lock diagnostics and stale-lock handling
- validate transaction resume and rollback behavior
- keep README and command documentation concise
- add regression tests for bugs found on real machines
- verify Windows behavior as the primary reference environment

### Exit Criteria

The 0.12.x line is considered stable when:

- a clean Windows machine can bootstrap and complete setup
- running setup again does not damage or duplicate configuration
- interrupted setup can be resumed or safely restarted
- private-source conflicts are detected before destructive changes
- local backup and rollback work reliably
- directory-provider synchronization no longer depends on cloud-synced lock files

---

# rclone Provider Migration

The long-term goal is to make `rclone` the preferred synchronization provider while keeping the current `directory` backend as a fallback.

Migration should be gradual and reversible.

## Phase 1 — Probe and Read-Only Validation

Goal: verify that the configured rclone remote is reliable before allowing it to become part of the normal write path.

Planned checks:

- remote exists and is reachable
- authentication works
- expected directory can be listed
- small test objects can be read safely
- remote metadata can be retrieved
- failures are reported clearly without modifying local configuration

Example future commands:

```nu
dotbackend probe-rclone
dotbackend status
```

No existing directory-based synchronization should change during this phase.

---

## Phase 2 — Shadow Synchronization

Goal: compare rclone transfers against the existing directory backend without making rclone authoritative.

Concept:

```text
Local managed state
        |
        +--> directory provider      (primary)
        |
        +--> rclone shadow store     (verification only)
```

The project should compare:

- file inventory
- SHA-256 hashes
- revision metadata
- upload/download integrity
- behavior after interrupted transfers

A mismatch must be reported, not automatically corrected.

### Required Tests

- normal push
- normal pull
- interrupted upload
- interrupted download
- unavailable network
- Unicode paths
- paths containing spaces
- large files
- repeated identical synchronization

---

## Phase 3 — rclone as Primary Provider

Goal: allow the user to explicitly promote rclone to the primary provider.

Target flow:

```text
dotpush
  |
  +--> calculate local manifest
  +--> verify expected remote revision
  +--> upload immutable revision
  +--> verify uploaded hashes
  +--> publish HEAD last
  +--> record new local baseline
```

A failed upload must never replace the last valid remote `HEAD`.

A stale machine must not overwrite a newer revision.

Example configuration:

```nu
dotbackend configure --kind rclone --remote "remote:Initial-setup"
```

Promotion should remain explicit. Existing users should never be migrated automatically.

---

## Phase 4 — Directory Provider as Fallback

Once rclone has been proven reliable across supported platforms:

- `rclone` becomes the recommended provider
- `directory` remains available for users who prefer a desktop cloud client
- `local` remains available for NAS and shared filesystems

Target provider roles:

| Provider | Intended Use |
|---|---|
| `rclone` | Recommended remote synchronization |
| `directory` | Cloud-client-managed local mirror |
| `local` | NAS / shared filesystem / local storage |

No provider should be removed solely because another becomes preferred.

---

# Concurrency and Data Safety

rclone synchronization must continue using **optimistic concurrency** rather than pretending to provide a universal distributed lock.

Example:

```text
Machine A reads revision A
Machine B pushes revision B
Machine A tries to push from revision A
                |
                +--> reject push
                     remote changed
```

Before rclone becomes the recommended provider, the project must verify:

1. stale-baseline pushes are rejected
2. remote `HEAD` is updated only after upload verification
3. failed transfers keep the previous valid revision
4. concurrent revisions are not silently deleted
5. local secrets never appear in transfer manifests
6. encrypted vault data remains encrypted in remote storage

---

# Secret Management

The current security model should remain conservative.

Planned direction:

- keep SSH private keys machine-local
- keep credentials out of Git
- use encrypted vault storage only for explicitly registered secrets
- avoid automatic secret capture
- require explicit restore destinations on each machine

Future work may improve age/SOPS integration, but convenience should not weaken the current trust model.

---

# Validation Strategy

Validation should remain separated from normal daily setup.

### Normal use

```nu
nu setup.nu
```

### Development and debugging

```nu
dotvalidate
dottest --sandbox
```

### Release gate

A release should require:

- project validation
- parser/module validation
- sandbox regression tests
- security tests
- release manifest generation
- checksum verification

Real-machine testing remains important because static validation cannot replace Windows/macOS/Linux integration testing.

---

# 1.0.0 Readiness Criteria

Initial-setup should reach 1.0 only after the following workflows are consistently reliable.

## Clean Installation

```text
Fresh machine
    |
bootstrap
    |
setup
    |
private configuration restored
    |
audit passes
```

## Repeated Setup

Running setup multiple times should:

- preserve existing user data
- avoid duplicate configuration
- skip already completed work where appropriate
- detect unexpected changes before overwriting them

## Recovery

The project must reliably support:

- transaction resume
- local configuration backup
- snapshot restore
- rollback after partial failure
- conflict review before destructive synchronization

## Cross-Platform

The core workflow should be verified on:

- Windows
- macOS
- Linux

Windows should remain a first-class target rather than relying on WSL-only behavior.

## Documentation

Before 1.0:

- README stays short and task-oriented
- CHANGELOG contains release history
- ROADMAP contains future architecture
- troubleshooting covers only recurring real-world problems

---

## Beyond 1.0

Possible future work, only if it provides clear practical value:

- improved lock metadata and stale-lock diagnostics
- stronger provider health reporting
- optional machine overlay tooling
- improved encrypted secret workflows
- safer self-update and rollback
- additional package-manager adapters

The priority after 1.0 should remain **reliability over feature count**.
