# Start Here

Run this from the extracted project root:

```nu
nu setup.nu
```

If Nushell is not installed, use `bash bootstrap.sh` on Linux/macOS or `bootstrap.ps1` on Windows once. After Nushell exists, use `nu setup.nu` for normal setup and maintenance.

The setup orchestrator owns the terminal directly, so selection prompts are interactive. If you interrupt setup with Ctrl+C, the run is marked `interrupted` and the printed `--resume --run-id ...` command can continue it later.

For project diagnostics:

```nu
nu setup.nu --diagnose
```

For the validation suite:

```nu
nu setup.nu --check
```

See [`docs/wiki/Home.md`](docs/wiki/Home.md) for the full documentation.
