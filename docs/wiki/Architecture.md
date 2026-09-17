# Architecture

The project separates public tooling from private configuration data. `setup.nu` is the stable front door. Platform bootstrap scripts exist only to prepare prerequisites when the front door cannot proceed directly. `setup-main.nu` performs the actual configuration transaction.

Private state is managed through a provider abstraction. The default directory provider can later be changed to a remote-backed provider. Safety modules implement local operation locks, provider-head checks, backups, snapshots, and guarded rollback.

Cloud-wins is intentionally separate from bidirectional synchronization: it imports from a local cloud mirror into a local workspace and does not upload back to the cloud source.
