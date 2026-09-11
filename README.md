# Initial-setup v0.7.3

A cross-platform development environment manager for Windows, macOS, and Linux.

`Initial-setup` is designed to bootstrap a new machine quickly and keep personal development configuration synchronized across multiple computers.

The overall workflow is:

```text
New computer
   ↓
Run setup.nu
   ↓
Install/configure development tools
   ↓
Restore personal configuration from Private Cloud
   ↓
Future configuration changes are synchronized automatically
```

The public Git repository contains only installation and management scripts. Personal configuration is stored outside the repository in a Private Cloud-synchronized directory.

---

# 1. Main Features

- Windows / macOS / Linux support
- Nushell-centered setup workflow
- chezmoi-based dotfiles management
- Bidirectional automatic configuration synchronization across machines
- SHA-256-based local/cloud change detection
- Conflict-safe synchronization
- Full Neovim configuration synchronization
- Nushell configuration synchronization
- WezTerm / Starship configuration synchronization
- VS Code settings and extension synchronization
- Shared and machine-local Git / SSH configuration separation
- Rust / Julia development environment setup
- Manifest-based CLI tool installation
- Snapshot / rollback support
- Environment diagnostics and automatic repair
- Development environment update command
- Synchronization logs and environment reports
- Machine-local secrets management
- Rust / Julia / Python project bootstrap
- Workstation / Laptop / Server / Minimal machine profiles

---

# 2. Recommended Directory Layout

```text
PRIVATE-CLOUD-FOLDER/
├─ Initial-setup/               # GitHub repository
│  ├─ VERSION
│  ├─ setup.nu
│  ├─ bootstrap.ps1
│  ├─ bootstrap.sh
│  │
│  ├─ defaults/
│  │  ├─ wezterm.lua
│  │  └─ starship.toml
│  │
│  ├─ packages/
│  │  ├─ common.txt
│  │  ├─ windows.txt
│  │  ├─ macos.txt
│  │  └─ linux.txt
│  │
│  ├─ scripts/
│  │  ├─ auto-sync.nu
│  │  ├─ sync-up.nu
│  │  ├─ sync-down.nu
│  │  ├─ sync-fingerprint.nu
│  │  ├─ update-sync-state.nu
│  │  ├─ write-sync-meta.nu
│  │  │
│  │  ├─ create-snapshot.nu
│  │  ├─ rollback.nu
│  │  ├─ doctor.nu
│  │  ├─ update.nu
│  │  ├─ report.nu
│  │  ├─ log-event.nu
│  │  │
│  │  ├─ setup-platform-shims.nu
│  │  ├─ setup-local-overrides.nu
│  │  ├─ setup-secrets.nu
│  │  │
│  │  ├─ install-cli-tools.nu
│  │  ├─ install-language-tools.nu
│  │  ├─ install-starship.nu
│  │  ├─ install-wezterm.nu
│  │  ├─ install-vscode.nu
│  │  │
│  │  ├─ capture-vscode-config.nu
│  │  ├─ apply-vscode-config.nu
│  │  ├─ capture-vscode-extensions.nu
│  │  ├─ install-vscode-extensions.nu
│  │  │
│  │  ├─ new-project.nu
│  │  └─ modules/
│  │     └─ dotfiles.nu
│  │
│  ├─ README.md
│  └─ CHANGELOG.md
│
├─ .chezmoiroot                # Private
│
├─ home/                       # Private chezmoi source
│  ├─ dot_config/
│  │  ├─ nvim/
│  │  ├─ nushell/
│  │  ├─ wezterm/
│  │  └─ starship.toml
│  │
│  ├─ dot_cargo/
│  │  └─ config.toml
│  │
│  ├─ dot_julia/
│  │  └─ config/
│  │     └─ startup.jl
│  │
│  ├─ dot_gitconfig
│  └─ private_dot_ssh/
│
└─ vscode/                     # Private
   ├─ extensions.txt
   ├─ settings.json
   ├─ keybindings.json
   └─ snippets/
```

`home/`, `vscode/`, and `.chezmoiroot` are siblings of the `Initial-setup` repository, so personal configuration is structurally outside the Git repository and cannot accidentally be committed with `git add .`.

---

# 3. Installation

## If Nushell / Git / Neovim / chezmoi are already installed

Run from the repository root:

```nu
nu setup.nu
```

For the first authoritative machine:

```nu
nu setup.nu --mode initial
```

For another machine where the Private Cloud source has already synchronized:

```nu
nu setup.nu --mode existing
```

`auto` is the default mode, so in most cases:

