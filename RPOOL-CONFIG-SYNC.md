# RPool configuration synchronization

## Private storage layout

The private source is always `Initial-setup/private`, inside the directory
that contains `setup.nu`, resolved relative to the tool checkout, **not** the
terminal's current directory or the user's HOME. It is git-ignored and is
excluded from release manifests, `dotupgrade` inventories, syntax/project
validation and `cleanup-release-junk.nu`. The rpool artifact is therefore
`Initial-setup/private/rpool/`, never a sibling rpool source-code repository.
New application exports must use a dedicated application subdirectory within
this private source.

```text
parent/
  rpool/                 # optional rpool source code; not configuration
  Initial-setup/          # tooling/source code (setup.nu)
    private/             # private synchronized settings (git-ignored)
      rpool/config/portable-config.json   # portable rpool settings (no secrets)
      rpool/secrets/rclone.age            # rpool crypt passwords, age-encrypted (only with crypt remotes)
      vscode/              # VS Code settings and extension list
      toolchains/          # Rust and Julia configuration
      secrets/rclone.age   # encrypted credentials only
      .chezmoiroot          # selects the inner home directory
      home/                # existing chezmoi-encoded Git/SSH/shell/editor files
```

Because the settings live inside the checkout, update the checkout in place
(`git pull` / `dotupgrade`); deleting and re-extracting the whole
`Initial-setup` folder also deletes `private/`. Machine-local state
(`~/.config/dotfiles`: machine config, vault policy, age identity) stays
outside the checkout. Cloud-wins requires its target to be outside the
checkout and therefore cannot target this default location.

The location is fixed: every command uses `<tools_root>/private`. A
`data_root` saved by an older version (the checkout's parent folder or
`../home`) is ignored — setup prints "Ignoring the previous private data
location" and starts in `private/`; the old folder is never read, changed or
deleted (remove it manually when no longer needed). `--data-dir` is accepted
only by isolated tests. This also removes the old failure where a parent-folder
`data_root` containing rpool source code made `dotpush` stop on
`rpool/Cargo.lock`.

The inner `home/` is intentional: preserving chezmoi's source format keeps
existing apply/restore semantics intact. Active application configuration,
machine-local control state, and vault identities are not stored in the
shared payload.

The private source's `rpool/` artifact is a transport bundle, not
RPool's live GUI settings file. Do not move the live config directory into the
private source or replace it with that bundle.

## Active application files

RPool resolves its own paths; Initial-setup calls `rpool config export/import`.

| OS | Active configuration directory |
| --- | --- |
| Windows | `%APPDATA%\rpool` |
| macOS | `$HOME/Library/Application Support/rpool` |
| Linux | `$XDG_CONFIG_HOME/rpool`, or `$HOME/.config/rpool` |

Portable settings are read from and restored to `gui.json`, `pools.json`,
and `remote_roots.json` there. Updated RPool exposes resolved paths without
reading file contents through `rpool config paths`.

## Finding the rpool executable

`dotpush` and `dotctl push` share the same capture path; `dotpull` and
`dotctl pull` import the received bundle. Launching the GUI does not by itself
put the executable on PATH. Recommended: keep both executables in one directory
and register that directory once using `dotctl config local` (or Nushell
`config.nu`). Paste this snippet, replacing the directory with its actual location:

```nu
let sync_tools = ('C:\Tools\rpool' | path expand)
$env.PATH = ($env.PATH | prepend $sync_tools | uniq)
hide-env -i RPOOL_BIN
```

On macOS/Linux, use your directory, for example `~/Tools/rpool`, containing
`rpool` and `rclone`; Windows uses `rpool.exe` and `rclone.exe`. No OS-specific
executable aliases are needed. The directory can contain spaces. Remove any old
`RPOOL_BIN` assignment: a stale override takes precedence over PATH. The
`hide-env` line explicitly switches back to PATH discovery.

Restart Nushell, then run `which rpool`, `which rclone`, `dotctl config rpool`,
and `dotpush` / `dotpull`. Children launched with `--no-config-file` inherit
this PATH. Independently launched scheduled jobs/other shells do not load this
Nushell configuration; configure their environment separately if needed.
See `templates/sync-tools.nu.example` for a directory-validated snippet.

