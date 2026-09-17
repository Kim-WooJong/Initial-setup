# Changelog

## 0.15.0

- Hardened Starship setup on Windows, Linux, and macOS. A PATH-visible executable is no longer accepted until both `starship --version` and `starship init nu` succeed.
- Added candidate discovery for PATH, Cargo, user-local, WinGet, and Scoop locations so a stale PATH entry cannot hide a healthy installation.
- Capture and print the actual `starship init nu` exit code and stderr instead of replacing the root cause with a generic setup error.
- Preserve the existing Nushell Starship autoload until a complete new init script has been generated successfully.
- Treat Starship as optional consistently: a broken prompt integration warns and setup continues instead of aborting the entire machine setup.
- On Windows, an unhealthy WinGet installation is offered an upgrade attempt before falling back to Cargo.

## 0.14.2

- Restored normal `nu setup.nu` behavior: startup blocks only on files required to execute safely, then continues to the existing configuration review/diff flow.
- Release-manifest drift is advisory in `--diagnose` and strict only in `--check`/the verification suite.
- Replaced the ambiguous diagnostic `read_only` field with `diagnostic_only` and `setup_blocked`; diagnostics no longer imply a synchronization policy.
- Removed the obsolete `install.sh`. Linux/macOS systems without Nushell use `bash bootstrap.sh`.
- Regenerated the release manifest so removed files cannot cause a false `MISSING_OR_NONREGULAR` startup failure.

## 0.14.1

- Restored `nu setup.nu` as the canonical Windows/Linux/macOS setup entry point.
- Added automatic prerequisite routing from `setup.nu` when Nu, Git, or chezmoi is not ready.
- Kept `install.sh` only as a fallback for machines without Nushell.
- Reused a compatible existing Nushell on Windows instead of rebuilding it unnecessarily.
- Converted maintained Markdown documentation to English and consolidated long-lived guidance into the wiki.
- Removed version-specific audit, migration, and testing documents from the release.

## [0.14.0] - 2026-09-18

- Promoted Linux to a first-class quick-start target with `sh install.sh`, automatic workstation/server profile selection (WSL defaults to server), and script-relative entrypoint routing.
- Added apt/dnf/pacman/zypper/apk support alignment, root-aware privilege handling, Debian `fdfind`/`batcat` shims, and a machine-local PATH bridge for `~/.local/bin`, Cargo and Juliaup.
- Added pinned official Nushell release binaries as the fast POSIX bootstrap path with SHA-256 verification; Cargo compilation remains the fallback.
- Made Linux auto-sync tolerant of WSL/containers without a working `systemctl --user`; manual `dotsync` remains available and `dotdoctor` reports scheduler state.
- Changed Linux Starship bootstrap to prefer the user-local official installer before Cargo compilation.
- Added offline POSIX one-command quick-start, official-release selector, and Cargo-selector tests; integrated documentation coverage into verification.
- Added a Wiki under `docs/wiki/` covering installation, feature roles, architecture, profiles, all exported commands, synchronization, Cloud-wins, recovery, troubleshooting and internal components.
- Private schema remains 5; no automatic destructive migration is introduced.

## 0.13.3

- Diagnose missing/mixed release files before setup; provide a flat-root ZIP and
  standalone cwd/project-root/runtime diagnostics without network/config writes.
- Preserve existing `dotpreflight --diff`; new diagnostics live separately.
- Use the current Nu executable for child invocations; align native seed minimum
  at 0.106.1 and keep compatible read-only work available without registry access.
- Repair active cloud-wins command-refresh recovery snapshots across checkout moves;
  preserve backups and refuse unrelated machine-context edits.
- Read compatible 0.13.2 format-2 recovery journals after upgrades; require fresh
  current-version plans for new applies.
- Reject empty-directory namespace collisions; harden file observation, bounded
  JSON reading, target-storage preflight and copied build-input verification.
- Validate run IDs, write checkpoints atomically, retain primary errors on cleanup.
- Stop synchronization after failed capture; propagate incomplete environment capture/restore.
- Add per-stage verification reports, explicit incomplete/blocked states, optional
  seed matrix tests, four Nu regression suites and ten Rust regression cases.
- Actual authoring checks: POSIX bootstrap mocks, shell syntax, native lock cases,
  static/reference checks and archive/patch audits. Nu/Rust/Windows/macOS/live Proton
  runtime execution was unavailable in that build environment. Schema remains 5.

## 0.13.2

- Integrate optional `dotcloud` into the uploaded 0.13.1 project; keep private schema 5 and existing directory/local/rclone paths.
- Add Rust cloudwins format-2 plan/apply/verify/ready/status/rollback with separate local state, whole-inventory SHA-256 checks, explicit plan/run confirmations, non-deleting overlay, verified staging/backups and write-ahead recovery.
- Read-only previews do not create the target or overwrite payloads; plans and operation leases may write local control metadata. Cloud mirror stability is not proof of server freshness.
- Add preview-first configure/activate/deactivate, saved machine policy, interruption-safe fail-closed activation, push/backend/setup blockers, disabled auto worker and configured/explicit prune rejection. Normal dotpull requires an approved local workspace and retains existing protected-file/backup checks.
- Build the optional helper in source-hash keyed local cache, retaining a first-build Cargo.lock and binary receipt. No generated/pinned release Cargo.lock or compiled binary is included.
- Add 26 authored Rust tests, isolated Nu control/engine regressions and explicit verify-0.13.2.nu; retain old release gates and add required cloud engine tests. Release version bumps also update the Rust package version.
- Preserve offline local recovery through the existing validated runtime cache; no cloud-source reads are required by the rollback engine.
- Add root-level usage/migration/testing notes, retaining the no docs/ or .github/ repository policy.
- Verification disclosure: POSIX mocked bootstrap tests and static/artifact checks only in the authoring environment. Rust compile/tests, Nu parser/runtime and native Windows/macOS/Proton integration were not executed here.



## [0.13.1] - 2026-09-17

- Fixed `nu-runtime.nu` assigning a record into a variable inferred as `nothing` by declaring the selector as `any`.
- Fixed the OneDrive policy helper argument path so immutable arguments are captured safely by `do { ... } | complete`.
- Administrator-required OneDrive policy exit code 11 remains a warning and no longer aborts normal setup.
- Protected-file conflicts during private-authoritative setup now show the actual diff and ask whether to keep the local file, overwrite it from the private source, or cancel.
- Local protected-file choices are backed up before apply and restored afterward, including when `chezmoi apply` fails.
- Fixed the same mutable-capture pattern in the edit-managed regression test.

## [0.13.0] - 2026-09-17

