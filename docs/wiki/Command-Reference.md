# Command Reference

## Routine `dotctl` interface

New interactive workflows should use `dotctl`. The default surface is intentionally small; the older `dot*` commands remain available for advanced workflows and compatibility with existing scripts.

| Command | Role |
|---|---|
| `dotctl status` | Show the synchronization/provider summary and managed configuration state. |
| `dotctl diff` | Show managed-file differences before changing state. |
| `dotctl push` | Publish this machine's managed configuration to the private source. Manual push is the explicit local-authoritative conflict direction. |
| `dotctl pull` | Fetch/apply the private source. Pull creates its verified pre-apply backup automatically and requires explicit confirmation/flags before discarding conflicting local changes. |
| `dotctl sync` | Run one configured automatic-sync cycle. |
| `dotctl config` | Edit the machine configuration. |
| `dotctl doctor` | Diagnose installation, configuration, schema, provider, and encrypted-rclone readiness. |
| `rpool-install` | Install/update the RPool binary from its public GitHub releases into `~/.cargo/bin` (checksum-verified). `--version vX.Y.Z` (default latest), `--check` to compare only. Manual, no auto-update. |
| `dotvault ssh-key add-all` | Enroll every private key found in `~/.ssh` at once (skips `.pub`, certs, `config`, `known_hosts`, PuTTY `.ppk`); idempotent. |
| `dotvault ssh-key add <name>` | Enroll an SSH private key (`~/.ssh/<name>`): encrypt it to the vault recipients and add it to the synced manifest. `dotpush` publishes it. |
| `dotvault ssh-key remove <name>` | Stop syncing an SSH key (keeps the local key in `~/.ssh`). |
| `dotvault ssh-key list` | List enrolled SSH keys and whether each is published/public/present locally. |
| `dotvault edit-identity` | Open the age vault identity in an editor (default nvim) to set it to another machine's shared private key; creates it owner-only if missing, re-restricts permissions, validates it, and reports whether it matches the vault recipient. Local only; never prints the secret. |
| `dotvault rekey` | After an age key mismatch, make this machine's identity the only vault recipient (preview; `--execute` to apply), then `dotpush` re-encrypts. |
| `dotctl verify` | Read-only: check that this machine's `rclone.conf` and rpool settings/crypt passwords match the private source (`--json` for machine-readable output; exit 1 on a difference). |
| `dotctl update` | Run guarded project/tool/config maintenance. |

Run `dotctl` by itself to print this compact surface in the terminal.

## Recovery and configuration

These commands are part of the canonical `dotctl` namespace but are used less frequently.

| Command | Role |
|---|---|
| `dotctl backup` | Create a private-source snapshot. |
| `dotctl restore --list` | List snapshots; use `--snapshot <id>` to restore one. |
| `dotctl preflight --diff` | Review safety checks and differences before changing synchronized state. |
| `dotctl config local` | Edit machine-local Nushell overrides. |
| `dotctl config secrets` | Edit machine-local shell secret autoload configuration. |
| `dotctl config rclone` | Show encrypted-rclone readiness. `--capture`/`--restore` use the same safe implementations as normal push/pull. |
| `dotctl config rpool` | Show or manually capture/restore rpool's portable, non-secret configuration. |
| `dotctl config vault` | Show encrypted-vault status. |
| `dotctl config vault init` | Initialize or validate the local age-backed vault policy. |

With `rclone_config` enabled, `dotctl push` encrypts the active rclone configuration into `secrets/rclone.age`. `dotctl pull` authenticates/decrypts a changed ciphertext before live configuration is modified. The age identity remains machine-local and is never synchronized.

`dotctl pull` intentionally has no `--backup` option. Every normal pull already receives the transport's verified `before-verified-pull` backup. The legacy `dotpull --backup` path remains available only for older workflows that explicitly request an additional named backup.

## Advanced and compatibility commands

The commands below remain supported, but routine interactive use should prefer `dotctl`. Compatibility wrappers share the same canonical implementation where an equivalent `dotctl` command exists.

### Synchronization, recovery, and conflict handling

| Command | Role |
|---|---|
| `dotstatus` | Compatibility entry point for `dotctl status`. |
| `dotdiff` | Compatibility entry point for `dotctl diff`. |
| `dotpush` | Compatibility entry point for `dotctl push`. |
| `dotpull` | Compatibility entry point for `dotctl pull`; retains legacy-only options such as `--backup`. |
| `dotsync` | Compatibility entry point for `dotctl sync`. |
| `dotsnapshot` | Snapshot command retained for existing scripts; prefer `dotctl backup` for routine use. |
| `dotrollback` | Snapshot restore command retained for existing scripts; prefer `dotctl restore`. |
| `dotresolve` | Advanced three-way/protected-file conflict resolution. |
| `dotrpush` | Publish the current private-source snapshot to the separate explicit rclone transport. |
| `dotrpull` | Pull/apply from the separate explicit rclone transport. |
| `dotlocalbackup` | Create a local configuration backup. |
| `dotlocalrestore` | Restore a local configuration backup. |

