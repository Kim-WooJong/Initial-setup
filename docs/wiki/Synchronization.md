# Synchronization

For routine use, prefer `dotctl status`, `dotctl push`, `dotctl pull`, and `dotctl sync`. The original `dotstatus`, `dotpush`, `dotpull`, and `dotsync` commands remain supported compatibility entry points. `dotresolve` remains the advanced protected-file merge tool.

Automatic synchronization is optional. If systemd user services or another supported scheduler are unavailable, setup should still complete and manual synchronization remains available.

Before destructive direction changes, use `dotctl preflight --diff` and create a snapshot.


## Separate rclone-only push and pull

`dotrpush` and `dotrpull` provide an additional explicit rclone transport without changing `sync-provider.nuon`. This is intentionally separate from the normal `dotctl push` / `dotctl pull` path.

```nu
# First use
dotrpush --remote "proton:Initial-setup-store" --save-remote

# Reuse the saved dedicated remote
dotrpush
dotrpull
```

Isolation rules:

- the normal provider configuration is not rewritten;
- a separate provider-state scope is used for the rclone-only remote;
- successful rclone-only pulls record a scoped local/cloud baseline under `sync-states/`, while the normal `sync-state.nuon` baseline is not advanced;
- `dotrpush` does not run the live recapture phase, so it cannot mutate a normal Proton/OneDrive-backed private source just to perform the rclone upload;
- `dotrpull` fetches a verified revision into temporary staging and applies from staging instead of installing the revision into the normal provider source;
- the shared operation lock is still used, so normal sync and rclone-only sync cannot mutate local configuration concurrently.

If no dedicated remote was saved, the commands may reuse the normal provider remote only when that provider is already `rclone`. Otherwise `--remote` is required.

## Manual conflict direction

`dotctl push` (compatibility alias: `dotpush`) is the explicit local-authoritative direction for the normal `directory` provider. If that provider changed since this machine's saved provider baseline, the manual command first preserves the complete current provider payload in a verified `~/.config/dotfiles/sync-recovery/<id>` copy, prints both revisions and the recovery path, then continues from the newly reviewed head. Automatic/background push remains fail-closed and never uses this manual recovery path.

`dotctl pull` (compatibility alias: `dotpull`) and the advanced `dotrpull` transport compare the current live-machine fingerprint with the last successful local sync baseline before applying an incoming source. If live configuration changed after that baseline, the pull prints the incoming chezmoi diff. A manual interactive `dotctl pull` then asks whether to keep the private source; the default is cancel. `--discard-local` is the explicit non-interactive way to permit that replacement. Use `dotctl push` when the local edits should win.

When `features.rclone_config` is enabled, normal push/pull also own encrypted `rclone.conf` synchronization. Push resolves the machine's active config path, registers it in the machine-local age vault if needed, and writes only `secrets/rclone.age` into the synchronized payload. Pull first authenticates/decrypts a changed incoming ciphertext into a restricted machine-local staging directory **before** chezmoi or other live configuration is applied. If authentication succeeds, the same staged plaintext is committed later in the pull transaction, after preserving a verified private backup under `~/.config/dotfiles/rclone-restore-backups/<id>`. A missing/wrong identity, corrupt ciphertext, or ciphertext that changes during preflight stops the pull before live configuration is modified. The age identity and `vault.nuon` remain machine-local; they must be restored separately on a new machine before encrypted rclone data can be decrypted.


## rpool portable configuration

Initial-setup integrates with rpool through rpool's own portable artifact contract (`rpool export <root>` / `rpool import <root>`), falling back to the legacy JSON-only `config export` / `config import` on older rpool builds.

- `dotctl push` exports the current portable state to `<data_root>/rpool/config/portable-config.json`. When crypt remotes exist, their `password`/`password2` are exported to `<data_root>/rpool/secrets/rclone.age`, age-encrypted to the machine vault's single recipient; without a configured vault the push stops with `dotvault init` guidance. Unchanged configuration and (decrypted) secrets keep the existing files, so the random age ciphertext does not create a new revision on every push.
- `dotctl pull` checks before applying anything that an incoming `rclone.age` can be decrypted (vault, identity, `age`, artifact-capable rpool). After the incoming encrypted rclone configuration is committed, it stages the artifact privately, runs `rpool import --dry-run`, then imports. Crypt passwords are restored only into crypt remotes that already exist in the target `rclone.conf` with the same structure; a missing remote stops with a hint.
- The synchronized bundle includes portable Pools, remote roots/default paths, remotes, shard sizing, worker/retry settings, RS K+M, placement, and portable GUI defaults as defined by rpool.
- The full `rclone.conf` (all provider tokens) remains owned by Initial-setup's separate age-encrypted top-level `secrets/rclone.age` flow; `rpool/secrets/rclone.age` is a different file that holds only rpool crypt-remote passwords. Inventory, history, journals, and machine-specific rclone executable paths are not synchronized through the portable rpool bundle.
- If rpool is not installed, Initial-setup keeps any existing synchronized bundle and skips the local rpool step instead of blocking unrelated dotfiles synchronization.

Use `dotctl config rpool` to inspect readiness. Manual capture and import preview are available through `dotctl config rpool --capture` and `dotctl config rpool --restore --dry-run`.