- Replaced official-release binary downloads with Cargo builds of the newest stable, non-yanked `nu` found in the official crates.io sparse index. Build an exact version with `--locked --bin nu --registry crates-io`; never silently select an older MSRV-compatible crate.
- Use isolated Cargo installation roots under `CARGO_HOME/initial-setup/nu`, verify version/startup and Cargo tracking, and reuse checksum-checked receipts. Preserve running executables, older builds and old 0.12 downloaded caches. Shared Cargo build cache replaces redundant project update locks.
- Prepare stable Rust through Rustup for new builds without changing an existing default/project override; system Rust must meet the selected MSRV. Build prerequisites remain explicit. Cargo/network/verification failures stop sync.
- Native Windows/POSIX bootstrap can compile the first Nu without an existing Nu parser. Removed Nu binary extractors and WinGet/Homebrew/extra-repository Nu installation paths. Preview does not install dependencies or runtimes.
- Added `dotnuupdate --shell`; session reuse is Cargo-specific and limited to child operations. Idle scheduler cycles do not query/build; actual push/pull checks the registry. No always-running updater is added.
- Fixed the self-updater's 0.12-only manifest and patch-number comparison. New code compares complete stable versions; first migration from an old 0.12 updater must use a full ZIP/patch. Existing setup run-version checks and schema 5 remain.
- Nushell uses the Cargo freshness policy, while toolchain lock-current preserves only the parser minimum for Nu. Rust/Julia version locking stays independent.
- Replaced binary-asset tests with registry-selection, exact Cargo argv, cache integrity, failed-build preservation and launcher regression fixtures. Native POSIX preparation tests (10 mock-tool scenarios) ran successfully; full Nu/Cargo and Windows/macOS integration was not executed because those runtimes/network were unavailable in the authoring environment.
- README/ROADMAP remain concise and English. No docs/, .github/, secret migration, forced push or baseline acknowledgement added.

## [0.12.32] - 2026-09-17

- Fixed the text-case adapter's parse-time selector: replaced regex matching with membership in a literal list of all pre-0.114 minor versions (0 through 113). No numeric conversion or runtime command is used in the selector.
- Extended the real-module constant/import regression to every pre-0.114 minor and boundary/prerelease/future-version inputs. Added an optional `syntax-self-test.nu --case-only` path for local, offline diagnostics.
- Latest-stable runtime preparation, checksum checks, sync/vault/lock behavior and optional startup validation are unchanged. No docs/ or .github/ added.
- Authoring checks: literal-table coverage, source diff and release artifacts verified. Actual Nushell/Windows execution was not run: no Nu executable was available and the official binary download could not be obtained.

## [0.12.31] - 2026-09-17

- Fixed the runtime bootstrap comparator using an unparenthesized negative return value that Nushell parsed as an unknown `-1` flag. It now returns `(-1)`.
- Added focused integer/order regression cases for older, equal and newer major/minor/patch versions, and a parser-acceptance fixture for the negative return expression.
- No change to update selection, checksum verification, sync safety checks or normal-startup validation policy. No docs/ or .github/ directory added.
- Authoring verification: targeted source scan and artifact checks only. Nushell regressions were not run (runtime unavailable; GitHub DNS resolution failed).

## [0.12.30] - 2026-09-17

- Setup and explicit push/pull now check the latest official stable Nushell release before loading business modules or acquiring operation locks. Nested scripts reuse the selected executable and child PATH.
- Install older runtimes side by side in user-local storage from official GitHub release assets; require their SHA-256 digest, exact executable version and isolated execution check. Do not overwrite a running or package-managed nu binary.
- Added runtime-only update/check commands and a guarded compatibility launcher. Network, metadata, checksum or install failure stops synchronization; no silent outdated-runtime fallback.
- Idle automatic-sync cycles use a compatible current/cached runtime, while actual push/pull still checks latest stable. No per-minute release polling when nothing needs syncing.
- Correctly select the legacy case adapter for every 0.x minor below 114, including 0.108. No non-const numeric conversion is used.
- Bootstrap uses an existing Nu only as a seed, prepares/rechecks the selected runtime and preserves argument forwarding. Ancient seeds require native bootstrap/PATH repair before using the Nu launcher.
- Added offline release-selection/launcher regressions and POSIX/Windows single-binary extractors. Explicit validation/release gates remain; normal setup does not scan the whole repository.
- Authoring verification: POSIX extractor behavior, shell syntax, static contracts and patch/artifact checks were run. Nushell and Windows PowerShell integration tests were not run because these executables could not be obtained in the authoring environment.

## [0.12.29] - 2026-09-17

- Vault initialization and restore no longer load sync-provider configuration; capture/migration retain their existing revision and locking guards.
- Added `dotvault init --check` for read-only local path and age/age-keygen prerequisite checks. No package is installed automatically.
- Vault failures print the original rendered diagnostic and the initialization stage, release both held locks, and exit nonzero without another misleading footer error.
- Decode public-key/path command output strictly as UTF-8; optional rclone-path discovery failure no longer invalidates a usable identity.
- Protect a staged policy before committing it, reuse an existing identity on retry, and never overwrite an existing vault policy.
- Added isolated vault-init regressions to the explicit sandbox workflow. Runtime tests were authored but could not be run in the authoring environment (Nushell unavailable).

## [0.12.28] - 2026-09-17

- Separate managed editor commands from synchronization: local editing is the default, with explicit --push and --path options.
- Delegate editor behavior to edit-managed.nu, check source-path exit/empty output, avoid implicit pull, and reject template capture that re-add cannot perform.
- Add a local-only refresh-commands.nu tool with backups, command-module checksum verification, tools_root update and lock cleanup. Restart the shell after refreshing.
- Show both baseline/current tree hashes and independent export-audit blockers in backend status; matching revisions alone never imply export readiness.
- Normalize sync errors to known text fields, preserve the real cause when auxiliary logging fails, and recognize failure envelopes in tables.
- Use the current Nushell executable on the direct push/transport entry paths.
- Add isolated local-editor/refresh regressions; retain the optional normal-setup validation policy.
- Keep README/ROADMAP concise and English; no docs directory or .github directory is added.
- Verification limit: this patch was statically reviewed and packaged, but its Nushell/Windows/chezmoi integration tests were not executed in the authoring environment.

## [0.12.27] - 2026-09-17

- Stabilized directory-provider concurrency checks by requiring consecutive identical cloud-mirror snapshots before comparing against the saved baseline.
- dotbackend status and push now use the same stable provider-head logic; real mismatches report baseline/current revisions and the data root.
- Removed the docs/ directory and generated test-report files; README, ROADMAP, and CHANGELOG remain the maintained documentation.






## [0.12.26] - 2026-09-17

- Fixed `dotnu`, `dotenv`, `dotnvim`, `dotwezterm`, and `dotstarship` editing the private chezmoi source before synchronization.
- Managed editor commands now edit the live/local target first; `dotpush` verifies the provider baseline before `chezmoi re-add` captures the local change.
- This prevents a user's own edit from being misclassified as a concurrent private-source change.
- Simplified `sync-transport.nu` failure reporting so the original synchronization error is printed immediately and is no longer re-rendered through a typed message conversion.
- If synchronization fails after editing, the local edit is preserved.

## [0.12.25] - 2026-09-17

- Rewrote README as a concise quick-start and daily-use guide.
- Moved detailed version history to CHANGELOG only.
- Added ROADMAP.md with the staged rclone-provider migration plan and 1.0 stability criteria.
- No runtime behavior or schema changes.

## [0.12.24] - 2026-09-17

- Removed the redundant machine-local provider lock for the `directory` backend.
- Same-machine serialization now relies only on the existing global `operation.lock`.
- Cross-machine directory-provider conflicts continue to use revision/tree fingerprint checks.
- Obsolete `provider-*.lock` files from v0.12.21-v0.12.23 are ignored and reported diagnostically; they are not probed or deleted automatically.
- True shared-filesystem/NAS (`local`) providers still retain their shared cooperative lock.

## [0.12.23] - 2026-09-17

- Removed setup-side error-object-to-string conversion from stage and final failure handling.
- Original caught errors are printed immediately; setup then returns only a fixed short failure message.
- Lock-cleanup failures are printed separately and no longer participate in message aggregation or type conversion.
- This change is intentionally limited to `setup.nu`; sync/provider behavior is unchanged.

## [0.12.22] - 2026-09-17

