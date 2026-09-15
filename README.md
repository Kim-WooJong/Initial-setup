# Initial-setup v0.9.8

`Initial-setup` is a cross-platform bootstrap and configuration synchronization
tool for reproducing a personal development environment on Windows, macOS, and
Linux.

The project keeps public automation code in Git and stores personal
configuration outside the repository in a private cloud-synchronized folder.

v0.9.0 introduces a configuration-schema layer, automatic schema migration,
machine-local tool-version snapshots, a read-only environment audit, and
cross-platform GitHub Actions validation with real Nushell parsers.

```text
New machine
    ↓
bootstrap / setup.nu
    ↓
Install development tools
    ↓
Restore private configuration
    ↓
Install platform shims
    ↓
Enable automatic synchronization
```

## Goals

- One primary setup entry point: `nu setup.nu`
- Nushell-first workflow
- Reproducible Neovim, terminal, Git, Rust, Julia, and VS Code environments
- Private configuration kept outside the public Git repository
- Safe multi-machine synchronization
- Idempotent setup and repair
- Cross-platform support where practical
- Machine-local secrets and credentials kept out of cloud synchronization

---

## Repository and private-data layout

Recommended structure:

```text
PRIVATE-CLOUD-FOLDER/
├─ Initial-setup/                 # Public Git repository
│  ├─ VERSION
│  ├─ SCHEMA_VERSION
│  ├─ setup.nu
│  ├─ bootstrap.ps1
│  ├─ bootstrap.sh
│  ├─ defaults/
│  ├─ fonts/
│  ├─ packages/
│  ├─ scripts/
│  ├─ README.md
│  └─ CHANGELOG.md
│
├─ .chezmoiroot                  # Private
│
├─ home/                         # Private chezmoi source
│  ├─ dot_config/
│  │  ├─ nvim/
│  │  ├─ nushell/
│  │  └─ wezterm/
│  ├─ dot_cargo/
│  ├─ dot_julia/
│  ├─ dot_gitconfig
│  └─ private_dot_ssh/
│
├─ vscode/                       # Private
│  ├─ extensions.txt
│  ├─ settings.json
│  ├─ keybindings.json
│  └─ snippets/
│
└─ toolchains/                   # Private environment metadata
   ├─ rust/
   │  └─ state.nuon
   └─ julia/
      └─ environments/
```

`home/`, `vscode/`, `toolchains/`, and `.chezmoiroot` are intentionally outside
the `Initial-setup` Git repository.

---

## Supported platforms

- Windows
- macOS
- Linux

WSL can use the Linux path while Windows-native tools are handled separately.

---

## Quick start

### Existing machine with prerequisites

From the repository root:

```nu
nu setup.nu
```

For the first authoritative machine:

```nu
nu setup.nu --mode initial
```

For another machine restoring an existing private source:

```nu
nu setup.nu --mode existing
```

The default mode is `auto`.

### Fresh Windows machine

From PowerShell:

```powershell
.\bootstrap.ps1
```

Optional explicit mode:

```powershell
.\bootstrap.ps1 -Mode initial
```

or:

```powershell
.\bootstrap.ps1 -Mode existing
```

### Fresh macOS or Linux machine

```sh
chmod +x bootstrap.sh
./bootstrap.sh
```

Explicit modes:

```sh
./bootstrap.sh --mode initial
./bootstrap.sh --mode existing
```

---

## Profiles

Supported profiles:

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

### workstation

Full GUI development environment:

```text
Neovim
VS Code
WezTerm
Starship
Rust
Julia
CLI tools
Git / SSH configuration
D2Coding
```

### laptop

Similar to `workstation`, with machine-local customization available through
`config.nuon`.

### server

CLI-focused environment:

```text
Nushell
Neovim
Starship
Rust
Julia
Git / SSH
CLI tools
```

### minimal

Minimal terminal-oriented environment without the larger language toolchain
set.

---

## Dry run

Preview the setup plan without applying changes. Dry-run does not require
chezmoi, which allows CI to validate setup orchestration on a clean runner:

```nu
nu setup.nu --dry-run
```

Example:

```nu
nu setup.nu --profile server --dry-run
```

---

## Machine-local configuration

Machine-local state is stored in:

```text
~/.config/dotfiles/config.nuon
```

