# Development and Testing

Use [Code Architecture and Maintenance Map](Code-Architecture.md) before changing unfamiliar areas. Its change map identifies the owning layer and the first files to inspect.

## Working-tree validation

During development, run:

```nu
nu verify.nu --working-tree
```

This allows release-manifest drift to be reported while continuing the other validation layers.

For strict release validation:

```nu
nu setup.nu --check
```

For diagnostic-only entry checks:

```nu
nu setup.nu --diagnose
```

## Validation layers

The main path is `verify.nu` -> `scripts/verify-all.nu`. It combines repository validation, syntax checks, behavioral tests, and architectural policy tests. Focused policy tests protect external-command handling, installer health checks, setup orchestration, synchronization/recovery behavior, diagnostics, and documentation coverage.

Important regression areas include entry-point routing, partial archive rejection, runtime selection, process diagnostics, lock behavior, provider-head concurrency, verified staging, backup/rollback recovery, Cloud-wins plan/apply/rollback, and command-reference coverage.

## Documentation maintenance

- Keep all Markdown documentation in English.
- Keep long-lived architecture and behavior under `docs/wiki/`.
- Update `Code-Architecture.md` when ownership boundaries or call relationships change.
- Update `Command-Reference.md` when the public `dot*` command surface changes.
- Do not create per-version audit, migration, or testing Markdown files.
- Release history belongs in `CHANGELOG.md`.
