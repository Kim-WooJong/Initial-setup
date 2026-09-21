# Initial-setup v0.17.0

Initial-setup is a cross-platform development-environment bootstrap and configuration synchronization project for Windows, Linux, macOS, and WSL.

## Start here

From the project root, run:

```nu
nu setup.nu
```

This is the canonical entry point. If the current machine already has a compatible Nushell, Git, and chezmoi, setup starts directly. If prerequisites are missing or Nushell is too old, `setup.nu` delegates to the platform bootstrap, prepares the host, and returns to the same setup flow.

`setup.nu` hands the terminal directly to the interactive setup orchestrator. Menus and confirmations are printed before input is read; Ctrl+C is recorded as an interrupted, resumable run rather than a generic setup failure.

If Nushell is not installed at all on Linux or macOS, bootstrap it from the project root:

```sh
bash bootstrap.sh
```

On Windows without Nushell, run `bootstrap.ps1` from PowerShell.

## Safe manual pull behavior

Manual `dotpull` and `dotrpull` compare the live machine with the last successful local synchronization baseline before applying incoming private state. If the machine changed after that baseline, the command prints a colorized incoming diff and stops instead of silently rolling the edit back. Use `dotpush` when the local edit should win. Use `--discard-local` only after reviewing the diff when the incoming private state should replace it. `--force` does not imply local-authority discard. Set `NO_COLOR` to disable terminal styling.

## Changed private source during setup

When an existing directory provider differs from the last synchronized revision, interactive `nu setup.nu` offers:

1. Review the current local/private chezmoi differences and return to the menu.
2. Keep this machine's managed configuration and save it to the private source.
3. Keep the current private configuration and apply it to this machine.
4. Cancel (the default when pressing Enter).

The direction applies to the managed configuration as a whole. Protected Git/SSH targets retain their individual review before private-authoritative apply. This is not an automatic three-way merge or a per-file chooser for every managed file.

Before applying the selected direction, setup creates its normal local configuration backup under `~/.config/dotfiles/local-backups` and an independently verified copy of the synchronized private payload under `~/.config/dotfiles/reconciliation-backups/<id>`. The recovery path is printed. Recovery copies are retained independently of snapshot enablement and retention settings; `reconciliation.nuon` records the reviewed revision, file hashes, and setup run ID. Keep the copy until the result is confirmed. It is a file recovery copy, not a rotating `dotsnapshot` entry.

Setup rechecks the reviewed revision before continuing and after copying it. A further change invalidates that decision. Choosing a direction alone does not acknowledge a new baseline; successful setup commits the baseline. Cancel and Ctrl+C preserve it. If a resumed run encounters a changed source, selecting a direction starts a new transaction and retains the previous run's checkpoints.

This interactive recovery applies to the directory provider, including a cloud-client-synchronized folder. Background sync and explicit local/rclone revision-store transports retain their existing conflict guards. Captured or unattended setup refuses to prompt and asks for an interactive terminal.

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
- [Code Architecture](docs/wiki/Code-Architecture.md)
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

### Optional rclone-only transport

After setup, an additional rclone revision store can be used without changing the normal provider:

```nu
dotrpush --remote "proton:Initial-setup-store" --save-remote
dotrpull
```

The dedicated commands keep their provider baseline separate and do not replace the normal private source. See `docs/wiki/Synchronization.md`.
