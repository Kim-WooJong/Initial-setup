# Initial-setup v0.15.0

Initial-setup is a cross-platform development-environment bootstrap and configuration synchronization project for Windows, Linux, macOS, and WSL.

## Start here

From the project root, run:

```nu
nu setup.nu
```

This is the canonical entry point. If the current machine already has a compatible Nushell, Git, and chezmoi, setup starts directly. If prerequisites are missing or Nushell is too old, `setup.nu` delegates to the platform bootstrap, prepares the host, and returns to the same setup flow.

If Nushell is not installed at all on Linux or macOS, bootstrap it from the project root:

```sh
bash bootstrap.sh
```

On Windows without Nushell, run `bootstrap.ps1` from PowerShell.

## What setup configures

- Nushell command environment and project commands
- chezmoi-managed configuration
- Rust and Julia toolchains
- rclone-backed/private configuration workflows
- Neovim, Starship, VS Code, WezTerm, and CLI tools according to profile
- Git identity and SSH configuration helpers
- snapshots, rollback, diagnostics, and synchronization state
- optional automatic synchronization
- Cloud-wins recovery/import workflow

## Useful commands

```nu
dotdoctor
dotstatus
dotpreflight --diff
dotsync
dotpush
dotpull
dotsnapshot
dotrollback
dotcloud status
```

## Validation

```nu
nu setup.nu --diagnose
nu setup.nu --check
```

`--diagnose` reports required files and release-manifest differences without turning setup into a read-only mode. `--check` performs strict release validation. Normal `nu setup.nu` continues to the existing configuration review flow, where chezmoi status/diff is shown before a destructive synchronization direction is chosen.

## Documentation

The documentation is maintained as an English wiki under [`docs/wiki`](docs/wiki/Home.md). Start with:

- [Wiki Home](docs/wiki/Home.md)
- [First Run](docs/wiki/First-Run.md)
- [Features and Roles](docs/wiki/Features-and-Roles.md)
- [Command Reference](docs/wiki/Command-Reference.md)
- [Synchronization](docs/wiki/Synchronization.md)
- [Recovery and Safety](docs/wiki/Recovery-and-Safety.md)
- [Troubleshooting](docs/wiki/Troubleshooting.md)

## Design rules

- `nu setup.nu` remains the stable user-facing entry point.
- Setup never silently deletes target-only files during Cloud-wins operations.
- Existing local/private configuration is reviewed before destructive direction changes.
- Version-specific audit or migration documents are not generated. Long-lived behavior belongs in the wiki and release history belongs in `CHANGELOG.md`.
