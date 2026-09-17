# Troubleshooting

## `setup.nu does not exist`

Run the command from the extracted project root, where `setup.nu` is visible:

```nu
ls
nu setup.nu --diagnose
```

## Nushell is too old

Run `nu setup.nu`. The entry point routes to the platform bootstrap when the current Nu is below the supported runtime minimum.

## Nushell is not installed

Use `bash bootstrap.sh` on Linux/macOS or `bootstrap.ps1` on Windows once.

## Setup stopped

Run `dotdoctor`, inspect `dotrun --status`, and use `nu setup.nu --check` to separate project validation failures from machine configuration failures.


## `manifest_status` is `changed`

`nu setup.nu --diagnose` reports release-manifest drift for review, but normal `nu setup.nu` does not stop solely because a release hash changed. Use `nu setup.nu --check` when strict release-byte validation is required.

If normal setup reaches configuration reconciliation, use the **Review differences** choice to inspect `chezmoi status` and `chezmoi diff` before deciding which side should be authoritative.

## Starship initialization fails

Run these commands directly:

```nu
starship --version
starship init nu | complete
```

`setup-starship.nu` now performs the same health check and prints the failing executable path, exit code, and stderr. A broken Starship integration is optional and no longer aborts the rest of setup.

If WinGet owns the broken Windows installation, rerun `nu setup.nu`; the Starship installation stage attempts a WinGet upgrade and then a Cargo fallback when necessary. The existing `vendor/autoload/starship.nu` is not replaced until a new init script has been generated successfully.
