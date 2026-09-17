#!/usr/bin/env bash
# Cross-platform POSIX bootstrap for Initial-setup.
# Linux is first-class: apt, dnf, pacman, zypper and apk are supported.
set -euo pipefail

MODE="auto"
DATA_DIR=""
PROFILE=""
CONFIG_POLICY="ask"
DRY_RUN=0
NO_AUTO_SYNC=0
SKIP_VSCODE=0
RESUME=0
RUN_ID=""
VALIDATE=0
QUICK_START=0
NO_SHELL_PROFILE=0
FORCE_CARGO_NU=0
ENTER_SHELL=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

section() {
    printf '\n============================================================\n'
    printf ' %s\n' "$1"
    printf '============================================================\n\n'
}

have() { command -v "$1" >/dev/null 2>&1; }

is_root() { [ "$(id -u)" -eq 0 ]; }

as_root() {
    if is_root; then
        "$@"
    elif have sudo; then
        sudo "$@"
    else
        printf '[error] Root privileges are required for: %s\n' "$*" >&2
        printf '[error] Install sudo or rerun this bootstrap as root.\n' >&2
        return 1
    fi
}

run_optional() {
    local label="$1"; shift
    printf '[run] %s\n\n' "$label"
    if ! "$@"; then
        printf '\n[warn] %s failed; continuing because this component is optional.\n' "$label" >&2
    fi
}

usage() {
    cat <<'USAGE'
Usage:
  ./bootstrap.sh [--quick-start]
                 [--mode auto|initial|existing]
                 [--data-dir PATH]
                 [--profile workstation|laptop|server|minimal]
                 [--config-policy ask|push-local|pull-private|review|backup-private|preview]
                 [--no-auto-sync]
                 [--dry-run]
                 [--resume]
                 [--run-id ID]
                 [--validate]
                 [--skip-vscode]
                 [--no-shell-profile]
                 [--cargo-nu]
                 [--enter-shell]

Recommended entry point when Nushell is already installed:
  nu setup.nu

Fallback when Nushell is not installed on Linux/macOS:
  bash bootstrap.sh

--quick-start chooses a sensible profile/data directory and a conservative
first-run synchronization policy. Existing private configuration is reviewed
instead of silently overwritten.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --quick-start) QUICK_START=1; shift ;;
        --mode) MODE="${2:?missing --mode value}"; shift 2 ;;
        --data-dir) DATA_DIR="${2:?missing --data-dir value}"; shift 2 ;;
        --profile) PROFILE="${2:?missing --profile value}"; shift 2 ;;
        --config-policy) CONFIG_POLICY="${2:?missing --config-policy value}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --no-auto-sync) NO_AUTO_SYNC=1; shift ;;
        --skip-vscode) SKIP_VSCODE=1; shift ;;
        --resume) RESUME=1; shift ;;
        --run-id) RUN_ID="${2:?missing --run-id value}"; shift 2 ;;
        --validate) VALIDATE=1; shift ;;
        --no-shell-profile) NO_SHELL_PROFILE=1; shift ;;
        --cargo-nu) FORCE_CARGO_NU=1; shift ;;
        --enter-shell) ENTER_SHELL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$MODE" in auto|initial|existing) ;; *) echo "[error] invalid --mode: $MODE" >&2; exit 2 ;; esac
case "$CONFIG_POLICY" in ask|push-local|pull-private|review|backup-private|preview|keep-local|keep-private) ;; *) echo "[error] invalid --config-policy: $CONFIG_POLICY" >&2; exit 2 ;; esac
case "$PROFILE" in ''|workstation|laptop|server|minimal) ;; *) echo "[error] invalid --profile: $PROFILE" >&2; exit 2 ;; esac

linux_desktop_present() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${XDG_CURRENT_DESKTOP:-}" ]
}

linux_is_wsl() {
    grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null || grep -qi microsoft /proc/version 2>/dev/null
}