- Removed setup error-message aggregation through `str join`; the original operation failure is now rethrown directly.
- Cleanup failures are printed as secondary warnings when another setup error already exists.
- This prevents the teardown/error-reporting path from masking the real failure with a type mismatch.





## [0.12.21] - 2026-09-17

- Removed the cloud-synchronized write lock from the `directory` backend.
- Directory/cloud-mirror providers now use a machine-local provider lock under `~/.config/dotfiles/locks/`.
- Cross-machine protection for directory providers remains optimistic: saved revision/tree fingerprints are checked before writes.
- Existing `.initial-setup-write.lock` entries in cloud folders are treated as legacy diagnostics only; they are never probed or deleted automatically.
- True `local` shared-filesystem/NAS providers keep the cooperative lock in the shared filesystem.
- Updated `dotbackend status`, `lock-status.nu`, security tests, and documentation for the new lock model.

## [0.12.20] - 2026-09-17

- Fixed setup failure propagation that assumed every captured value was an error record with `.msg`.
- Added explicit failure envelopes and normalized error rendering so normal pipeline output cannot be mistaken for an operation failure.
- Applied the same guarded-failure pattern to synchronization, rollback, vault, resolver, and safe-upgrade paths.
- Removed repository-wide syntax/project validation from normal `nu setup.nu` and bootstrap startup.
- Added opt-in `nu setup.nu --validate`, `bootstrap.sh --validate`, and `bootstrap.ps1 -Validate`.
- Full syntax/project validation remains available through `dotvalidate`, `dottest --sandbox`, and the release gate.

## [0.12.19] - 2026-09-17

- Fixed Windows lock and secret-ACL helpers being blocked by restrictive PowerShell execution policy.
- Project-owned `.ps1` helpers now use `-ExecutionPolicy Bypass` only for the spawned PowerShell process; no CurrentUser or LocalMachine policy is modified.
- Added validation preventing new project-owned `-File` PowerShell calls from omitting the process-scoped override.
- Existing lock ownership, collision detection, token verification, and protected-file behavior are unchanged.

## [0.12.18] - 2026-09-17

### Fixed
- Normalize human-readable subprocess diagnostic streams before string operations.
  `complete` may produce binary stderr, so `default ""` was not a text conversion.
  Fix the secondary `str trim` failure in `lock-result-message`.
- Add a dependency-free `process-output.nu` helper: text/null, UTF-8, UTF-8 BOM,
  UTF-16 BOM, an explicit legacy encoding hint, and a marked ASCII-preserving
  fallback. Do not guess a Windows code page or dump raw binary tokens.
- Use the same helper in the failure messages for toolchains, rclone, conflicts,
  auto-sync, validation, updater logs and diagnostic assertions in tests. Leave
  configuration, crypto payloads, fingerprint and other machine-data parsing alone.
- Write Windows lock-helper-owned stderr as UTF-8 through its process-local
  `Console.Error` writer. Do not change the shared console code page or policy.
- Keep the helper's exit code, collision marker check and token redaction. No
  lock is deleted, stolen, retried or treated as successful by this change.

### Tests and limits
- Add literal byte fixtures and an optional raw child-process stderr test; wire
  both into the existing sandbox gate. Runtime Nu/PowerShell tests are authored,
  not executed in the release container. See docs/TEST-REPORT-0.12.18.md.
- Keep schema 5 and the removal of `.github`.

## [0.12.17] - 2026-09-17

### Fixed
- Rewrite the two lock-result messages as lists joined with an empty separator.
  Remove six physical lines beginning with `+` that passed syntax validation
  but violated the existing repository formatting guard.
- Keep the formatting rule active. Its diagnostics now include a 1-based
  physical line number and explicitly identify a repository-format failure.
- Preserve message text, token redaction, lock lifecycle and schema 5.

### Regression checks
- Extend the existing lock test with message-separator, empty-stderr and
  source-format regressions. These Nu tests were authored, not executed here.
- Execute a repository-wide equivalent of all ten operator-leading line guards
  and static comparisons of old/new message fragments. Verify patch and release
  inventories. See the release-specific test report for execution boundaries.

## [0.12.16] - 2026-09-17

### Fixed
- Stop mapping every nonzero lock-helper exit to "Operation is locked". Preserve
  the helper diagnostic and distinguish existing-file collisions, I/O/policy
  failures, missing executables, and post-create token verification failures.
- Windows: report CreateNew file-exists HRESULTs separately from access, path,
  write and flush errors. Keep execution policy unchanged and redact tokens.
- POSIX: use a tested helper with exclusive creation, a retained descriptor,
  explicit Bash/Dash open-failure handling, and distinct collision/I/O exits.
- Preserve the raw-token lock format, lease checks and owner-only release. Never
  automatically remove an old, empty, or apparently stale lock.

### Diagnostics and testing
- Add read-only `scripts/lock-status.nu` with optional, isolated `--probe` of
  create/verify/release in the lock directory. No live lock is deleted.
- Add `scripts/lock-test.nu` and connect it to the existing sandbox self-test.
- Actual Linux helper tests: 20 passed, including 32 competing processes with
  one winner, permissions under an unprivileged UID, and Bash/Dash behavior.
- Nushell and PowerShell were not available here. No actual Nu parser, new Nu
  tests, or Windows integration pass is claimed. See the versioned test report.

## [0.12.15] - 2026-09-17

### Fixed
- Remove `into int` from the case adapter's parse-time selector. Use primitive
  string/list/boolean operations over the documented supported legacy window;
  retain parse-time imports and native Unicode case conversion.
- Accept Nu 0.114.x in the modern side of `check-compatibility.nu`; previously
  the matrix demanded 0.115+ even though the case command boundary is 0.114.

### Validation
- Audit all 100 Nu sources and 147 production constant declarations. No further
  conversion call in a constant initializer was found by lexical inspection.
- Add 15 synthetic-version const/import fixtures using the actual source,
  deliberately invalid inactive adapters, plus an actual-version import smoke
  check using the current interpreter and native adapters.
- Add a negative non-const command fixture and verify error report continuation.
- These Nushell tests were authored, NOT executed in the container. The complete
  evidence/limitations are in `docs/TEST-REPORT-0.12.15.md`.
- Keep schema 5, existing installer/sync/security policies and .github removal.

## [0.12.14] - 2026-09-17

### Fixed
- Rename the private plan helper `run` to `run-plan-script` and update all eight
  calls; never shadow Nushell's parser keyword. Plan children use the current
  executable and no user config.
- Replace nine shared/test case-conversion calls with a parse-time selected
  adapter. Nu >=0.114 uses lowercase/uppercase; older supported Nu uses the
  legacy names without loading them on new Nu. Preserve native Unicode behavior
  and the 0.109.1 minimum rather than simply reversing the previous rename.
- Retain stderr warnings from successful syntax/startup checks instead of
  silently reporting only `[ok]`.

### Validation
- Add explicit inactive-adapter reporting and JSON format 3 fields; no inactive
  file is marked as tested. Add optional `--deny-warnings`.
- Add keyword definition/alias/export, warning capture, case dispatch, Unicode,
  empty-string and safe-helper-name regression cases.
- Add `check-compatibility.nu` for an explicit installed old/new interpreter
  matrix. No binary downloads, package manager changes or live cloud operations.
- Preserve schema 5, .github removal, and existing configuration/sync policies.
- Actual Nushell execution was not available in the authoring container. Static
  and packaging evidence, plus unexecuted-test boundaries, are documented in
  `docs/TEST-REPORT-0.12.14.md`.

## [0.12.13] - 2026-09-17

