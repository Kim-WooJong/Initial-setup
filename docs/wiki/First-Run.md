# First Run

From the project root:

```nu
nu setup.nu
```

The entry point first checks only the files required to start safely. Release-manifest differences do not force normal setup into a no-change mode. If the current Nushell is compatible and `git` plus `chezmoi` are available, setup starts directly. Otherwise it invokes the platform bootstrap and returns to the same setup flow.

Use `nu setup.nu --diagnose` to inspect required files and release-manifest differences. The report is diagnostic only and does not choose a synchronization policy. Use `nu setup.nu --check` for strict release and project validation.

Normal setup keeps the interactive configuration workflow: when local and private managed configuration need reconciliation, choose **Review differences** to see `chezmoi status` and `chezmoi diff` before selecting push, pull, backup-and-pull, or cancel.

If Nushell does not exist yet, use `bash bootstrap.sh` on Linux/macOS or `bootstrap.ps1` on Windows once.
