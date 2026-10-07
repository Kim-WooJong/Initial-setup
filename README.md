# Initial-setup v0.26.0

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

## Updating by copying a release folder

Releases are delivered as a plain folder (no `.git`). To update, copy the whole
new release folder over the existing `Initial-setup` folder (overwrite files;
do not delete the folder first — `private/` holds your settings), then remove
files that the new release no longer contains:

```nu
nu --no-config-file scripts/prune-obsolete.nu            # preview
nu --no-config-file scripts/prune-obsolete.nu --execute  # delete obsolete files
```

The prune step compares against `RELEASE-MANIFEST.json`, never touches
`private/`, `.git/` or `tools/cloudwins/target/`, and also reports release
files that are missing or modified (an incomplete copy). When the command list
changed, run `nu --no-config-file scripts/refresh-commands.nu` once.

## Safe manual synchronization behavior

Opt-in native WireGuard encrypted capture/restore (Windows internal store and
Linux `wg-quick`) is documented in [WIREGUARD-CONFIG-SYNC.md](WIREGUARD-CONFIG-SYNC.md).
It requires separate privileged-helper enrollment; updating this checkout alone
does not grant access to protected VPN settings or activate tunnels.

Manual `dotctl push` (compatibility alias: `dotpush`) is the explicit local-authoritative resolution for a directory/cloud-client provider. If the private source changed since this machine's last baseline, the command first preserves a verified recovery copy under `~/.config/dotfiles/sync-recovery/<id>`, prints the baseline/current revisions, and only then captures this machine's configuration. Background/automatic pushes keep the strict baseline guard and never take this recovery path.

Manual `dotctl pull` (compatibility alias: `dotpull`) and the advanced `dotrpull` transport compare the live machine with the last successful local synchronization baseline before applying incoming private state. If local configuration changed, the command prints a colorized incoming diff. Interactive `dotctl pull` can explicitly confirm that the private source should replace those local changes; Enter/default cancels. Non-interactive replacement still requires `--discard-local`. `--force` does not imply local-authority discard. Set `NO_COLOR` to disable terminal styling.

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

## Primary commands

For routine use, the command surface is intentionally small:

```nu
dotctl status
dotctl diff
dotctl push
dotctl pull
dotctl sync
dotctl config
dotctl doctor
dotctl verify
dotctl update
```

Recovery and less-frequent configuration stay under the same namespace:

```nu
dotctl backup
dotctl restore --list
dotctl preflight --diff
dotctl config local
dotctl config secrets
dotctl config rclone
dotctl config rpool
dotctl config vault
dotctl config vault init
```

Run `dotctl` to print the compact help surface. Existing commands such as `dotpush`, `dotpull`, `dotvault`, `dotbackend`, and `dotcloud` remain available only as advanced/compatibility entry points; new interactive workflows should prefer `dotctl ...`. Native completion remains local-only and side-effect-free where applicable.

`dotctl pull` intentionally omits the legacy `--backup` switch. Every normal pull already creates a verified `before-verified-pull` backup immediately before changing live configuration, so exposing another backup switch in the primary interface was redundant and previously also implied `--force`. Existing scripts that explicitly need the extra named compatibility backup may continue to use `dotpull --backup`.

State-schema migration has been transactional since v0.18.8. `dotmigrate --check` is read-only and prepares the migration plan for machine config plus sync/provider/vault state. `dotmigrate` verifies every pending file, creates all recovery backups before the first commit, rechecks live SHA-256 values before replacement, and rolls back already-committed files in reverse order if a later migration fails. The canonical targets are sync-state schema 3, provider-state schema 2, and vault schema 2, each using `schema_version`; normal readers remain compatible with their supported legacy schemas until explicit migration.