choose_quick_defaults() {
    [ "$QUICK_START" -eq 1 ] || return 0

    if [ -z "$PROFILE" ]; then
        case "$(uname -s)" in
            Linux)
                # WSL can expose DISPLAY via WSLg even when the intended setup is
                # primarily a shell/dev environment. Default it to server; users
                # can explicitly request --profile workstation for Linux GUI apps.
                if linux_is_wsl; then
                    PROFILE="server"
                elif linux_desktop_present; then
                    PROFILE="workstation"
                else
                    PROFILE="server"
                fi
                ;;
            Darwin) PROFILE="workstation" ;;
        esac
    fi

    # Preserve existing machine configuration: setup.nu will reuse its saved
    # data_root when --data-dir is omitted.
    local machine_config="$HOME/.config/dotfiles/config.nuon"
    if [ -z "$DATA_DIR" ] && [ ! -f "$machine_config" ]; then
        case "$(uname -s)" in
            Linux) DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/initial-setup/private" ;;
            Darwin) DATA_DIR="$HOME/Library/Application Support/Initial-setup/private" ;;
        esac
    fi

    if [ "$CONFIG_POLICY" = "ask" ] && [ ! -f "$machine_config" ]; then
        # Existing source is never silently pulled over local files. Let review
        # show a diff and ask for direction. A brand-new source captures local
        # state so a fresh workstation becomes useful in one pass.
        if [ -n "$DATA_DIR" ] && { [ -e "$DATA_DIR/.chezmoiroot" ] || [ -d "$DATA_DIR/home" ]; }; then
            CONFIG_POLICY="review"
        else
            CONFIG_POLICY="push-local"
        fi
    fi
}

choose_quick_defaults

install_homebrew_macos() {
    if have brew; then return 0; fi
    if ! have curl; then printf '[error] curl is required to install Homebrew.\n' >&2; return 1; fi
    section "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)";
    elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
    have brew
}

install_macos_core() {
    install_homebrew_macos || return 1
    section "Installing core prerequisites"
    brew install git neovim chezmoi openssl cmake pkg-config curl || return 1
    if ! xcode-select -p >/dev/null 2>&1; then
        printf '[error] Xcode command-line tools are required. Run: xcode-select --install\n' >&2
        return 1
    fi
    if [ "$SKIP_VSCODE" -eq 0 ]; then run_optional "Install VS Code" brew install --cask visual-studio-code; fi
}

install_chezmoi_fallback() {
    if have chezmoi; then return 0; fi
    if ! have curl; then return 1; fi
    mkdir -p "$HOME/.local/bin"
    # Official installer. It writes only to the requested user bin directory.
    sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin" || return 1
    export PATH="$HOME/.local/bin:$PATH"
    have chezmoi
}

install_linux_core() {
    section "Installing Linux core prerequisites"
    if have apt-get; then
        as_root apt-get update
        as_root apt-get install -y ca-certificates curl git tar gzip xz-utils unzip build-essential pkg-config libssl-dev
        if ! have nvim; then run_optional "Install Neovim with apt" as_root apt-get install -y neovim; fi
        if ! have chezmoi; then run_optional "Install chezmoi with apt" as_root apt-get install -y chezmoi; fi
    elif have dnf; then
        as_root dnf install -y ca-certificates curl git tar gzip xz unzip gcc gcc-c++ make pkgconf-pkg-config openssl-devel
        if ! have nvim; then run_optional "Install Neovim with dnf" as_root dnf install -y neovim; fi
        if ! have chezmoi; then run_optional "Install chezmoi with dnf" as_root dnf install -y chezmoi; fi
    elif have pacman; then
        as_root pacman -Sy --needed --noconfirm ca-certificates curl git tar gzip xz unzip base-devel openssl pkgconf
        if ! have nvim; then run_optional "Install Neovim with pacman" as_root pacman -S --needed --noconfirm neovim; fi
        if ! have chezmoi; then run_optional "Install chezmoi with pacman" as_root pacman -S --needed --noconfirm chezmoi; fi
    elif have zypper; then
        as_root zypper --non-interactive refresh
        as_root zypper --non-interactive install ca-certificates curl git tar gzip xz unzip gcc gcc-c++ make pkg-config libopenssl-devel
        if ! have nvim; then run_optional "Install Neovim with zypper" as_root zypper --non-interactive install neovim; fi
        if ! have chezmoi; then run_optional "Install chezmoi with zypper" as_root zypper --non-interactive install chezmoi; fi
    elif have apk; then
        as_root apk add --no-cache ca-certificates curl git tar gzip xz unzip build-base pkgconf openssl-dev
        if ! have nvim; then run_optional "Install Neovim with apk" as_root apk add --no-cache neovim; fi
        if ! have chezmoi; then run_optional "Install chezmoi with apk" as_root apk add --no-cache chezmoi; fi
    else
        printf '[error] Unsupported Linux package manager. Supported: apt, dnf, pacman, zypper, apk.\n' >&2
        return 1
    fi

    install_chezmoi_fallback || { printf '[error] chezmoi could not be installed.\n' >&2; return 1; }
}

