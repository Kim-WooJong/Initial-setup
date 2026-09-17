# Linux Installation

## Normal path

If Nushell is installed:

```nu
nu setup.nu
```

This command is the normal Linux entry point as well as the normal Windows/macOS entry point. Missing native prerequisites are delegated to `bootstrap.sh` automatically.

## No Nushell installed

```sh
bash bootstrap.sh
```

The bootstrap supports apt, dnf, pacman, zypper, and apk based systems. Bash must already be available. It installs core prerequisites, prepares a compatible Nushell runtime, and then invokes `setup.nu`.

WSL defaults can be selected explicitly with `--profile server`; GUI Linux machines can use `--profile workstation`.