When the `rclone_config` feature is enabled, setup treats `age` and `age-keygen` as required encryption dependencies and installs/repairs the `age` package through the existing platform package manager even when `cli_tools` is disabled. `dotctl push` automatically encrypts the active `rclone.conf` with age into `secrets/rclone.age` before publication. `dotctl pull` authenticates/decrypts a changed incoming ciphertext into restricted machine-local staging **before** chezmoi or other live configuration is applied, then commit that exact verified plaintext later in the pull transaction. A missing/wrong age identity or corrupt/changing ciphertext therefore stops the pull before live configuration is touched. The age identity is intentionally machine-local and is never synchronized; initialize or restore it once with `dotctl config vault init` (compatibility: `dotvault init`) before encrypted rclone synchronization can work on a machine. Existing local `rclone.conf` is backed up under `~/.config/dotfiles/rclone-restore-backups/<id>` before an incoming encrypted config replaces it.

Manual rclone capture/restore uses the same implementation as normal synchronization: `dotctl config rclone --capture` (or compatibility alias `dotrclone --capture`) uses the automatic capture path, while `dotctl config rclone --restore` uses the authenticated preflight/staged restore path with recovery backup.

`dotctl verify` checks content, not just readiness: it decrypts the private `rclone.conf` copy in memory and compares it with the active one by remote (OAuth token-only refreshes are reported as normal), exports this machine's rpool settings to a private stage and compares settings sections and crypt passwords with the private artifact, and runs `rpool import --dry-run`. It writes nothing and prints names/statuses only.

`dotctl config rclone` now reports encrypted-sync readiness from one shared read-only inspector: active config discovery, `rclone`/`age`/`age-keygen` health, vault policy and recipient availability, local age identity, encrypted copy availability, and separate `Push` / `Pull` readiness. `dotctl doctor` (compatibility: `dotdoctor`) reuses the same inspector so the two commands cannot disagree merely because they implement different readiness checks.

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
- Each finalized version carries an updated `scripts/cleanup-release-junk.nu` list. After manually overlaying a patch, run `nu scripts/cleanup-release-junk.nu --check` and then `nu scripts/cleanup-release-junk.nu` if candidates are reported; it is a no-op when that version has nothing to remove. Release authors run the same check before regenerating the manifest.

### Optional rclone-only transport

After setup, an additional rclone revision store can be used without changing the normal provider:

```nu
dotrpush --remote "proton:Initial-setup-store" --save-remote
dotrpull
```

The dedicated commands keep their provider baseline separate and do not replace the normal private source. See `docs/wiki/Synchronization.md`.


### rpool portable configuration

The private source is always `private/` inside the checkout (next to
`setup.nu`, git-ignored), so rpool's export goes to `private/rpool/`
(`config/portable-config.json`, plus
`secrets/rclone.age` when crypt remotes exist), not a sibling rpool code
repository. VS Code, toolchains, encrypted secrets, and the existing chezmoi
source tree are kept under the same private root. New app exports belong in
their own subdirectory there. See [storage layout and migration](RPOOL-CONFIG-SYNC.md).

When an artifact-capable rpool (`rpool export`/`rpool import`, e.g. 0.7.x) is installed, `dotctl push` exports its portable configuration to `rpool/config/portable-config.json` and, when crypt remotes exist, their passwords to `rpool/secrets/rclone.age`, encrypted to this machine's age vault recipient (`dotvault init`). `dotctl pull` imports that artifact after the incoming encrypted `rclone.conf` has been restored, with a dry-run first; the crypt passwords are written into crypt remotes that already exist in the target `rclone.conf` with the same structure (rpool does not create remotes). The bundle carries Pools, remote roots/default paths, remotes, shard sizing, worker/retry values, RS K+M, placement, and portable GUI defaults. Older rpool builds keep the legacy JSON-only `rpool/portable-config.json`. Machines without rpool skip this stage without blocking the rest of synchronization.

Use `dotctl config rpool` for status, `dotctl config rpool --capture` for a manual export, or `dotctl config rpool --restore --dry-run` to preview an import.
