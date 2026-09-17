# Recovery and Safety

Use `dotsnapshot` before major changes and `dotrollback` to restore supported project snapshots. `dotlocalbackup` and `dotlocalrestore` protect machine-local configuration. `dotrun --status` and `dotrun --rollback` inspect or recover setup transactions.

Cloud-wins has its own journaled rollback and refuses stale plans when hashes changed. Automatic deletion of target-only Cloud-wins files is disabled by default.
