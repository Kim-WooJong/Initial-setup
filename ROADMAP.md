# Initial-setup Roadmap

## 0.13.x — Cargo runtime and stabilization

Implemented in 0.13.0: crates.io stable/non-yanked selection, exact Cargo builds,
side-by-side installation, cached reuse, native seed bootstrap, failure-before-sync
and cross-minor project version comparison. Existing private schema remains 5.

Release validation still needs real Cargo/compiler and Windows/macOS/Linux
integration evidence. Authoring verification for 0.13.0 covers the POSIX native
helper with mocked tools and static/artifact checks, not a live Nushell build.
Next work: test cold builds, unchanged-version reuse, failed compiler/network,
Windows executable-in-use handling, and the 0.12-to-0.13 command refresh path.
Keep normal setup free of repository-wide scans. Update checks run when commands
run, not as a background service. New upstream stable versions can still introduce
incompatibilities: document and test them instead of suppressing errors.

## 0.13.2 — explicit cloud mirror import

Implemented in source: optional dotcloud review/approval, local-only target, separate
plan/backup journal state, explicit activation, guarded dotpull, push/auto/prune
blockers and recovery. This is not a server-freshness API or an exact deleting mirror.
Private schema remains 5; directory remains the default provider.

Pending validation: execute the 26 authored Rust tests and Nu integration fixtures
with a real toolchain; then verify native Windows/macOS/Linux file semantics, cloud
placeholders, interrupted operations and protected live application. The initial
published source has no generated Cargo.lock; pin/review dependencies with a real
Cargo resolver before treating builds as reproducible across machines.

## rclone migration (planned; directory stays default)

| Phase | Work | Acceptance criteria |
|---|---|---|
| Read-only probe | Inspect an existing remote without writes. | Clear authentication/list/read failures; a read does not prove write permission. |
| Shadow store | Copy reviewed snapshots into a separate test store. | Round-trip inventory/SHA-256 match; production configuration is unchanged. |
| Explicit promotion | Opt into rclone as primary. | Interrupted transfers, stale baselines, Unicode paths and two-writer races tested on all platforms. |
| Retained fallback | Keep directory/local providers. | User-approved fallback cannot silently overwrite a newer store. |

Check expected revision, upload an immutable revision, verify contents, publish
HEAD last, then record the baseline. These are optimistic checks, not universal
compare-and-swap. Failures around HEAD may be ambiguous: read back and reconcile;
retain competing revisions. No unreviewed plaintext credentials in payloads.

## 1.0 readiness

Require repeatable clean install, repeated setup, conflict rejection, backup,
resume and rollback results on native Windows, macOS and Linux. Review the older
auto-sync scheduler lock: elapsed time alone must not authorize deletion.
Keep README short, history in CHANGELOG and plans here. No docs/ or .github/ tree.