### Fixed
- Parenthesize both toolchain comparison values passed to `return`; prevent
  `Extra positional argument` during parsing, including through module imports.
- Replace seven 0.114.0-only case-conversion command references with the names
  available on the documented Nushell 0.109.1 baseline. Newer Nu can warn about
  deprecation without rejecting the source.
- Stop rejecting those baseline-compatible names in the structural validator.
- Scope the fingerprint ordering contract to the target inspection operations;
  an earlier home-path helper must not cause a false ordering failure.
- Treat checkout paths literally when collecting validation sources/templates,
  rather than interpolating directory names into a glob pattern.

### Validation
- Add a standalone per-file parser worker accepting target paths as argv values;
  keep `nu-check --debug` and module parsing enabled.
- Collect startup/import diagnostics even after target parser failure. JSON
  report format 2 retains existing result fields and adds per-stage diagnostics.
- Add standalone temporary-fixture tests for valid/invalid returns, failed imports,
  continued scanning, report generation and bracketed/quoted/Unicode paths.
- Add real toolchain comparison fixtures and case-conversion regression checks.
- Preserve schema 5, the rclone dependency installer, secrets/sync policy and
  `.github` removal. No real Nushell or platform integration execution was possible
  in the authoring container; see `docs/TEST-REPORT-0.12.13.md`.


## [0.12.12] - 2026-09-17

### Added
- Ensure rclone is present and `rclone version` succeeds during setup, independent
  of optional CLI/config-capture features; recheck the dependency on resume.
- Add `scripts/install-rclone.nu` with read-only `--check` and `--dry-run` modes.
- Use existing WinGet, Homebrew, apt-get, dnf, pacman, zypper or apk; use sudo only
  for non-root Linux installs. Refresh the apt index before first installation.
- Preserve a working binary/version, fail on a broken one, and fail closed on
  ambiguous WinGet registration or a nonzero installer exit. No download-script,
  package-manager installation, cloud login, mount driver, or upgrade fallback.
- Refresh process PATH after install (including the setup parent), preserving its
  existing precedence; consider Windows registered PATH and WinGet links.
- Keep rclone in package manifests/planner even when optional CLI tools are off;
  explicit plan application also ensures the dependency after consent/preflight.
- Add mocked offline installer regressions to the local sandbox/release gate.

### Compatibility and validation
- Preserve schema 5, existing configuration/secret/sync policies, and `.github` removal.
- Tests in the authoring container are static/Bash/patch/hash only. Nushell,
  PowerShell and real package-manager installation tests were not runnable here.
  See `docs/TEST-REPORT-0.12.12.md` for the exact validation boundary.

## [0.12.11] - 2026-09-16

### Fixed
- Freeze the final setup policy before both apply-stage closures, avoiding Nushell mutable captures.
- Move mutable lock/recovery-handle inspection outside `catch` in setup, sync transport, conflict resolution, snapshot rollback, vault and safe upgrade.
- Attempt local and shared lock releases independently; preserve the original operation error.
- Preserve Rust/Julia version punctuation, prereleases, dated nightly channels and Julia's default marker; handle empty/malformed tool output.
- Propagate Rust/Julia install/default command failures rather than treating the stage as successful.
- Generate unique, high-resolution local backup names and validate all backup payload paths/presence before changing live files.
- Do not roll back an already committed secret merely because recovery-directory deletion failed.
- Isolate Windows AppData and cache directories in self-tests and candidate-validation HOME environments.

### Validation
- Add standalone `scripts/validate-syntax.nu`: isolated per-file parser/startup checks, aggregate diagnostics and optional JSON report.
- Run aggregate checks at the beginning of the project validator and before bootstraps launch setup.
- Add `scripts/regression-test.nu` for capture, version parsing, failure-path lock cleanup and backup regressions; integrate it with sandbox/release tests.
- Keep schema 5 and existing configuration policies; do not restore `.github`.
- Authoring-container validation remains static/Bash/patch/hash only; Nushell and platform integration tests were not executable here.


## [0.12.10] - 2026-09-16

This package bundles the planned 0.12.7–0.12.10 development work; separate
intermediate release artifacts were not produced.

- 0.12.7 scope: add native age secret capture/restore with machine-local allowlists,
  local identities, owner-restricted paths, and explicit verified legacy rclone migration.
- 0.12.8 scope: add directory/local/rclone providers and immutable revision stores,
  staged download, manifest validation, and rclone download-based upload verification.
- 0.12.9 scope: add provider baselines before re-add/capture, HEAD pre/post checks,
  shared local operation locks, planner revision checks, and explicit reconciliation.
- 0.12.10 scope: add manifest/commit-pinned staged self-update, test-before-promotion,
  retained previous tools, and edit-preserving fallback/manual rollback.
- Preserve default directory operation, schema 5, existing profiles/toolchain locks,
  protected targets, planner, and .github removal. Encrypted features stay opt-in.
- Refuse plaintext rclone publication; old cloud versions and backups are not erased.
- Stop silently ignoring automatic push rejection and external rollback failures.
- Guard selected merges; remove the old blanket force-apply after merge-all.
- Keep unpublished explicit-provider workspace edits dirty after setup/merge.
- Harmonize sandbox HOME guards across standalone helpers, fix example NUON loading,
  and use text-safe version loading instead of decoding an already-decoded string.
- Add isolated security regression tests, release inventory generation, a local
  dependency-required release gate, and a migration/limitations guide.
- Validation limitation: Nushell/age/rclone/PowerShell runtime tests were not executed
  in this build environment. See TEST-REPORT.md; static checks are not parser tests.




## [0.12.6] - 2026-09-16

- Automatically configures Neovim diff mode as chezmoi's three-way merge tool when no custom merge section exists.
- Adds `dotmergecfg` for merge-tool inspection/application while preserving custom configuration.

## [0.12.5] - 2026-09-16

- Adds `toolchains/lock.nuon`, `dottoolchain`, exact lock capture, active Rust/Julia channel drift reporting, and Rust/Julia lock application.
- Planner and verification include toolchain drift.

## [0.12.4] - 2026-09-16

- Adds layered profiles: common -> OS -> role -> repository machine -> machine-local overlay.
- Bumps machine config schema to 5 and adds the 4 -> 5 migration.

## [0.12.3] - 2026-09-16

- Adds `dotplan`, `dotapply`, and `dotverify` desired-state workflow.
- Saved plans combine package state, chezmoi status, protected-file conflicts, and toolchain drift.

## [0.12.2] - 2026-09-16

- Transaction rollback now restores local state and the private-source snapshot independently, including shared sync metadata.
- Failed rollback attempts are recorded as `rollback-failed` instead of silently retaining the previous run status.
- Sandbox tests now verify manifest-v2 local backup/restore behavior, including removal of files that were absent before a transaction.

### Three-way conflict resolution and protected files
- Expanded `dotresolve` with per-file `chezmoi merge`, `merge-all`, local -> private publishing, guarded private -> local pulls, and explicit per-file protected overrides.
- Added `defaults/conflict-policy.nuon` with `.ssh/config`, `.gitconfig`, and `.config/git/config` protected by default.
- Added machine-local conflict-policy override support at `~/.config/dotfiles/conflict-policy.nuon`.
- `sync-down.nu` and setup private-authoritative applies now stop before overwriting protected files that differ from the private source.
- Protected policy entries that are not managed by the active chezmoi source are ignored instead of causing false conflicts.

## [0.12.1] - 2026-09-16