An exact executable override remains available when necessary:

```nu
$env.RPOOL_BIN = 'C:\Tools\rpool\rpool.exe'
dotctl config rpool
dotpush
# On the receiving PC, configure its own executable location, then:
dotpull
```

Keep this executable path local; it is not part of portable settings. Automatic
discovery also checks PATH and known sibling build/install locations. Status
reports the selected executable. Missing/unsupported CLI must not silently look
like a successful rpool settings update; follow the printed diagnostic.

## Coverage and encryption

- GUI preferences include workers, retries, placement, shard parameters,
  remote selection/default path, and encryption defaults.
- Encryption defaults are preferences (entropy bits and naming modes), not
  passwords. They remain in the portable JSON.
- The destination's machine-local rclone executable path is preserved.
- Older bundles without encryption preferences preserve destination preferences.
- History, inventory, and integrity runtime state are not portable settings.
- Crypt-remote passwords (`password`/`password2` of `type = crypt` remotes)
  are synchronized by `dotpush`/`dotpull` through rpool's artifact format:
  `rpool export` writes them to `rpool/secrets/rclone.age`, encrypted to the
  Initial-setup vault's recipient. The vault must be initialized
  (`dotvault init`) and have exactly one recipient; `age` must be on PATH.
  Other provider tokens are never part of the rpool artifact.
- On pull, `rpool import` writes those passwords only into crypt remotes that
  already exist in the target `rclone.conf` with the same `remote` and
  encryption modes. Create the remotes first (Initial-setup's encrypted
  `rclone.conf` sync, or manually). The receiving machine needs the same vault
  identity (`~/.config/dotfiles/age/identity.txt`) to decrypt.
- Change detection: with an artifact-capable rpool, the local sync fingerprint
  includes a SHA-256 digest of the active `rclone.conf` crypt sections, so a
  crypt-password-only change triggers auto-sync/push even when `rclone.conf`
  sync is disabled. OAuth token refreshes of other remotes are ignored. An
  rclone.conf encrypted with `RCLONE_CONFIG_PASS` cannot be inspected; such
  password changes still need a manual `dotpush`.
- The rpool artifact's `rpool/secrets/rclone.age` is not the same file as the
  vault's top-level `secrets/rclone.age` (complete `rclone.conf` backup). They
  have different schemas and must not be substituted for each other.
- Older rpool builds without `rpool export`/`import` use the legacy JSON-only
  `rpool/portable-config.json` and do not carry crypt passwords. A legacy
  capture is refused once the private source already holds the artifact
  layout, so an old rpool cannot publish stale settings over it.

## Applying this update

Both RPool and Initial-setup source were updated. Deploy a rebuilt RPool binary
to Windows and update the Initial-setup checkout recorded as `tools_root`;
`scripts/modules/rpool-sync.nu` runs from that checkout, so no module copy is
needed. Updating only Initial-setup cannot add encryption-preference support
to an old RPool executable.

Run `rpool config paths` to inspect active locations. It should report the
Windows user's AppData/Roaming directory and
`portable_encryption_preferences: true`.

## Verification

On a real machine, `dotctl verify` (read-only) reports whether this machine's
rpool settings, crypt passwords and `rclone.conf` match the private source.

`scripts/rpool-two-machine-test.nu` (registered in verify-all) runs two
sandbox HOMEs sharing one directory-provider private source with the real
rpool, age, age-keygen, chezmoi and rclone from PATH (skipped when any is
missing). It uses plain `dotpush`/`dotpull` (no flags) in two scenarios —
rclone.conf sync off (target already has the crypt remote) and on (target has
no rclone.conf) — covering publish, crypt-password-only change detection, a
fresh-machine pull (rclone.conf, crypt password, rpool settings, chezmoi
files), a no-op repeat pull, and the reverse direction B → A.

The real-CLI test `artifacts/rpool/scripts/portable-config-path-test.nu` uses
isolated HOME/APPDATA/XDG directories and synthetic settings. It checks active
paths, export/import, dry-run, local executable preservation, older bundles,
and invalid encryption preferences. Windows execution must be verified on
Windows; running this test on macOS proves only the macOS runtime path.