Typical structure:

```nu
{
    app_version: "0.9.8"
    schema_version: 2
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
        prune_extras: false
    }

    maintenance: {
        snapshots_enabled: true
        snapshot_keep: 20
        log_keep_lines: 2000
    }

    features: {
        neovim: true
        fonts: true
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

Rerun setup after changing profile, feature switches, or scheduler settings:

```nu
nu setup.nu
```

---

## Version and configuration schema

Application releases and machine-config structure now have independent
versions:

```text
VERSION         0.9.8
SCHEMA_VERSION  2
```

Machine config stores both values:

```nu
{
    app_version: "0.9.8"
    schema_version: 2
    ...
}
```

`VERSION` may change without changing the configuration format.
`SCHEMA_VERSION` changes only when the machine-config structure requires a
migration.

### Automatic migration

Normal setup runs the migration framework before rebuilding machine config:

```nu
nu setup.nu
```

Current migration path:

```text
legacy config / schema 0
        ↓
schema 1
        ↓
schema 2
```

Schema 2 adds `sync.prune_extras`, defaulting to `false`.

Before the first schema migration, Initial-setup creates:

```text
~/.config/dotfiles/config.nuon.pre-schema-v2
```

Manual migration:

```nu
dotmigrate
```

Check only:

```nu
dotmigrate --check
```

A config with a schema newer than the installed Initial-setup release is
rejected instead of being downgraded.

---

## Tool-version snapshot

Initial-setup records the tool versions visible on each machine in:

```text
~/.config/dotfiles/state/tools.nuon
```

Capture manually:

```nu
dotstate
```

The snapshot includes Nushell, Git, Neovim, chezmoi, Starship, WezTerm,
VS Code, Rust/Cargo, Julia, and the common CLI tools.

The snapshot is machine-local. Its purpose is diagnostics and comparison, not
forcing every platform to use identical package versions.

`dotcapture` refreshes the tool snapshot before capturing the managed
environment.

---

## Environment audit

Run:

```nu
dotaudit
```

The audit is read-only and checks:

- application version consistency
- machine-config schema
- private data root
- tools root
- chezmoi availability
- enabled core tools
- synchronization conflict state
- tool-version snapshot presence

Critical failures return a non-zero exit code.

Recommended stable-machine verification:

```text
nu setup.nu
    ↓
dotdoctor
    ↓
dotaudit
    ↓
0 critical errors
```

---

## Continuous integration

GitHub Actions:

```text
.github/workflows/ci.yml
```

CI validates the project on:

```text
Windows
macOS
Ubuntu
```

against:

```text
Nushell 0.109.1
Nushell 0.115.1
```

Validation includes:

- real `nu-check` parser validation
- package-manifest consistency
- `VERSION` / `SCHEMA_VERSION` consistency
- repository structure checks
- `setup.nu --dry-run`
- Bash bootstrap syntax
- PowerShell bootstrap parser validation

Run the repository validator locally:

```nu
nu scripts/validate-project.nu
```


---

## Cross-version Nushell syntax normalization

v0.9.8 performs a repository-wide syntax normalization for Nushell physical
lines.

Arithmetic/string continuation operators are never placed at the beginning of
a physical line. For example:

```nu
# Avoid
let value = (
    "prefix"
    + $suffix
)

# Use
let value = (
    "prefix" + $suffix
)
```

The same rule applies to multiplication and similar arithmetic continuations.

Project validation now rejects physical lines beginning with `+`, `*`, or `/`
in Nushell source files. Existing checks for leading `and` / `or`, Bash-style
trailing backslashes, deprecated string case commands, direct version-specific
Nushell home fields, and parser validation remain enabled.


---

## Machine-local Nushell setup

v0.9.7 adds one intentionally unmanaged file for computer-specific Nushell
configuration:

```text
~/.config/dotfiles/local.nu
```

Initial-setup creates the file only when it is missing. After creation,
Initial-setup never overwrites or replaces its contents.

The synchronized canonical Nushell config contains only this shared source
directive:

```nu
# Machine-local setup (not synchronized)
source ~/.config/dotfiles/local.nu
```

This allows every computer to use the same shared Nushell configuration while
keeping different machine-specific setup in `local.nu`.

Example:

```nu
$env.MY_MACHINE_ONLY = "value"
alias local-tool = some-command
```

Edit it with:

```nu
dotlocal
```

The file is deliberately excluded from:

- chezmoi and private-cloud synchronization
- automatic sync fingerprints
- `dotpush` and `dotpull`
- snapshots and rollback
- public Git repository state

`dotdoctor --fix` creates it when missing, but does not modify an existing
file.


---

## Hidden Windows automatic synchronization

v0.9.6 changes the Windows `DotfilesAutoSync` scheduled task so periodic sync
runs do not open a terminal or console window.

The task now uses:

```text
Task Scheduler
    ↓