### Configuration and credentials

| Command | Role |
|---|---|
| `dotconfig` | Compatibility entry point for `dotctl config`. |
| `dotlocal` | Compatibility entry point for `dotctl config local`. |
| `dotsecrets` | Compatibility entry point for `dotctl config secrets`. |
| `dotrclone` | Compatibility entry point for `dotctl config rclone`. |
| `dotvault` | Vault status/init/capture/restore compatibility and advanced subcommands. |
| `dotgitids` | Manage portable Git identity definitions. |
| `dotsshkeys` | Manage SSH-key configuration helpers. |
| `dotgitlocal` | Manage machine-local Git identity overrides. |
| `dotsshlocal` | Manage machine-local SSH overrides. |
| `dotmergecfg` | Merge configuration fragments using the advanced merge workflow. |
| `dottoolchain` | Inspect/manage toolchain configuration. |

### Diagnostics, migration, and maintenance

| Command | Role |
|---|---|
| `dotdoctor` | Compatibility entry point for `dotctl doctor`. |
| `dotupdate` | Compatibility entry point for `dotctl update`. |
| `dotpreflight` | Compatibility entry point for `dotctl preflight`. |
| `dotmigrate` | Transactionally migrate machine config plus sync/provider/vault state schemas; `--check` is read-only. |
| `dotvalidate` | Validate project and configuration structure. |
| `dottest` | Run project self-tests. |
| `dotaudit` | Run audit-oriented maintenance checks. |
| `dotreport` | Produce diagnostic/report output. |
| `dotlog` | Inspect project logs. |
| `dotstate` | Inspect lower-level state. |
| `dotchecklist` | Run maintenance checklist output. |
| `dotversion` | Inspect project version information. |
| `dotrepo` | Repository maintenance helpers. |
| `dotrelease` | Release maintenance helpers. |
| `dotcleanup` | Runtime/state cleanup workflow. |
| `dotupgrade` | Perform guarded project/runtime upgrade operations. |
| `dotsecuritytest` | Run security-oriented checks. |
| `dotnuupdate` | Update/select the managed Nushell runtime. |

### Setup/runtime control and application helpers

| Command | Role |
|---|---|
| `dotrun` | Inspect, resume, or roll back setup runs. |
| `dotcapture` | Capture environment/configuration state for supported workflows. |
| `dotrestoreenv` | Restore captured environment state. |
| `dotplan` | Build an advanced change plan. |
| `dotapply` | Apply a saved/selected change plan. |
| `dotverify` | Verify plan/application results. |
| `dotbackend` | Advanced synchronization-provider configuration/status controls. |
| `dotcloud` | Cloud-wins import/recovery workflow. |
| `dotonedrive` | OneDrive-specific helper retained for supported workflows. |
| `dotnvim` | Neovim configuration helper. |
| `dotnu` | Nushell configuration helper. |
| `dotenv` | Environment configuration helper. |
| `dotwezterm` | WezTerm configuration helper. |
| `dotstarship` | Starship configuration helper. |
| `dotdata` | Data/configuration maintenance helper. |
| `dottools` | Tool maintenance helper. |
| `newproj` | Create a new project scaffold. |

## Tab completion

Nushell-native subcommands expose completion where action-style APIs are useful. Dynamic completion is local and side-effect-free: it reads only machine-local state and does not synchronize, contact network services, mutate provider state, or invoke an external command just to build suggestions.

Examples:

```nu
dotctl config rclone <Tab>
dotvault <Tab>
dotbackend <Tab>
dotcloud <Tab>
```

Value completion is available for selected constrained arguments such as snapshot names, local-backup names, setup run IDs, release modes, project kinds, and plan directions.

## Explicit rclone-only transport

Use this only when an additional rclone revision store is required without changing the normal synchronization provider.

```nu
# One-time explicit target; save it after reviewing the path.
dotrpush --remote "proton:Initial-setup-store" --save-remote

# Later calls can reuse ~/.config/dotfiles/rclone-sync.nuon.
dotrpush
dotrpull

# Advanced apply controls remain available on the compatibility transport.
dotrpull --backup
dotrpull --force
dotrpull --prune
```

`dotrpush` publishes the current private-source snapshot as-is. It does not recapture live files into the normal provider source. `dotrpull` fetches into verified temporary staging and applies from that staging. This explicit transport keeps its provider baseline separate and does not advance the normal synchronization baseline.