```nu
nu setup.nu
```

is sufficient. The setup script checks whether a private source already exists and chooses the appropriate mode.

---

## Fresh Windows Machine

Open PowerShell in the repository directory:

```powershell
.\bootstrap.ps1
```

First machine:

```powershell
.\bootstrap.ps1 -Mode initial
```

Additional machine:

```powershell
.\bootstrap.ps1 -Mode existing
```

`bootstrap.ps1` installs the core prerequisites required to run `setup.nu`.

Typical prerequisites include:

- Git
- Nushell
- Neovim
- chezmoi
- VS Code

After the prerequisites are available, the bootstrap script invokes `setup.nu`.

---

## macOS / Linux

```sh
chmod +x bootstrap.sh
./bootstrap.sh
```

First machine:

```sh
./bootstrap.sh --mode initial
```

Additional machine:

```sh
./bootstrap.sh --mode existing
```

---

# 4. Machine Profiles

The following profiles are supported:

```text
workstation
laptop
server
minimal
```

Example:

```nu
nu setup.nu --profile workstation
```

```nu
nu setup.nu --profile server
```

## workstation

Full GUI-oriented development environment.

```text
VS Code
WezTerm
Starship
Rust
Julia
CLI tools
Git
SSH
```

## laptop

Similar to `workstation`. Individual features can be adjusted in the machine-local `config.nuon`.

## server

CLI-oriented server environment without desktop applications.

```text
Nushell
Neovim
Git
SSH
CLI tools
Starship
Rust
Julia
```

## minimal

Minimal shell/editor-oriented environment with heavier toolchains and GUI applications disabled.

---

# 5. Dry Run

To inspect what setup would do without changing files, packages, or scheduler entries:

```nu
nu setup.nu --dry-run
```

Example:

```nu
nu setup.nu --profile server --dry-run
```

---

# 6. Machine-local Configuration

Each machine stores its own configuration in:

```text
~/.config/dotfiles/config.nuon
```

Example:

```nu
{
    version: "0.7.3"

    data_root: "..."
    tools_root: "..."

    machine: {
        name: "MY-PC"
        profile: "workstation"
        install_gui_apps: true
    }

    sync: {
        enabled: true
        interval_minutes: 1
        auto_push: true
        auto_pull: true
        conflict_policy: "stop"
        stability_delay_seconds: 3
    }

    maintenance: {
        snapshots_enabled: true
        snapshot_keep: 20
        log_keep_lines: 2000
    }

    features: {
        cli_tools: true
        vscode: true
        wezterm: true
        starship: true
        rust: true
        julia: true
        git_config: true
        ssh_config: true
    }
}
```

Edit it with:

```nu
dotconfig
```

After changing scheduler interval, profile, or feature-related values, rerun:

```nu
nu setup.nu
```

so the installed environment and scheduler can be reconciled.

---

# 7. Automatic Synchronization

The synchronization model is:

```text
Edit config on PC A
        ↓
Local fingerprint changes
        ↓
auto-sync
        ↓
chezmoi re-add
        ↓
Private Cloud source
        ↓
Cloud client synchronization
        ↓
PC B / PC C
        ↓
Cloud fingerprint changes
        ↓
chezmoi apply
        ↓
Latest configuration becomes active
```

Default polling interval:

```nu
interval_minutes: 1
```

Platform schedulers:

- Windows: Task Scheduler
- Linux: systemd user timer
- macOS: LaunchAgent

---

# 8. Conflict Handling

If both Local and Cloud have changed since the last successful synchronization, the system does not silently overwrite either side.

Recommended default:

```nu
conflict_policy: "stop"
```

When a conflict is detected, the following file is created:

```text
~/.config/dotfiles/SYNC-CONFLICT.txt
```

To make the current local configuration authoritative:

```nu
dotpush
```

To make the cloud configuration authoritative:

```nu
dotpull
```

Supported policies:

```text
stop
prefer_local
prefer_cloud
```

For normal use, `stop` is recommended.

---

# 9. Synchronization Status

```nu
dotstatus
```

Example output:

```text
Automatic Sync
────────────────────────────────
Machine       : MacStudio
Profile       : workstation
Enabled       : true
Interval      : 1 minute(s)
Auto push     : true
Auto pull     : true
Conflict mode : stop
Last sync     : 2026-09-12 ...
Last writer   : MacStudio
Writer time   : 2026-09-12 ...
Last action   : push
Local         : clean
Cloud         : clean
Conflict      : none
```

Run one synchronization cycle immediately:

```nu
dotsync
```

