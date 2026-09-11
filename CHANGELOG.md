# Changelog

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
