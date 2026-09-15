# Changelog

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
