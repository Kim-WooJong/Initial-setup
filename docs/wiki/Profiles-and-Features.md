# Profiles and Features

Profiles choose sensible defaults without changing the core synchronization model.

- `workstation`: GUI development applications and full tooling.
- `laptop`: workstation-oriented configuration with portable defaults.
- `server`: terminal/server tools without unnecessary GUI dependencies.
- `minimal`: small base environment for recovery or constrained systems.

Pass a profile explicitly with `nu setup.nu --profile <name>`. Existing machine configuration is preserved unless setup is intentionally reset or reconfigured.