wscript.exe //B //Nologo
    ↓
~/.config/dotfiles/scheduler/auto-sync-hidden.vbs
    ↓
nu.exe scripts/auto-sync.nu
```

The machine-local VBScript launcher invokes Nushell with window style `0`
(hidden) and waits for the sync cycle to finish.

Running setup replaces the existing `DotfilesAutoSync` task in place, so an
older task that directly launched `nu.exe` is automatically upgraded to the
hidden launcher.

Automatic synchronization does not update the public Initial-setup Git
repository. The scheduled sync graph is limited to fingerprint comparison,
chezmoi/private-state synchronization, VS Code/toolchain state handling, and
sync metadata. Repository updates remain explicit through commands such as:

```nu
dotupdate --repo
```

or:

```nu
dotupdate --all
```


---

## Missing-path fingerprint handling

v0.9.5 makes synchronization fingerprint generation tolerant of optional or
not-yet-created configuration paths.

Fingerprint targets are now processed in this order:

```text
null / empty target
    → MISSING

path does not exist
    → MISSING

path exists
    → expand path
    → detect file/directory type
    → hash contents
```

This prevents `path expand` or `path type` from receiving a `nothing` value
when a managed file or directory has not been created on the current machine.

A missing managed target is a valid synchronization state and is represented
in the fingerprint instead of being treated as a setup error.


---

## Fingerprint compatibility fix

v0.9.4 fixes synchronization fingerprint generation on current Nushell.

String concatenation in `sync-fingerprint.nu` no longer places `+` at the
beginning of a physical line. This prevents Nushell from interpreting `+` as
an external command while a fingerprint pipeline is running.

Variable filesystem patterns are also converted explicitly to the `glob` type
before being passed to `glob`.

The fix affects synchronization baseline generation, `dotstatus`, automatic
sync fingerprinting, and local/cloud change detection.


---

## Merge-first synchronization policy

v0.9.3 changes the default reconciliation policy to merge-first.

Default:

```nu
sync: {
    prune_extras: false
}
```

With `prune_extras: false`:

```text
missing locally
    → install/copy from private source

different locally
    → update/overwrite with private source

already identical
    → skip

local-only item
    → keep
```

This applies to VS Code extensions and snippet files. The purpose is to
synchronize useful changes between machines without deleting machine-local
additions just because they are absent from another machine's snapshot.

For a one-time strict pull:

```nu
dotpull --prune
```

For persistent strict reconciliation on a machine:

```nu
sync: {
    prune_extras: true
}
```

### Rust restore

Rust restoration is incremental:

- existing toolchains are not reinstalled
- existing components are not re-added
- existing targets are not re-added
- the default toolchain is changed only when it differs
- extra local Rust state is preserved


---

## Idempotent package installation and updates

v0.9.2 makes Windows package handling more conservative.

Before running a WinGet install command, Initial-setup checks whether the
package is already registered as installed. If it is already installed, setup
does not reinstall it merely because its executable is temporarily missing
from the current process PATH.

Before running a WinGet upgrade command, `dotupdate` checks whether WinGet
actually reports a newer version as available.

Policy:

```text
not installed
    → install

installed + newer version available
    → upgrade

installed + no newer version available
    → do nothing

package state cannot be determined
    → leave package unchanged