### Run history and recoverable configuration transactions
- Added `dotrun --list`, `--status`, `--logs`, `--resume`, and `--rollback`.
- Setup runs now write persistent state and stage events under `~/.config/dotfiles/runs/`.
- Transaction backups include both live local configuration and a private-source snapshot when available.
- Rollback restores the local configuration first, then the matching private snapshot; package-manager changes are intentionally not uninstalled.
- Local backup manifests now record previously-missing targets so rollback can remove files created by a failed transaction.

## [0.12.0] - 2026-09-16

### Checkpoint and resume
- Every setup execution receives a Run ID and checkpoint state.
- Script stages and direct configuration-apply stages record running/success/failure state.
- Added `nu setup.nu --resume [--run-id ID]`; completed stages are skipped and the failed/interrupted stage is retried.
- Resolved profile, data root, synchronization direction, and auto-sync setting are retained in run state so a resume uses the same setup context.
- Setup prints the exact resume command when a checkpointed stage fails.




## [0.11.4] - 2026-09-16

### Fail-fast validation
- `nu setup.nu` now runs the repository validator before any setup mutation.
- Added `dotvalidate` as a first-class command for manual project validation.
- Existing `nu-check` coverage is retained for every Nushell source and module.
- `dotrelease` now requires both project validation and the sandbox smoke test
  before creating a release commit/tag.

### Isolated sandbox smoke testing
- Added `dottest --sandbox` and `scripts/self-test.nu`.
- Sandbox tests use temporary HOME/XDG config/data/state directories plus a fake
  private source, without modifying the user's real machine configuration.
- Smoke tests cover local/private source detection, `push-local` dry-run,
  `pull-private` dry-run, and dry-run side-effect detection.
- `dottest --sandbox --keep` preserves the temporary tree for inspection.
- Added guarded `INITIAL_SETUP_TEST_MODE=1` + `INITIAL_SETUP_HOME_OVERRIDE`
  support to shared setup/core policy helpers strictly for isolated tests.

### Documentation cleanup
- Replaced the obsolete GitHub Actions section after `.github` removal with local
  validation and sandbox-test documentation.

## [0.11.3] - 2026-09-16

- Fixed a Nushell parse error in `scripts/capture-tool-state.nu` where the `lazygit` and `rclone` version checks were accidentally merged into one call.
- Added separate valid `command-version` entries for `lazygit` and `rclone`.
- No configuration-policy behavior changes from v0.11.2.

## [0.11.2] - 2026-09-16

### Bidirectional setup reconciliation
- Added `push-local` and `pull-private` as explicit synchronization policies.
- `nu setup.nu` now offers a first-class "Save local changes to private drive"
  option when local and private configuration coexist.
- Review mode now shows `chezmoi status`/`diff` and then returns to an
  Initial-setup direction menu instead of falling through to chezmoi's raw
  overwrite prompt.
- Existing `keep-local`/`keep-private` policy names remain compatibility aliases.

### Conflict-resolution commands
- Added `dotresolve` for an interactive local-vs-private reconciliation workflow.
- Added `dotpull --force` for explicit private-authoritative pulls.
- Added `dotpull --backup` to create a local configuration backup before an
  explicit private-authoritative pull.
- Added `--force` support to `scripts/sync-down.nu` for guarded internal use.

### Cleanup
- Removed the obsolete `.github/workflows/ci.yml` requirement from the project
  validator after the `.github` directory was removed in v0.11.1.

## [0.11.1] - 2026-09-16

- Removed the `.github` directory and GitHub-specific repository metadata/workflows.
- No runtime behavior changes.

## 0.11.0

### First-run configuration policy
- Replaced the first-run overwrite-centric flow with an explicit six-choice
  source-selection menu: review, keep local, keep private, backup then keep
  private, preview, or cancel.
- Added `--config-policy` for scripted/non-interactive selection.
- `--mode initial` remains supported and maps to the local-authoritative path.
- `--mode existing` uses interactive review on a first run instead of immediately
  forcing a destination overwrite decision.
- Added state-aware recommendations based on whether local/private configuration
  is detected.
- Added private-source validation so destructive private-authoritative policies
  cannot be selected when no private source exists.

### Safer chezmoi reconciliation
- `review` uses chezmoi interactive apply so managed changes can be inspected
  individually.
- `keep-local` explicitly updates existing source entries from the current
  machine instead of falling through to a confusing source overwrite prompt.
- `keep-private` explicitly applies the private source as authoritative.
- `preview` shows the setup plan plus chezmoi status/diff without applying setup
  changes.

### Local recovery and preflight
- Added `backup-local-config.nu` for machine-local live-configuration backups.
- Backups include editor/shell/terminal/Git/SSH-config/VS Code configuration but
  deliberately exclude SSH private keys and secret files.
- Added `dotlocalbackup` and guarded `dotlocalrestore`; restore is preview-only
  unless `--force` is provided.
- Added `dotpreflight` and `dotpreflight --diff` for managed-state inspection.
- `dotdoctor` now reports the count and newest local-configuration backup.
- Local backups follow `maintenance.snapshot_keep` retention.
- Added `backup-private`, which automatically creates a local backup before a
  forced private-source apply.

### Bootstrap and validation
- Added `--config-policy` passthrough to Windows, macOS, and Linux bootstrap
  entry points.
- Extended project validation for the new setup-policy module and recovery
  scripts.

## 0.10.0

### Declarative profiles and modular setup
- Moved workstation, laptop, server, and minimal profile defaults from
  `setup.nu` into composable `profiles/*.nuon` manifests.
- Added reusable `core.nu` and `profiles.nu` modules under `scripts/modules/`.
- Kept existing package manifests and chezmoi private-data architecture intact.

### Folder-specific Git identities
- Added machine-local `~/.config/dotfiles/git-identities.nuon`.
- Added conditional Git identity generation using `includeIf gitdir/i:` rules.
- Each identity can define folder paths, Git name/email, an optional signing key,
  and an optional SSH private-key path.
- Generated identity files live under `~/.config/git/identities/` and are never
  synchronized by Initial-setup.
- Added `dotgitids`, `dotgitids --edit`, and `dotgitids --apply`.
- Added a public example manifest at `templates/git-identities.nuon.example`.
- Added manifest validation for entry types, booleans, duplicate identity names,
  required folder paths, and generated Git-safe values.
- Kept normal identity/doctor checks read-only; the local manifest is created
  only by init/edit/apply flows.

### SSH key recovery and diagnostics
- Added SSH private-key discovery for conventional `id_*` keys and keys
  referenced by folder-specific Git identities.
- Missing `.pub` files are regenerated non-interactively when the private key
  is unencrypted. Encrypted keys are preserved and reported for manual recovery.
- Added `dotsshkeys` and `dotsshkeys --generate`.
- Integrated Git identity and SSH key checks into setup, doctor, repair, and the
  post-setup checklist.

### Validation and documentation
- Extended project validation to cover the new modules, scripts, profile
  manifests, and Git identity template.
- Updated README for the v0.10.0 architecture and commands.

## 0.9.10

### OneDrive upload exclusion policy
- Added Windows OneDrive upload exclusion policy management.
- Uses the official
  `HKLM\SOFTWARE\Policies\Microsoft\OneDrive\EnableODIgnoreListFromGPO`
  string-list policy.
- Manages:
  - `1 = *.log`
  - `2 = *.tmp`
  - `3 = *.cache`
  - `4 = *.bak`
- Preserves additional/unrelated values already present in the policy key.
- Does not force UAC elevation during normal setup.
- If administrator rights are required, setup warns and continues.
- Added `dotonedrive` for status and `dotonedrive --apply` for explicit apply.
- Added `dotdoctor` status/repair integration.

