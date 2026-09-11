# Changelog

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
