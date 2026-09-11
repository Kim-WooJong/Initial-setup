# Initial-setup 0.5.0

`Initial-setup` bootstraps a development machine and keeps the same private
configuration synchronized across all of your computers.

The public Git repository contains only automation code and generic defaults.
The actual configuration lives outside the repository, in the repository's
parent directory by default, where a private cloud client such as Proton Drive
can synchronize it.

## Core synchronization model

```text
PC A local config
      ↕
 conflict-safe auto-sync
      ↕
private cloud source
      ↕ cloud client
private cloud source on PC B
      ↕
 conflict-safe auto-sync
      ↕
PC B local config
```

Every minute, each configured computer compares two SHA-256 fingerprints:

- the actual local configuration
- the private cloud source

It also remembers the fingerprints from the last successful synchronization.

The decision is:

| Local since last sync | Cloud since last sync | Action |
|---|---|---|
| unchanged | unchanged | Nothing |
| changed | unchanged | Automatically publish local config |
| unchanged | changed | Automatically apply cloud config |
| changed | changed | Stop and create a conflict |

This means you can edit a managed configuration file normally:

```nu
nvim ~/.config/nushell/config.nu
```

You do not have to use `dotpush` after every edit. The next automatic cycle
detects the local change and publishes it.

After your cloud client transfers the changed source to the other computers,
their next automatic cycle applies it.

## Conflict handling

If two computers independently modify configuration before receiving each
other's changes, Initial-setup does **not** silently overwrite either side.

It creates:

```text
~/.config/dotfiles/SYNC-CONFLICT.txt
```

Automatic synchronization for that cycle stops.

Resolve it explicitly:

```nu
dotpush
```

means:

```text
LOCAL WINS
local config -> private cloud source
```

or:

```nu
dotpull
```

means:

```text
CLOUD WINS
private cloud source -> local config
```

Both commands write a new synchronization baseline and clear the conflict file
after success.

## Layout

```text
PRIVATE-CLOUD-FOLDER/
├─ Initial-setup/              # public GitHub repository
│  ├─ bootstrap.ps1
│  ├─ bootstrap.sh
│  ├─ setup.nu
│  ├─ defaults/
│  ├─ scripts/
│  ├─ README.md
│  ├─ CHANGELOG.md
│  └─ VERSION
│
├─ .chezmoiroot               # private
├─ home/                      # private chezmoi source
│  ├─ dot_config/
│  │  ├─ nvim/
│  │  ├─ nushell/
│  │  ├─ wezterm/
│  │  └─ starship.toml
│  ├─ dot_cargo/
│  │  └─ config.toml
│  ├─ dot_julia/
│  │  └─ config/
│  │     └─ startup.jl
│  ├─ dot_gitconfig
│  └─ private_dot_ssh/
│
└─ vscode/                    # private
   ├─ extensions.txt
   ├─ settings.json
   ├─ keybindings.json
   └─ snippets/
```

Because `home/` and `vscode/` are siblings of `Initial-setup`, they are
structurally outside the Git repository.

## Fresh Windows machine

Open PowerShell in the repository:

```powershell
.\bootstrap.ps1 -Mode initial
```

For another computer whose private cloud directory has already synchronized:

```powershell
.\bootstrap.ps1 -Mode existing
```

Usually automatic mode is sufficient:

```powershell
.\bootstrap.ps1
```

## Fresh macOS / Linux machine

```sh
chmod +x bootstrap.sh
./bootstrap.sh --mode initial
```

Additional machine:

```sh
./bootstrap.sh --mode existing
```

## Installed environment

The bootstrap/setup process manages or attempts to install:

- Git
- Nushell
- Neovim
- chezmoi
- VS Code
- Starship
- WezTerm
- Rust via rustup
- Julia via Juliaup
- ripgrep
- fd
- fzf
- bat
- zoxide
- direnv

Optional package installation failures do not prevent the private
configuration from being applied.

## Synchronized configuration

### Nushell

- `config.nu`
- `env.nu`
- `modules/`
- `autoload/`

### Neovim

The complete Neovim config directory is synchronized, including `init.lua`,
`lua/`, and plugin lock files such as `lazy-lock.json`.

### Other development configuration

- Git configuration
- SSH `config` only
- Cargo `~/.cargo/config.toml`
- Julia `~/.julia/config/startup.jl`
- WezTerm config
- Starship config

SSH private keys are intentionally excluded.

### VS Code

The synchronized private VS Code state includes:

- exact extension set
- `settings.json`
- `keybindings.json`
- `snippets/`

Extension removal therefore propagates as well as extension installation.

## Daily commands

Normal editing no longer requires a manual sync command.

Useful commands remain:

```text
dotstatus      show chezmoi + automatic sync status
dotdiff        show chezmoi differences
dotsync        run an automatic sync cycle immediately

dotpush        force local -> cloud
dotpull        force cloud -> local

dotnvim        edit managed Neovim source
dotnu          edit managed Nushell config
dotenv         edit managed Nushell env
dotwezterm     edit managed WezTerm config
dotstarship    edit managed Starship config

dotdata        open private cloud source
dottools       open Initial-setup repository
```

## Automatic synchronization

The scheduler runs every **1 minute**:

- Windows: Task Scheduler
- Linux: systemd user timer
- macOS: LaunchAgent

A local-only change waits briefly before publishing and checks that the cloud
source did not change during that delay.

A cloud-only change also waits briefly and verifies that the cloud directory
has stopped changing before applying it.

This reduces the chance of acting while the cloud client is in the middle of
transferring files.

## Important limitation

This system relies on your private cloud client to synchronize the parent
directory between computers.

The synchronization logic can detect that both the local and cloud state
changed since the last successful baseline, but it cannot provide a
distributed transaction across several independent cloud clients.

For that reason, simultaneous editing on multiple computers becomes an
explicit conflict rather than an automatic last-writer-wins overwrite.

## Security

The migration intentionally does not import SSH private keys.

Avoid placing passwords, tokens, or API keys directly into synchronized
configuration unless you intentionally want them stored in your private cloud.