ensure_cargo() {
    export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
    export PATH="$CARGO_HOME/bin:$PATH"
    if have rustup || { have cargo && have rustc; }; then return 0; fi
    if ! have curl; then return 1; fi
    local installer
    installer="$(mktemp)" || return 1
    if ! curl --proto '=https' --tlsv1.2 --fail --show-error --location --max-time 120 https://sh.rustup.rs -o "$installer"; then
        rm -f "$installer"; return 1
    fi
    sh "$installer" -y --profile minimal --default-toolchain stable --no-modify-path
    local status=$?
    rm -f "$installer"
    [ "$status" -eq 0 ] && { have rustup || { have cargo && have rustc; }; }
}

ensure_shell_path() {
    [ "$NO_SHELL_PROFILE" -eq 0 ] || return 0
    [ "$(uname -s)" = "Linux" ] || return 0
    local profile="$HOME/.profile"
    local begin='# >>> Initial-setup user bin >>>'
    local end='# <<< Initial-setup user bin <<<'
    if [ -f "$profile" ] && grep -Fq "$begin" "$profile"; then return 0; fi
    mkdir -p "$HOME/.local/bin"
    {
        printf '\n%s\n' "$begin"
        printf 'for initial_setup_bin in "$HOME/.local/bin" "$HOME/.cargo/bin" "$HOME/.juliaup/bin"; do\n'
        printf '    case ":$PATH:" in *":$initial_setup_bin:"*) ;; *) PATH="$initial_setup_bin:$PATH" ;; esac\n'
        printf 'done\n'
        printf 'unset initial_setup_bin\n'
        printf 'export PATH\n'
        printf '%s\n' "$end"
    } >> "$profile"
    printf '[ok] Added user tool directories to future login-shell PATH via %s\n' "$profile"
}

section "Initial-setup bootstrap"
printf 'OS            : %s\n' "$(uname -s)"
printf 'Architecture  : %s\n' "$(uname -m)"
printf 'Profile       : %s\n' "${PROFILE:-auto}"
printf 'Data root     : %s\n' "${DATA_DIR:-saved/default}"
printf 'Config policy : %s\n' "$CONFIG_POLICY"
if [ "$(uname -s)" = "Linux" ] && linux_is_wsl; then printf 'Environment   : WSL detected\n'; fi

if [ "$DRY_RUN" -eq 0 ] && [ "$CONFIG_POLICY" != "preview" ]; then
    case "$(uname -s)" in
        Darwin) install_macos_core ;;
        Linux) install_linux_core ;;
        *) printf '[error] Unsupported operating system. Use bootstrap.ps1 on Windows.\n' >&2; exit 1 ;;
    esac
    ensure_shell_path
    for required in chezmoi git curl tar; do
        if ! have "$required"; then printf '[error] Missing dependency after bootstrap: %s\n' "$required" >&2; exit 1; fi
    done
fi