Force local configuration to become authoritative:

```nu
dotpush
```

Force cloud configuration to become authoritative:

```nu
dotpull
```

Show chezmoi differences:

```nu
dotdiff
```

---

# 10. Synchronized Configuration

## Nushell

```text
config.nu
env.nu
modules/
autoload/
```

## Neovim

The complete Neovim configuration directory is managed.

Example:

```text
~/.config/nvim/
├─ init.lua
├─ lua/
└─ lazy-lock.json
```

On Windows, the native Neovim configuration directory may differ from the canonical synchronized path. Initial-setup creates a platform shim when required.

Windows paths written into Lua use forward slashes:

```lua
C:/Users/name/.config/nvim
```

rather than raw backslashes.

## WezTerm

```text
~/.config/wezterm/wezterm.lua
```

## Starship

```text
~/.config/starship.toml
```

## Git

Shared:

```text
~/.gitconfig
```

Machine-local:

```text
~/.gitconfig.local
```

Edit the machine-local file:

```nu
dotgitlocal
```

The shared `.gitconfig` includes the local file.

## SSH

Shared:

```text
~/.ssh/config
```

Machine-local:

```text
~/.ssh/config.local
```

Edit:

```nu
dotsshlocal
```

SSH private keys are not synchronized.

## Rust

```text
~/.cargo/config.toml
```

## Julia

```text
~/.julia/config/startup.jl
```

## VS Code

Synchronized state:

```text
settings.json
keybindings.json
snippets/
extensions.txt
```

The extension list is authoritative rather than additive. Extensions removed from the authoritative machine can therefore be removed on other machines as well.

---

# 11. Package Manifests

CLI package definitions are separated from installation logic.

```text
packages/
├─ common.txt
├─ windows.txt
├─ macos.txt
└─ linux.txt
```

Default common tools:

```text
ripgrep
fd
fzf
bat
zoxide
direnv
git-delta
lazygit
```

To add another standard CLI tool, updating the manifest is preferred over hardcoding package installation directly into the installer script.

---

# 12. Snapshots

Create a manual snapshot:

```nu
dotsnapshot
```

Create a named snapshot:

```nu
dotsnapshot --label before-nvim-change
```

Snapshots are stored locally under:

```text
~/.config/dotfiles/snapshots/
```

Default retention:

```nu
snapshot_keep: 20
```

`dotpush` automatically creates a `pre-push` snapshot before updating the private cloud source.

Snapshots are intentionally machine-local.

---

# 13. Rollback

List available snapshots:

```nu
dotrollback --list
```

Restore the latest snapshot:

```nu
dotrollback
```

Restore a specific snapshot:

```nu
dotrollback --snapshot 20260912-031500-before-nvim-change
```

Before rollback, the current state is preserved as a `pre-rollback` snapshot.

---

# 14. Doctor

Run environment diagnostics:

```nu
dotdoctor
```

Run the repair pass:

```nu
dotdoctor --fix
```

The repair pass can restore or reconfigure:

- Private source structure
- Neovim / Nushell platform shims
- Nushell management module
- Git / SSH machine-local overrides
- Machine-local secrets autoload
- CLI tools
- Starship
- WezTerm
- Synchronization baseline
- Automatic synchronization scheduler

---

# 15. Environment Update

Update the development environment:

```nu
dotupdate
```

Specific categories:

```nu
dotupdate --repo
dotupdate --tools
dotupdate --config
dotupdate --all
```

Depending on the operating system and installed tools, this may update:

- Initial-setup Git repository
- Winget / Homebrew / Linux package-manager tools
- rustup
- juliaup
- Neovim Lazy plugins
- Private configuration
- Environment diagnostics

A snapshot is created before the update process.

---

# 16. Synchronization Log

Automatic synchronization events are written to:

```text
~/.config/dotfiles/logs/sync.log
```

Show recent log entries:

```nu
dotlog
```

Show more lines:

```nu
dotlog --lines 200
```

Clear the log:

```nu
dotlog --clear
```

Default maximum number of retained lines:

```nu
log_keep_lines: 2000
```

The log is machine-local.

---

# 17. Environment Report

Show a diagnostic environment report:

```nu
dotreport
```

Save the report:

```nu
dotreport --save
```

The report includes information such as:

- Initial-setup version
- Operating system
- Machine profile
- Nushell
- Git
- Neovim
- chezmoi
- Starship
- WezTerm
- Rust
- Cargo
- Julia
- git-delta
- lazygit
- Synchronization state
- Last writer
- Conflict state