### Configuration schema
- Bumped machine-config schema to 4.
- Added `features.onedrive_ignore_uploads`.
- Defaults to enabled for workstation/laptop and disabled for server/minimal.

### Documentation
- README remains English-only.
- Documented Administrator-rights and OneDrive-restart requirements.

## 0.9.9

### rclone config synchronization
- Added synchronization of the active rclone configuration file only.
- Uses `rclone config file` to resolve the actual platform-specific config
  location instead of hard-coding Windows/macOS/Linux paths.
- Stores the private copy as `rclone/rclone.conf`.
- Initial/push workflows capture the local config.
- Existing/pull workflows restore the private config.
- Identical config files are skipped.
- Added `dotrclone`, `dotrclone --capture`, and `dotrclone --restore`.
- Added rclone config state to synchronization fingerprints, snapshots, and
  rollback.
- Does not install rclone and does not configure or invoke rclone mounts,
  services, drive letters, or VFS mount state.

### Configuration schema
- Bumped machine-config schema to 3.
- Added `features.rclone_config`, defaulting to `true`.

### Documentation
- README remains English-only.
- Added credential/security guidance for synchronized `rclone.conf`.

## 0.9.8

### Repository-wide Nushell syntax normalization
- Removed every physical Nushell source line beginning with `+`.
- Removed the remaining physical arithmetic continuation beginning with `*`.
- Fixed the reported `capture-vscode-extensions.nu` `Command '+' not found`
  failure and the same latent pattern across the rest of the project.
- Added project-wide validation rejecting physical Nushell lines beginning
  with `+`, `*`, or `/`.
- Existing regression checks for leading `and` / `or`, trailing Bash
  continuations, deprecated case-conversion commands, and version-specific
  home fields remain enabled.

### Documentation
- README remains English-only.
- Documented the cross-version Nushell physical-line syntax policy.

## 0.9.7

### Machine-local Nushell setup
- Added `~/.config/dotfiles/local.nu` for computer-specific Nushell setup.
- The file is created only when missing and is never overwritten by
  Initial-setup.
- Canonical Nushell config sources the machine-local file at shell startup.
- Added `dotlocal` for editing the machine-local setup.
- `dotdoctor` reports the file and `dotdoctor --fix` creates it only when
  missing.
- The file is excluded from private-cloud/chezmoi synchronization,
  synchronization fingerprints, snapshots, rollback, and public Git state.

### Documentation
- README remains English-only.
- Documented the machine-local setup contract and `dotlocal`.

## 0.9.6

### Hidden Windows auto-sync
- Windows `DotfilesAutoSync` no longer launches `nu.exe` directly.
- Added a machine-local `auto-sync-hidden.vbs` launcher under
  `~/.config/dotfiles/scheduler/`.
- Task Scheduler now invokes the launcher through
  `wscript.exe //B //Nologo`.
- The launcher starts Nushell with hidden window style and waits for each sync
  cycle to finish.
- Re-running setup replaces an older visible `DotfilesAutoSync` task in place.
- `dotdoctor` now reports whether the Windows hidden launcher exists.

### Scheduler safety
- Added project validation that prevents scheduled auto-sync scripts from
  containing Git pull/fetch/push/clone operations.
- Public Initial-setup repository updates remain explicit rather than periodic.

### Documentation
- README remains English-only.
- Documented the Windows hidden/background scheduler architecture.

## 0.9.5

### Missing-path fingerprint fix
- Fixed `sync-fingerprint.nu` passing `nothing` into `path type` when an
  optional managed path did not exist.
- Fingerprint targets now reject null/empty values before filesystem
  inspection.
- `path exists` is checked before `path expand` and `path type`.
- Missing managed files/directories are represented as `MISSING` fingerprint
  entries instead of aborting synchronization baseline generation.
- `target-entries` and `append-target` now accept optional path values safely.
- Added project validation for the path-existence guard ordering.

### Documentation
- README remains English-only.
- Documented missing-path fingerprint behavior.

## 0.9.4

### Synchronization fingerprint fix
- Fixed `sync-fingerprint.nu` string concatenation where a physical line
  beginning with `+` could be interpreted as an external command.
- Rewrote affected fingerprint strings as complete expressions.
- Explicitly converts variable filesystem patterns with `into glob`.
- Applied the same explicit glob conversion to the project validator.
- Added a regression check for physical `+` continuation lines in the
  synchronization fingerprint implementation.

### Documentation
- README remains English-only.
- Added the fingerprint compatibility note.

## 0.9.3

### Merge-first synchronization
- Added machine-config schema 2.
- Added `sync.prune_extras`, defaulting to `false`.
- VS Code extension synchronization installs missing extensions but preserves
  local-only extensions by default.
- Added `dotpull --prune` for explicit one-time strict reconciliation.
- Persistent strict reconciliation is available through
  `sync.prune_extras: true`.
- VS Code snippets merge file-by-file by default instead of deleting the
  destination snippets directory before copy.
- Settings and keybindings continue to overwrite the managed files.

### Incremental Rust restore
- Existing Rust toolchains are skipped instead of being reinstalled.
- Existing components and targets are skipped instead of being re-added.
- The default toolchain is changed only when it differs.
- New toolchains use the minimal profile before captured components are added.
- Extra local Rust toolchains/components/targets are preserved.

### Documentation
- README remains English-only.
- Documented merge-first synchronization and explicit prune behavior.

## 0.9.2

### Idempotent Windows package handling
- Added a WinGet package-state probe that checks installed state without
  invoking an installer.
- Setup skips WinGet installation when the package is already installed even
  if the executable is not visible in the current process PATH.
- `dotupdate` checks for an available newer version before invoking
  `winget upgrade`.
- When the installed version is already current, no installer/upgrader is
  launched.
- If package state cannot be determined reliably, Initial-setup leaves the
  package unchanged instead of forcing a reinstall.
- Applied the guard to common CLI tools, Neovim, VS Code, Starship, WezTerm,
  Rustup, Julia, and Windows bootstrap prerequisites.
- Existing package-manager behavior on macOS/Linux is unchanged.

### Documentation
- README remains English-only.
- Documented the install/update idempotency policy.

## 0.9.1

### Nushell compatibility fixes
- Fixed `enable-nushell-dotfiles.nu` assigning to an immutable `$current`
  binding; `$current` is now declared with `mut`.
- Removed deprecated lowercase-conversion usage from the legacy direnv cleanup
  migration.
- Avoided the newer lowercase replacement because it was introduced after the
  Nushell 0.109.x compatibility baseline.
- Winget direnv-path detection now uses `str contains --ignore-case`.
- Project validation now rejects reintroduction of the deprecated
  case-conversion commands without self-matching its own validation strings.

### Documentation
- README remains English-only.
- Added a Nushell compatibility policy for deprecation handling.

## 0.9.0

### Configuration schema architecture
- Added `SCHEMA_VERSION` as a separate source of truth from `VERSION`.
- Machine config now stores `app_version` and `schema_version`.
- Added `migrate-config.nu` with sequential schema migration support.
- Added automatic legacy schema-0 to schema-1 migration.
- Legacy machine config is backed up before the first schema migration.
- Newer unsupported schemas fail safely instead of being downgraded.
- Added `dotmigrate` and `dotmigrate --check`.

### Environment state and audit
- Added machine-local tool-version snapshots in
  `~/.config/dotfiles/state/tools.nuon`.
