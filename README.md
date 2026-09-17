# Initial-setup v0.12.25

Cross-platform development environment bootstrap and configuration synchronization for Windows, macOS, and Linux.

The project manages package installation, dotfiles, Git/SSH settings, toolchains, backups, recovery, and private configuration synchronization from a single entry point.

## Quick Start

### Windows

If Nushell is already installed:

```powershell
cd C:\path\to\Initial-setup
nu --no-config-file .\setup.nu
```

On a new machine without Nushell:

```powershell
cd C:\path\to\Initial-setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

### macOS / Linux

If Nushell is already installed:

```bash
nu --no-config-file setup.nu
```

Or use the bootstrap script:

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

## First Setup

The normal entry point is:

```nu
nu setup.nu
```

During first setup, choose how local and private configuration should be reconciled:

- **Review** — inspect differences before choosing a direction
- **Push local** — save this machine's configuration to the private source
- **Pull private** — apply the private source to this machine
- **Backup + pull** — back up local configuration, then apply private configuration
- **Preview** — show planned changes without applying them

You can also select a profile:

```nu
nu setup.nu --profile workstation
nu setup.nu --profile laptop
nu setup.nu --profile server
nu setup.nu --profile minimal
```

## Common Commands

```nu
dotpush                 # Save local managed configuration to the private source
dotpull                 # Apply private configuration to this machine
dotresolve              # Resolve local/private conflicts
dotpreflight --diff     # Review configuration differences
dotaudit                # Audit the managed environment
dotdoctor               # Check environment health
dotsshkeys              # Check SSH key pairs
dotlocalbackup          # Back up machine-local configuration
dotlocalrestore         # Restore a local configuration backup
dotrun --list           # Show setup transaction history
```

## Synchronization Providers

Initial-setup supports three provider types:

- **directory** — existing cloud-synchronized folder
- **local** — local disk, NAS, or shared filesystem
- **rclone** — revision-based remote storage through rclone

The current default remains the `directory` provider.

For directory providers:

- same-machine serialization uses `operation.lock`
- cross-machine changes are detected using revision/tree fingerprints
- old `.initial-setup-write.lock` files from earlier releases are ignored

Check the current provider with:

```nu
dotbackend status
```

The planned migration toward rclone as the primary provider is documented in [ROADMAP.md](ROADMAP.md).

## Secrets

Machine-local secrets are not stored as plaintext in the project repository.

Secret management uses the local vault workflow:

```nu
dotvault status
dotvault init
```

SSH private keys remain machine-local.

## Backup and Recovery

Create a snapshot:

```nu
dotsnapshot
```

Restore a snapshot:

```nu
dotrollback
```

Resume an interrupted setup:

```nu
nu setup.nu --resume
```

Inspect previous runs:

```nu
dotrun --list
dotrun --status
dotrun --logs
```

## Validation

Normal setup does **not** scan every project source file before running.

For development or debugging, run validation explicitly:

```nu
dotvalidate
dottest --sandbox
```

Or start setup with full validation:

```nu
nu setup.nu --validate
```

Full validation is still required by the release workflow.

## Troubleshooting

### A lock already exists

Inspect current locks:

```nu
nu --no-config-file scripts/lock-status.nu
```

Do not delete active lock files blindly.

### Unexpected private-source changes

Review them first:

```nu
dotpreflight --diff
dotresolve
```

### Setup stopped midway

Resume the recorded transaction:

```nu
nu setup.nu --resume
```

### rclone is missing

Normal setup attempts to install rclone automatically when required.

You can also check/install it directly:

```nu
nu --no-config-file scripts/install-rclone.nu --check
nu --no-config-file scripts/install-rclone.nu
```

## Project Files

```text
setup.nu        Main entry point
profiles/       Machine role profiles
packages/       Package manifests
scripts/        Setup, sync, backup, and recovery tools
templates/      Local configuration templates
CHANGELOG.md    Version history
ROADMAP.md      Future development plan
```

## Notes

- Keep private keys, tokens, passwords, and other credentials out of the repository.
- Use `dotlocalbackup` before large manual configuration changes.
- Use `dotpreflight --diff` before accepting unexpected private-source changes.
- See [CHANGELOG.md](CHANGELOG.md) for detailed release history.
- See [ROADMAP.md](ROADMAP.md) for planned synchronization and stabilization work.