This is useful when comparing environments or debugging a machine-specific issue.

---

# 18. Machine-local Secrets

Secrets are intentionally excluded from Private Cloud synchronization.

Initial-setup creates a machine-local Nushell autoload file:

```text
$nu.data-dir/vendor/autoload/dotfiles-secrets.nu
```

Edit it with:

```nu
dotsecrets
```

Example:

```nu
$env.MY_API_KEY = "..."
```

Avoid storing API keys, passwords, or tokens directly in the synchronized `env.nu` unless that is explicitly intended.

---

# 19. Project Bootstrap

## Rust

```nu
newproj rust my-tool
```

## Julia

```nu
newproj julia detector-analysis
```

## Python

```nu
newproj python quick-analysis
```

## Generic

```nu
newproj generic my-project
```

Specify another base directory:

```nu
newproj rust my-tool --path D:/Projects
```

---

# 20. Main Commands

## Synchronization

```text
dotstatus
dotdiff
dotsync
dotpush
dotpull
```

## Recovery

```text
dotsnapshot
dotrollback
dotdoctor
```

## Maintenance

```text
dotupdate
dotreport
dotlog
```

## Machine-local Configuration

```text
dotconfig
dotsecrets
dotgitlocal
dotsshlocal
```

## Managed Configuration

```text
dotnvim
dotnu
dotenv
dotwezterm
dotstarship
```

## Project Bootstrap

```text
newproj
```

## Locations

```text
dotdata
dottools
```

---

# 21. Version Management

The project version is stored in the repository-root file:

```text
VERSION
```

For v0.7.2:

```text
0.7.2
```

When reading the version from Nushell, convert raw file contents to UTF-8 text explicitly:

```nu
def app-version [] {
    let version_file = ($TOOLS_ROOT | path join "VERSION")
    open $version_file --raw | decode utf-8 | str trim
}
```

Project components should read the version from `VERSION` whenever possible instead of duplicating the same version string across multiple files.

Git tags and an automated release workflow can be added separately as a future release-management feature.

---

# 22. Nushell Compatibility Guidelines

This project targets real-world Nushell 0.109 behavior and avoids syntax patterns that caused parser issues during development.

## Keep custom command positional arguments on the same physical line

Recommended:

```nu
run-program ("Install " + $name) "winget" $args
```

Avoid:

```nu
run-program
    ("Install " + $name)
    "winget"
    $args
```

## Keep boolean expressions on one physical line when practical

Recommended:

```nu
| where { |line| not ($line | is-empty) and not ($line | str starts-with "#") }
```

Avoid splitting `and` or `or` onto a new physical line if it may be parsed as a separate command.

## Do not assume pipeline input fills positional custom-command parameters

Given:

```nu
def xml-escape [value: string] {
    $value
    | str replace --all '&' '&amp;'
}
```

Use:

```nu
let value = (xml-escape ($path | into string))
```

rather than:

```nu
$path | into string | xml-escape
```

unless the command is explicitly written to consume `$in`.

## Avoid Bash-style line continuation

Do not use:

```text
\
```

as a line continuation character in Nushell.

## Avoid `complete | str trim` for Windows package-manager output

Some Windows CLIs such as Winget may produce binary output. Installer scripts therefore prefer direct execution and `$env.LAST_EXIT_CODE`.

---

# 23. Recommended Daily Workflow

Normally, edit configuration directly.

For example:

```nu
nvim ~/.config/nushell/config.nu
```

or:

```nu
nvim ~/.config/nvim/init.lua
```

Automatic synchronization detects the change.

Typical flow:

```text
Edit configuration
   ↓
Local change detected within about 1 minute
   ↓
Private source updated
   ↓
Cloud client synchronizes the directory
   ↓
Other machines detect the cloud change
   ↓
Configuration is applied automatically
```

Under normal operation, `dotpush` and `dotpull` should not be required frequently. They are mainly useful for explicit conflict resolution or forced synchronization.

---

# 24. Current Project Stage

v0.7.2 provides the core functionality required for personal cross-machine development environment synchronization.

Current scope:

```text
Bootstrap
Configuration management
Cross-machine synchronization
Conflict protection
Recovery
Maintenance
Diagnostics
Machine profiles
Local secrets
Project bootstrap
```

The next stage should focus more on stabilization than on adding many new features.

Recommended priorities:

- Real integration testing on Windows / macOS / Linux
- Nushell parser compatibility hardening
- Git-based release workflow
- Full VERSION single-source-of-truth cleanup
- CI-based syntax and regression checks
- Stabilization toward a v1.0 release candidate