- Added `capture-tool-state.nu` and `dotstate`.
- `dotcapture` now refreshes the tool-version snapshot.
- Added read-only `dotaudit` with non-zero exit on critical failures.
- Environment report and doctor now expose schema/tool-state information.
- Fixed an inherited stray closing brace in `doctor.nu`.

### CI and validation
- Added `.github/workflows/ci.yml`.
- CI covers Windows, macOS, and Ubuntu.
- CI validates Nushell 0.109.1 and 0.115.1.
- Added `validate-project.nu` for parser, manifest, version, schema, and
  repository-structure validation.
- Setup dry-run no longer requires chezmoi, allowing safe orchestration checks
  in CI.
- CI validates Bash and PowerShell bootstrap syntax.

### Release workflow
- Release helper now updates the README version heading.
- Release helper validates the project before creating a release commit.
- README remains English-only.

## 0.8.9

### Final direnv removal migration
- Expanded legacy direnv cleanup to canonical and platform-native Nushell
  configuration directories.
- Removes old managed direnv module/autoload files and stale `source` lines
  from both live and private chezmoi configuration.
- On Windows, removes former Initial-setup User-scope direnv/XDG values only
  when they exactly match the defaults created by older releases.
- Preserves custom User-scope environment values.
- Adds a one-time migration marker so future manually installed direnv
  packages are not removed by later setup runs.
- If the remaining external executable is the exact Winget `direnv.direnv`
  package under Winget's managed package path, the one-time migration
  uninstalls that former managed dependency.
- Added `dotcleanup` and `dotcleanup --force` for migration maintenance.

### Documentation
- Rewrote README.md completely in English.
- Removed stale documentation that still listed direnv as a default package.
- Updated the package list, current feature set, release helpers, environment
  reproduction workflow, and direnv migration policy for v0.8.9.

## 0.8.8

### Remove direnv from the default environment
- Removed direnv from package manifests.
- Removed automatic direnv installation, Nushell hook/wrapper integration,
  validation, doctor/report integration, and `dotdirenv`.
- Added `cleanup-direnv.nu` migration logic.
- Removes legacy managed Nushell direnv module/autoload files.
- Removes the old managed `source ~/.config/nushell/modules/direnv.nu` line.
- On Windows, removes old User-scope `DIRENV_CONFIG`, `XDG_CACHE_HOME`, and
  `XDG_DATA_HOME` only when they exactly match Initial-setup defaults.
- Preserves any custom User-scope values.
- Does not uninstall an existing external `direnv.exe`.
- direnv is now optional/manual and outside Initial-setup's managed scope.

## 0.8.7

### direnv command resolution
- Fixed false `External direnv executable was not found in PATH` errors.
- Changed direnv discovery from deduplicated `which direnv` to
  `which --all direnv`.
- The managed wrapper now resolves the external direnv executable path and
  invokes that exact path.
- The PWD hook uses the same external-resolution logic.
- `setup-direnv.nu` also uses `which --all` when checking whether direnv is
  installed.
- `dotdirenv` now prints the resolved external executable path.
- Fixed `print (name + ...)` typo in `validate-direnv.nu`; the correct variable
  reference is `$name`.

## 0.8.6

### direnv Windows redesign
- Stopped using global Windows XDG variables as the primary direnv mechanism.
- Added a Nushell `direnv` wrapper that injects `DIRENV_CONFIG`,
  `XDG_CACHE_HOME`, and `XDG_DATA_HOME` only into the external direnv process.
- Existing process values continue to take precedence.
- `XDG_CONFIG_HOME` remains untouched.
- Added migration cleanup for old User-scope values written by
  Initial-setup v0.8.2-v0.8.5; only exact old managed defaults are removed.
- Moved the managed direnv integration from canonical autoload to
  `~/.config/nushell/modules/direnv.nu`.
- Canonical `config.nu` now explicitly sources the direnv module, avoiding
  Windows native/canonical autoload path mismatches.
- Removed legacy `initial-setup-direnv.nu` autoload files during migration.
- `dotdirenv` now validates the process-local environment model.

## 0.8.5

### direnv environment persistence
- Fixed the remaining Windows direnv configuration-directory failure.
- Changed `ensure-windows-direnv-env` to `def --env` so `$env` mutations
  persist to the calling Nushell environment.
- Changed `direnv-managed-env` to `export def --env` for the same reason.
- Added regression checks for custom commands that assign to `$env` without
  being declared environment-preserving.
- Updated direnv validation guidance for already-running shell processes.
- `XDG_CONFIG_HOME` remains untouched.

## 0.8.4

### Nushell 0.109 compatibility
- Fixed `Capture of mutable variable` parser error in `setup-direnv.nu`.
- The mutable Windows environment record is now frozen into an immutable
  binding before it is captured by `do --env`.
- Improved `validate-direnv.nu` so the `direnv status` exit code is returned
  from inside the temporary environment scope.
- Added `direnv-managed-env` to the managed Nushell direnv module for
  diagnostics.
- Existing Windows persistent values and current-process values remain
  preserved.
- `XDG_CONFIG_HOME` remains untouched.

## 0.8.3

### direnv Windows reliability
- Fixed a case where persistent Windows environment variables existed but the
  current Nushell process had not inherited them.
- Managed Nushell direnv integration now self-heals missing
  `DIRENV_CONFIG`, `XDG_CACHE_HOME`, and `XDG_DATA_HOME`.
- Resolution order is current process -> persistent User/Machine value ->
  Initial-setup default.
- Existing process and persistent values are preserved.
- Required directories are created idempotently in the active Nushell process.
- `XDG_CONFIG_HOME` remains untouched.
- `setup-direnv.nu` now immediately tests `direnv status` with the effective
  Windows values.
- `dotdirenv` now shows process, persistent, and effective values separately.

## 0.8.2

### direnv / Nushell integration
- Added `setup-direnv.nu` as an idempotent direnv setup unit.
- Reuses the existing package-manifest installation path and provides a
  platform-specific installation fallback when direnv is still unavailable.
- Added Windows User-scope direnv environment configuration using a dedicated
  PowerShell helper and .NET environment APIs.
- Configures `DIRENV_CONFIG`, `XDG_CACHE_HOME`, and `XDG_DATA_HOME` only when
  no existing User/Machine persistent value is present.
- Does not modify `XDG_CONFIG_HOME`.
- Creates the required Windows direnv config/cache/data directories.
- Added a managed Nushell autoload hook that appends to existing PWD hooks.
- Added `validate-direnv.nu` and `dotdirenv` self-check command.
- Added direnv setup/validation to normal setup and `dotdoctor --fix`.
- Environment report now includes the direnv version.

## 0.8.1

### Synchronization stability
- Added a machine-local automatic sync lock.
- Split synchronization into `auto-sync.nu` and `auto-sync-worker.nu`.
- Prevents overlapping one-minute scheduler runs.
- Locks older than 10 minutes are treated as stale.
- `dotdoctor` reports the automatic sync lock state.

### Git / version convenience
- Added `dotversion`.
- Added `dotrepo`.
- Added `dotrelease patch|minor|major`.
- Added `dotrelease set <version>`.
- Release helper updates `VERSION`, adds a CHANGELOG entry, commits, and can
  create an annotated Git tag.
- Remote push only occurs with explicit `--push`.
- Added `--no-tag`.

### Convenience
- Added `dotchecklist`.
- Environment report includes Git describe state when available.

## 0.8.0

