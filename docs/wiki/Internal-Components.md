# Internal Components

For the full maintainer call graph, script families, state layout, and change map, see [Code Architecture and Maintenance Map](Code-Architecture.md).

| Path | Purpose | Stability expectation |
|---|---|---|
| `setup.nu` | Canonical user-facing entry point and prerequisite routing | Stable public entry |
| `setup-main.nu` | Setup transaction, required/optional stages, resume/finalization | Central orchestration |
| `bootstrap.sh` | POSIX prerequisite/runtime preparation when Nushell is unavailable | Bootstrap only |
| `bootstrap.ps1` | Windows prerequisite/runtime preparation when Nushell is unavailable | Bootstrap only |
| `scripts/modules/subprocess.nu` | Shared non-interactive process result contract | Low-level infrastructure |
| `scripts/modules/core.nu` | Machine paths and failure normalization | Low-level infrastructure |
| `scripts/modules/safety.nu` | Locks, atomic records, private permissions, path/tree verification | Low-level infrastructure |
| `scripts/modules/dotfiles.nu` | Installed public `dot*` command facade | User-command API |
| `scripts/modules/sync-provider.nu` | Provider abstraction, baselines, revisions, verified workspace transfer | Sync core |
| `scripts/modules/diagnostics.nu` | Structured tool/command diagnostics | Diagnostic core |
| `scripts/modules/run-state.nu` | Setup transaction checkpoints and resume state | Setup state |
| `scripts/modules/cloud-wins-*.nu` | Local Cloud-wins state and Rust engine integration | One-way import control |
| `scripts/*.nu` | Focused setup, sync, recovery, maintenance, and validation endpoints | Implementation endpoints |
| `profiles/` | Workstation/laptop/server/minimal feature policy | Declarative policy |
| `tools/cloudwins/` | Rust Cloud-wins engine | Optional helper |
| `docs/wiki/` | Long-lived English documentation | Maintained documentation |
