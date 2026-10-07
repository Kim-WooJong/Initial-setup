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

After setup, routine operation is intentionally centered on `dotctl`:

```nu
dotctl status
dotctl diff
dotctl push
dotctl pull
dotctl sync
dotctl config
dotctl doctor
dotctl update
```

Use `dotctl` for the compact built-in command overview. Recovery/configuration commands such as `dotctl backup`, `dotctl restore --list`, `dotctl preflight --diff`, and `dotctl config rclone` remain available when needed. Older `dot*` commands are retained for advanced workflows and compatibility with existing scripts.

See [`docs/wiki/Home.md`](docs/wiki/Home.md) for the full documentation and [`docs/wiki/Command-Reference.md`](docs/wiki/Command-Reference.md) for the advanced/compatibility command list.
