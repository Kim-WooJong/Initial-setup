# Cloud-wins

Cloud-wins is a guarded one-way import path from a local cloud mirror, such as a Proton Drive synchronized folder, into a local Initial-setup workspace. It does not force the cloud provider itself to fetch a newer server revision.

## Safety model

1. Probe the source for stability.
2. Generate a dry-run plan.
3. Review creates and replacements.
4. Apply only with the matching plan identifier.
5. Back up replaced target files before installation.
6. Never delete target-only files by default.
7. Refuse stale plans when source or target hashes changed.
8. Keep a journal for rollback.

## Typical flow

```nu
dotcloud configure --source <cloud-mirror> --target <local-workspace>
dotcloud probe
let plan = (dotcloud plan)
$plan
dotcloud apply --plan $plan.plan_file --execute --confirm $plan.plan_id
dotcloud activate --execute --confirm activate-local-workspace
dotpull
```

Use `dotcloud status` to inspect the current state. See [`docs/wiki/Cloud-Wins.md`](docs/wiki/Cloud-Wins.md) for details.
