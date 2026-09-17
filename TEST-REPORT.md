# Initial-setup v0.12.21 — directory provider local-lock migration

Date: 2026-09-17. Base: v0.12.20.

## Change

The `directory` backend no longer creates or acquires
`.initial-setup-write.lock` inside the cloud-synchronized data root.

It now acquires a machine-local provider lock under:

`~/.config/dotfiles/locks/provider-<provider-id>.lock`

The global `operation.lock` remains unchanged.

Cross-machine protection for directory/cloud-mirror providers is optimistic:
`provider-state.nuon` stores the previously observed revision/tree hash and
`assert-expected-head` rejects a write when the mirror changed since the last
trusted observation.

A true `local` shared-filesystem/NAS provider still uses a cooperative
`.initial-setup-write.lock` in the shared filesystem. The rclone provider still
uses revision checks rather than a distributed lock.

Existing cloud `.initial-setup-write.lock` entries are legacy diagnostics only.
The project reports their presence but does not probe or delete them
automatically.

## Verification performed in authoring environment

- Active `remote-lock` block contains no directory-data-root lock creation.
- Directory provider uses `provider-local-lock-path`.
- Revision and tree-hash mismatch checks remain present.
- `lock-status.nu` probes the machine-local provider lock and reports legacy
  cloud lock entries without probing them automatically.
- `backend-control.nu` reports provider lock scope and legacy-lock presence.
- Security self-test source includes local-lock and mirror-change regression
  cases.
- No `.nu` file begins a physical line with `+`.
- `bash -n bootstrap.sh` passed.
- `.github` remains absent.
- Release ZIP integrity and manifest hashes are checked during packaging.
- Patch from clean v0.12.20 is reapplied in-place and compared with the final
  tree.

Nushell is not installed in the authoring container, so actual `nu-check` and
runtime execution of the modified Nu files are not claimed here.