```

This prevents unnecessary installer runs and avoids uninstall/reinstall cycles
when the installed version is already current.

If a package is installed but its command is not visible in PATH, Initial-setup
reports the PATH problem instead of reinstalling the package.


---

## Nushell compatibility policy

v0.9.1 tightens compatibility between the Nushell 0.109.x baseline and newer
releases.

When a command becomes deprecated but its replacement was introduced after the
compatibility baseline, Initial-setup avoids both forms when a stable
cross-version alternative exists.

For case-insensitive path checks, Initial-setup uses:

```nu
str contains --ignore-case
```

instead of relying on a case-conversion command.

CI continues to validate both the compatibility baseline and a current Nushell
release.


---

## Core managed tools

### Neovim

Neovim is installed automatically when enabled.

The full configuration directory is managed through chezmoi, including
`lazy-lock.json` when present.

### Nushell

Canonical configuration is stored under:

```text
~/.config/nushell/
```

Platform shims bridge native configuration locations to the canonical
configuration where needed.

### WezTerm

Managed configuration:

```text
~/.config/wezterm/wezterm.lua
```

New default configurations prefer D2Coding when available.

### D2Coding

GUI-oriented profiles install D2Coding automatically when possible.

Font binaries are not stored in this repository.

### Starship

Managed configuration:

```text
~/.config/starship.toml
```

### VS Code

Managed items include:

```text
settings.json
keybindings.json
snippets/
extensions.txt
```

The extension list is treated as authoritative when applying configuration.

### Git

Shared configuration:

```text
~/.gitconfig
```

Machine-local overrides:

```text
~/.gitconfig.local
```

Edit local overrides with:

```nu
dotgitlocal
```

### SSH

Shared configuration:

```text
~/.ssh/config
```

Machine-local overrides:

```text
~/.ssh/config.local
```

Edit with:

```nu
dotsshlocal
```

Private SSH keys are not synchronized.

---

## CLI package manifests

CLI packages are separated from installer logic:

```text
packages/
├─ common.txt
├─ windows.txt
├─ macos.txt
└─ linux.txt
```

The default common toolset is:

```text
ripgrep
fd
fzf
bat
zoxide
git-delta
lazygit
```

`direnv` is intentionally not part of the default stack.

---

## Rust environment reproduction

Initial-setup captures and restores:

- rustup toolchains
- default toolchain
- installed Rust components
- installed compilation targets

Private state:

```text
toolchains/rust/state.nuon
```

Capture current state:

```nu
dotcapture
```

Restore environment metadata:

```nu
dotrestoreenv
```

---

## Julia environment reproduction

Initial-setup captures `Project.toml` and `Manifest.toml` files from Julia
environments without synchronizing the entire Julia depot or package cache.

Private state:

```text
toolchains/julia/environments/
```

After restoring a machine, instantiate packages when first needed.

---

## Automatic synchronization

The default synchronization interval is one minute.

Platform scheduler:

- Windows: Task Scheduler
- Linux: systemd user timer
- macOS: LaunchAgent

The basic flow is:

```text
Local config change
    ↓
Fingerprint change
    ↓
auto-sync
    ↓
chezmoi re-add
    ↓
Private cloud source
    ↓
Cloud provider synchronization
    ↓
Another machine detects cloud change
    ↓