### Work environment reproduction
- Added Neovim auto-install to the normal setup workflow.
- Added D2 Coding installation for GUI-oriented profiles.
- New default WezTerm configs prefer D2Coding.
- Added Rust toolchain/default/component/target capture and restore.
- Added Julia Project/Manifest environment capture and restore.
- Added `toolchains/` to private cloud state, cloud fingerprints, snapshots,
  and rollback.
- Added `dotcapture` and `dotrestoreenv`.
- Added post-setup checks for credentials, SSH keys, secrets, cloud login,
  fonts, and Julia environment instantiation.
- Added D2Coding/Rust/Julia state to doctor/report output.

### Reliability
- Removed the accidental nested `const TOOLS_ROOT` declaration from
  `build-machine-config`.
- Normalized inherited multiline boolean expressions for Nushell 0.109.
- Version display continues to use the repository `VERSION` file.

## 0.7.3

### Nushell home-directory compatibility
- Added a common `nu-home` compatibility pattern to every Nushell script that
  accesses the user's home directory.
- Supports both Nushell `$nu.home-path` and `$nu.home-dir` environments through
  optional record lookup.
- Removed all direct `$nu.home-path` and `$nu.home-dir` field accesses from the
  executable Nushell code.
- Added release regression checks so direct version-specific home-field access
  cannot be reintroduced accidentally.
- Updated `VERSION` to `0.7.3`.
- Removed stale hard-coded release numbers from bootstrap display strings.

## 0.7.1

### Nushell 0.109 parser compatibility
- Fixed `install-cli-tools.nu` failing with `missing label` at multiline
  `run-program` calls.
- Audited every Nushell file for the same pattern.
- Rewrote positional custom-command calls in Starship, WezTerm, auto-sync,
  package installation, sync fingerprinting, Git/SSH overrides, VS Code
  config capture/apply, and migration scripts.
- Custom commands with required positional arguments no longer put the command
  head on one line and the first argument on the following line.
- Continuation-style calls that began with `custom-command (` were also
  normalized through temporary variables where appropriate.
- Added a release regression scan that discovers custom commands from each
  `.nu` file and fails packaging if a call head is followed by indented
  positional arguments on later physical lines.

## 0.7.0

### Reliability
- Fixed the `setup.nu` multiline custom-command invocation that could fail on
  Nushell 0.109. `save-machine-config` now receives one record in a deliberate
  single-line invocation.
- The main setup orchestrator now keeps positional custom-command calls on one
  line whenever practical.

### Snapshot and rollback
- Added `dotsnapshot`.
- Added `dotrollback` and `dotrollback --list`.
- Automatic local-to-cloud pushes create a pre-push snapshot.
- Snapshots are machine-local and retained according to
  `maintenance.snapshot_keep`.

### Doctor and repair
- Added `dotdoctor`.
- Added `dotdoctor --fix` to repair shims, management modules, local overrides,
  secrets autoload, optional tools, and the automatic sync scheduler.

### Updates
- Added `dotupdate`.
- Supports `--repo`, `--tools`, `--config`, and `--all`.
- Updates Rust/Julia toolchains and Lazy.nvim plugins when detected.

### Profiles
- `workstation`, `laptop`, `server`, and `minimal` profiles now actually set
  feature defaults.
- Added `nu setup.nu --profile <profile>`.
- Added `--dry-run`.

### Diagnostics
- Added persistent sync log and `dotlog`.
- Added environment report and `dotreport --save`.

### Local secrets
- Added machine-local Nushell secrets autoload.
- Added `dotsecrets`.
- Secrets remain outside the synchronized/private-cloud source.

### Project bootstrap
- Added `newproj rust|julia|python|generic <name>`.

## 0.6.0

### Machine configuration
- Added persistent machine profile, GUI-app switch, synchronization policy,
  interval, automatic push/pull switches, stability delay, and feature toggles.
- Existing values are preserved when `setup.nu` is rerun.
- Added `dotconfig`.

### Synchronization visibility
- Added shared `.dotfiles-sync-meta.nuon`.
- Synchronization state now records last writer, writer time, and last action.
- `dotstatus` shows local/cloud dirty state, interval, machine, profile,
  conflict policy, last writer, and last sync.

### Git / SSH
- Added synchronized common + unsynchronized machine-local split.
- Added `~/.gitconfig.local` and `~/.ssh/config.local`.
- Added `dotgitlocal` and `dotsshlocal`.
- git-delta configuration is machine-local and is enabled only when `delta`
  is actually available.

### Package manifests
- Added `packages/common.txt`, `windows.txt`, `macos.txt`, and `linux.txt`.
- Package installation is manifest-driven.
- Added git-delta and lazygit.

### Platform fixes
- Fixed Windows Neovim shim path escaping by converting `\` to `/` before
  writing Lua.

### Sync policy
- Scheduler interval comes from `sync.interval_minutes`.
- `auto_push` and `auto_pull` are configurable.
- Conflict policies: `stop`, `prefer_local`, `prefer_cloud`.
- Default remains the safer `stop` policy.

## 0.5.0

### Automatic cross-machine synchronization
- Added conflict-safe bidirectional synchronization.
- Managed configuration is fingerprinted with SHA-256.
- Local-only changes are automatically published to the private cloud source.
- Cloud-only changes are automatically applied to the local machine.
- If local and cloud both change since the last successful synchronization,
  automatic overwrite is stopped and `SYNC-CONFLICT.txt` is created.
- Automatic synchronization now runs every 1 minute instead of every 15 minutes.
- Added a short stability delay before automatic writes to avoid applying a
  cloud directory while the cloud client is still updating it.
- `dotpush` explicitly resolves a conflict in favor of local configuration.
- `dotpull` explicitly resolves a conflict in favor of cloud configuration.
- Added `dotsync` for a manual automatic-sync cycle.
- `dotstatus` now shows sync baseline and conflict state.

### VS Code
- Extension synchronization is now exact rather than union-only.
- Removing an extension on the authoritative machine propagates to other machines.
- Settings, keybindings, and snippets remain synchronized.

### Safety
- Automatic synchronization does not silently choose a winner when both sides changed.
- Manual `dotpush` and `dotpull` remain available as explicit conflict resolution.

## 0.4.0

First release-candidate style version of Initial-setup.

### Bootstrap
- Added `bootstrap.ps1` for Windows.
- Added `bootstrap.sh` for macOS/Linux.
- Bootstrap installs the core prerequisites required to run `setup.nu`:
  Git, Nushell, Neovim, and chezmoi.
- Windows bootstrap also attempts to install VS Code.
- macOS bootstrap uses Homebrew and can install Homebrew when it is missing.
- Debian/Ubuntu and Fedora/RHEL bootstrap paths use Nushell's official Gemfury repositories.

### Development tools
- Added optional common CLI installation:
  ripgrep, fd, fzf, bat, zoxide, and direnv.
- Added Rust installation via rustup.
- Added Julia installation via Juliaup.
- Added VS Code application installation where a predictable package-manager route exists.

### Configuration synchronization
- Nushell config, env, modules, and autoload.
- Neovim full config directory, including plugin lock files.
- Git configuration.
- SSH config only; private keys remain excluded.
- WezTerm configuration.
- Starship configuration.
- Cargo `~/.cargo/config.toml`.
- Julia `~/.julia/config/startup.jl`.
- VS Code extensions.
- VS Code `settings.json`, `keybindings.json`, and `snippets/`.

### Reliability
- Optional application installers do not abort the full setup.
- Windows CLI installers do not capture `winget` stdout through Nushell `complete`.
- Public Git repository remains separated from private `home/` and `vscode/` data.
- The default private data root remains the parent directory of `Initial-setup`.
