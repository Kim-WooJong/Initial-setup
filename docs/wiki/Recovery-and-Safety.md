# Recovery and Safety

Use `dotsnapshot` before major changes and `dotrollback` to restore supported project snapshots. `dotlocalbackup` and `dotlocalrestore` protect machine-local configuration. `dotrun --status` and `dotrun --rollback` inspect or recover setup transactions.

Cloud-wins has its own journaled rollback and refuses stale plans when hashes changed. Automatic deletion of target-only Cloud-wins files is disabled by default.

## State schema migration

`dotmigrate --check` is read-only and prepares the schema migration plan for machine config, sync-state, provider-state, and vault policy files. `dotmigrate` is the only supported schema-write entrypoint.

Before the first commit, the migration transaction validates every pending state and creates SHA-256-verified recovery backups under `~/.config/dotfiles/state-migration-backups/`. Each live file is rechecked against its preflight hash before replacement. If a later commit fails, already-committed files are restored in reverse order. A transaction record is retained under `state-migration-backups/transactions/`; a `rollback-failed` record identifies the verified backups to use for manual recovery.

The vault migration backs up only `vault.nuon`. The age private identity remains machine-local and is never copied into schema-migration backups.