section "Preparing Nushell runtime"
NU_RUNTIME=""
if [ "$FORCE_CARGO_NU" -eq 0 ]; then
    RELEASE_ARGS=()
    if [ "$DRY_RUN" -eq 1 ] || [ "$CONFIG_POLICY" = "preview" ]; then RELEASE_ARGS+=(--check); fi
    if [ "$NO_SHELL_PROFILE" -eq 1 ]; then RELEASE_ARGS+=(--no-link); fi
    if NU_RUNTIME="$(bash "$ROOT/scripts/posix/prepare-nu-release.sh" "${RELEASE_ARGS[@]}")"; then
        export INITIAL_SETUP_NU_SESSION_PROVIDER="release-v1"
    else
        NU_RUNTIME=""
        if [ "$DRY_RUN" -eq 1 ] || [ "$CONFIG_POLICY" = "preview" ]; then
            printf '[error] A compatible Nushell is required for a no-change preview. Install Nu >=0.109.1 or run a normal bootstrap first.\n' >&2
            exit 1
        fi
        printf '[warn] Prebuilt Nushell path unavailable; falling back to Cargo build.\n' >&2
    fi
fi

if [ -z "$NU_RUNTIME" ]; then
    ensure_cargo || { printf '[error] Rust/Cargo fallback could not be prepared.\n' >&2; exit 1; }
    PREPARE_ARGS=()
    if [ "$DRY_RUN" -eq 1 ] || [ "$CONFIG_POLICY" = "preview" ]; then PREPARE_ARGS+=(--check); fi
    NU_RUNTIME="$(bash "$ROOT/scripts/posix/prepare-nu-cargo.sh" "${PREPARE_ARGS[@]}")"
    export INITIAL_SETUP_NU_SESSION_PROVIDER="cargo-v1"
fi

if [ ! -x "$NU_RUNTIME" ]; then printf '[error] Selected Nushell runtime is not executable: %s\n' "$NU_RUNTIME" >&2; exit 1; fi
export INITIAL_SETUP_NU_SESSION_EXE="$NU_RUNTIME"
if [ "$SKIP_VSCODE" -eq 1 ]; then export INITIAL_SETUP_SKIP_VSCODE="1"; fi
INITIAL_SETUP_NU_SESSION_VERSION="$("$NU_RUNTIME" --version)"
export INITIAL_SETUP_NU_SESSION_VERSION
export PATH="$(dirname "$NU_RUNTIME"):$HOME/.local/bin:${CARGO_HOME:-$HOME/.cargo}/bin:$HOME/.juliaup/bin:$PATH"

section "Starting Initial-setup"
NU_ARGS=("$ROOT/setup.nu" "--mode" "$MODE" "--config-policy" "$CONFIG_POLICY")
[ -n "$DATA_DIR" ] && NU_ARGS+=("--data-dir" "$DATA_DIR")
[ -n "$PROFILE" ] && NU_ARGS+=("--profile" "$PROFILE")
[ "$NO_AUTO_SYNC" -eq 1 ] && NU_ARGS+=("--no-auto-sync")
[ "$DRY_RUN" -eq 1 ] && NU_ARGS+=("--dry-run")
[ "$RESUME" -eq 1 ] && NU_ARGS+=("--resume")
[ -n "$RUN_ID" ] && NU_ARGS+=("--run-id" "$RUN_ID")
[ "$VALIDATE" -eq 1 ] && NU_ARGS+=("--validate")

"$NU_RUNTIME" --no-config-file "${NU_ARGS[@]}"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then printf '[error] setup.nu exited with code %s\n' "$STATUS" >&2; exit "$STATUS"; fi

section "Bootstrap complete"
printf 'Nushell runtime : %s\n' "$NU_RUNTIME"
printf 'Version         : %s\n' "$INITIAL_SETUP_NU_SESSION_VERSION"
printf 'Profile         : %s\n' "${PROFILE:-saved}"
printf '\nReady commands:\n  nu\n  dotdoctor\n  dotstatus\n\n'
if [ "$(uname -s)" = "Linux" ] && linux_is_wsl; then
    printf 'WSL note: automatic sync uses systemd --user when available; otherwise manual `dotsync` remains available.\n'
fi

if [ "$ENTER_SHELL" -eq 1 ] && [ -t 0 ] && [ -t 1 ]; then
    printf '\n[ready] Entering the configured Nushell. Exit with `exit`.\n'
    unset INITIAL_SETUP_NU_SESSION_EXE INITIAL_SETUP_NU_SESSION_VERSION INITIAL_SETUP_NU_SESSION_PROVIDER
    unset INITIAL_SETUP_SKIP_VSCODE 2>/dev/null || true
    exec "$NU_RUNTIME"
fi
