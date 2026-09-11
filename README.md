# Initial-setup 0.7.1

Cross-platform workstation bootstrap, configuration synchronization, recovery,
and maintenance for Windows, macOS, and Linux.

## Normal setup

If the core prerequisites already exist:

```nu
nu setup.nu --mode initial
```

Use `initial` for the first authoritative machine and `existing` for additional
machines whose private cloud source already exists.

Usually this is enough later:

```nu
nu setup.nu
```

## Nushell 0.109 parser compatibility

The previous form:

```nu
save-machine-config
    $data_root
    $no_auto_sync
```

has been removed.

0.7.1 builds the complete machine config as a record and calls:

```nu
save-machine-config $proposed_context
```

on one line. The same rule is now applied project-wide: a custom command is never left
alone on one physical line with its required positional arguments beginning on
the following line. Continuation-style custom calls in installers, sync
fingerprinting, migration, VS Code capture/apply, and platform scheduling were
normalized for Nushell 0.109 compatibility.

## Profiles

Profiles now actually select feature defaults:

```nu
nu setup.nu --profile workstation
nu setup.nu --profile laptop
nu setup.nu --profile server
nu setup.nu --profile minimal
```

`workstation` and `laptop` enable the full GUI-oriented environment.

`server` disables GUI applications such as VS Code and WezTerm while retaining
CLI tools, Git/SSH, Rust, Julia, and Starship.

`minimal` keeps the shell/editor-oriented core and disables the heavier
language toolchains and GUI applications.

You can preview the result without changing anything:

```nu
nu setup.nu --profile server --dry-run
```

## Automatic sync

The existing conflict-safe SHA-256 synchronization remains in place.

Recommended defaults:

```nu
sync: {
    enabled: true
    interval_minutes: 1
    auto_push: true
    auto_pull: true
    conflict_policy: "stop"
    stability_delay_seconds: 3
}
```

## Snapshots and rollback

Manual snapshot:

```nu
dotsnapshot
```

Named snapshot:

```nu
dotsnapshot --label before-nvim-change
```

List available snapshots:

```nu
dotrollback --list
```

Restore the newest snapshot:

```nu
dotrollback
```

Restore a selected snapshot:

```nu
dotrollback --snapshot 20260912-031500-before-nvim-change
```

`dotpush` automatically creates a `pre-push` snapshot before changing the
private cloud source.

Snapshots are stored locally under:

```text
~/.config/dotfiles/snapshots/
```

so snapshot history itself is not repeatedly synchronized between computers.

## Doctor and repair

Status check:

```nu
dotdoctor
```

Conservative automatic repair:

```nu
dotdoctor --fix
```

The repair pass restores/rechecks:

- private source structure
- platform Nushell/Neovim shims
- Nushell management module
- local Git/SSH override files
- local secrets autoload
- common CLI tools
- Starship and WezTerm when enabled
- sync baseline when missing
- automatic sync scheduler

## Environment update

Update the normal environment:

```nu
dotupdate
```

With no flags, all update categories run.

Or select:

```nu
dotupdate --repo
dotupdate --tools
dotupdate --config
dotupdate --all
```

The update command takes a snapshot first.

Depending on the platform it updates the Initial-setup Git checkout, managed
package-manager tools, Rustup, Juliaup, and Lazy.nvim plugins when detected.

## Sync log

Automatic synchronization now records useful events under:

```text
~/.config/dotfiles/logs/sync.log
```

Show the last 50 lines:

```nu
dotlog
```

Show more:

```nu
dotlog --lines 200
```

Clear:

```nu
dotlog --clear
```

The log is machine-local and automatically truncated according to
`maintenance.log_keep_lines`.

## Environment report

```nu
dotreport
```

Save a diagnostic report:

```nu
dotreport --save
```

Reports include installed tool versions and synchronization state.

## Machine-local secrets

Initial-setup creates:

```text
$nu.data-dir/vendor/autoload/dotfiles-secrets.nu
```

This is a machine-local Nushell autoload file and is intentionally outside the
synchronized source.

Edit it with:

```nu
dotsecrets
```

Example contents:

```nu
$env.MY_API_KEY = "..."
```

Do not put secrets in shared `env.nu` unless cloud synchronization is intended.

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
newproj generic notes-project
```

A target base directory can be supplied with `--path`.

## Machine config

Machine-local settings remain in:

```text
~/.config/dotfiles/config.nuon
```

0.7.0 adds maintenance settings:

```nu
maintenance: {
    snapshots_enabled: true
    snapshot_keep: 20
    log_keep_lines: 2000
}
```

The full config contains:

```nu
{
    version: "0.7.1"

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

Edit with:

```nu
dotconfig
```

After changing profile/scheduler-related options, rerun:

```nu
nu setup.nu
```

## Main commands

```text
Synchronization
  dotstatus
  dotdiff
  dotsync
  dotpush
  dotpull

Recovery
  dotsnapshot
  dotrollback
  dotdoctor

Maintenance
  dotupdate
  dotreport
  dotlog

Machine-local
  dotconfig
  dotsecrets
  dotgitlocal
  dotsshlocal

Managed config
  dotnvim
  dotnu
  dotenv
  dotwezterm
  dotstarship

Projects
  newproj

Locations
  dotdata
  dottools
```

## Security

Private SSH keys remain excluded.

`.gitconfig.local`, `.ssh/config.local`, machine config, logs, snapshots, saved
reports, and the secrets autoload are all machine-local and are not imported
into the chezmoi private source.
