# Cloud-wins

Cloud-wins treats a local cloud-synchronized directory as read-only source material and copies reviewed changes into a separate local workspace.

The flow is `configure -> probe -> plan -> apply -> activate -> dotpull`. `plan` is non-destructive. `apply` requires an explicit plan identifier. Target-only files are preserved by default. Replaced files are backed up and journaled for rollback.

Cloud-wins cannot prove that the local Proton Drive/other provider mirror is the newest server revision; that remains the responsibility of the provider client.
