# Synchronization

Use `dotstatus` to inspect state, `dotpush` to publish reviewed local source changes, `dotpull` to apply private source changes, and `dotsync` for the normal bidirectional workflow. `dotresolve` handles protected-file conflicts and merge decisions.

Automatic synchronization is optional. If systemd user services or another supported scheduler are unavailable, setup should still complete and manual synchronization remains available.

Before destructive direction changes, use `dotpreflight --diff` and create a snapshot.


## Separate rclone-only push and pull

`dotrpush` and `dotrpull` provide an additional explicit rclone transport without changing `sync-provider.nuon`. This is intentionally separate from `dotpush`/`dotpull`.

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

## Manual pull local-change guard

`dotpull` and `dotrpull` compare the current live-machine fingerprint with the last successful local sync baseline before applying an incoming source. If the live configuration changed after that baseline, the pull prints the incoming chezmoi diff and stops without changing the live configuration or private workspace. Use `dotpush` when the local edits should win. Use `--discard-local` only after reviewing the diff when the incoming private source should replace those edits.
