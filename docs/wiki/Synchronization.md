# Synchronization

Use `dotstatus` to inspect state, `dotpush` to publish reviewed local source changes, `dotpull` to apply private source changes, and `dotsync` for the normal bidirectional workflow. `dotresolve` handles protected-file conflicts and merge decisions.

Automatic synchronization is optional. If systemd user services or another supported scheduler are unavailable, setup should still complete and manual synchronization remains available.

Before destructive direction changes, use `dotpreflight --diff` and create a snapshot.