chezmoi apply
```

Automatic sync uses a machine-local lock to prevent overlapping scheduler
runs.

A lock older than 10 minutes is treated as stale.

---

## Conflict handling

Default conflict policy:

```nu
conflict_policy: "stop"
```

When both local and cloud state changed since the last successful sync,
Initial-setup does not overwrite either side automatically.

Conflict marker:

```text
~/.config/dotfiles/SYNC-CONFLICT.txt
```

Resolve using local state:

```nu
dotpush
```

Resolve using cloud state:

```nu
dotpull
```

---

## Synchronization commands

```nu
dotstatus
dotdiff
dotsync
dotpush
dotpull
```

---

## Snapshots and rollback

Create a snapshot:

```nu
dotsnapshot
```

Named snapshot:

```nu
dotsnapshot --label before-change
```

List snapshots:

```nu
dotrollback --list
```

Restore the latest snapshot:

```nu
dotrollback
```

Restore a specific snapshot:

```nu
dotrollback --snapshot <snapshot-name>
```

Snapshots are machine-local and are also created automatically before
important destructive operations.

---

## Doctor and repair

Check the environment:

```nu
dotdoctor
```

Attempt repairs:

```nu
dotdoctor --fix
```

Doctor covers the machine-config schema, managed configuration structure,
platform shims, local overrides, secrets integration, optional tools,
synchronization state, and the scheduler. `dotdoctor --fix` runs config
migration before the repair pass.

---

## Updates

Update the environment:

```nu
dotupdate
```

Available scopes:

```nu
dotupdate --repo
dotupdate --tools
dotupdate --config
dotupdate --all
```

Depending on the platform and enabled features, updates can include:

- Initial-setup repository
- platform package manager tools
- rustup
- juliaup
- Neovim Lazy plugins
- private configuration apply
- doctor checks

---

## Environment report

Display the current environment:

```nu
dotreport
```

Save the report:

```nu
dotreport --save
```

---

## Logs

Automatic synchronization log:

```text
~/.config/dotfiles/logs/sync.log
```

Commands:

```nu
dotlog
dotlog --lines 200
dotlog --clear
```

---

## Machine-local secrets

Secrets are intentionally not stored in the private cloud source.

Machine-local Nushell secrets file:

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

Do not place API tokens or private credentials in the shared `env.nu`.

---

## Project bootstrap

Rust:

```nu
newproj rust my-tool
```

Julia:

```nu
newproj julia detector-analysis
```

Python:

```nu
newproj python quick-analysis
```

Generic:

```nu
newproj generic my-project
```

---

## Repository version and release helpers

Show application and Git version state:

```nu
dotversion
```

Show repository status:

```nu
dotrepo
```

Create releases:

```nu
dotrelease patch
dotrelease minor
dotrelease major
dotrelease set 0.9.0
```

Remote push is explicit:

```nu
dotrelease patch --push
```

Skip tag creation:

```nu
dotrelease patch --no-tag
```

`VERSION` is the application version source of truth.

---

## Legacy direnv migration

`direnv` is no longer installed, configured, hooked, or validated by
Initial-setup.

v0.8.9 performs a one-time migration that removes legacy Initial-setup state
from canonical and platform-native Nushell configuration locations.

Known managed files:

```text
~/.config/nushell/modules/direnv.nu
~/.config/nushell/autoload/initial-setup-direnv.nu
```

The migration also removes the old managed `source` line from live and private
chezmoi `config.nu` files.

On Windows, User-scope variables are removed only when they exactly match the
defaults previously written by Initial-setup:

```text
DIRENV_CONFIG  = %APPDATA%\direnv\config
XDG_CACHE_HOME = %LOCALAPPDATA%\direnv\cache
XDG_DATA_HOME  = %LOCALAPPDATA%\direnv\data
```

Custom values are preserved.

If the external executable is still located under the exact Winget
`direnv.direnv` package path used by the former Initial-setup dependency, the
one-time v0.8.9 migration removes that Winget package.

A machine-local migration marker prevents future setup runs from uninstalling
a later manual direnv installation:

```text
~/.config/dotfiles/migrations/direnv-removed-v0.8.9.nuon
```

Run the migration manually:

```nu
dotcleanup
```

Force it to run again:

```nu
dotcleanup --force
```

After upgrading from a direnv-enabled release, restart the terminal once to
discard any PWD hook already loaded in the parent shell.

---

## Maintenance commands

```text
Synchronization
  dotstatus
  dotdiff
  dotsync
  dotpush
  dotpull

Recovery / validation
  dotsnapshot
  dotrollback
  dotdoctor
  dotaudit
  dotmigrate
  dotcleanup

Maintenance
  dotupdate
  dotreport
  dotlog
  dotversion
  dotrepo
  dotrelease
  dotstate
  dotchecklist

Machine-local
  dotconfig
  dotlocal
  dotsecrets
  dotgitlocal
  dotsshlocal

Managed configuration
  dotnvim
  dotnu
  dotenv
  dotwezterm
  dotstarship

Environment reproduction
  dotcapture
  dotrestoreenv

Projects
  newproj

Locations
  dotdata
  dottools
```

---

## Fresh-machine workflow

First authoritative machine:

```nu
nu setup.nu --mode initial
```

Additional machine:

```nu
nu setup.nu --mode existing
```

Normal subsequent maintenance:

```nu
nu setup.nu
dotdoctor
dotaudit
dotstatus
```

The intended end state is that a new development machine can be rebuilt from
the public Initial-setup repository plus the private cloud source with minimal
manual configuration.
