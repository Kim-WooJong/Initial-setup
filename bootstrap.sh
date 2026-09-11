#!/usr/bin/env bash
set -u

MODE="auto"
DATA_DIR=""
NO_AUTO_SYNC=0
SKIP_VSCODE=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

section() {
    printf '\n============================================================\n'
    printf ' %s\n' "$1"
    printf '============================================================\n\n'
}

have() {
    command -v "$1" >/dev/null 2>&1
}

run_optional() {
    local label="$1"
    shift

    printf '[run] %s\n\n' "$label"

    "$@"
    local status=$?

    if [ "$status" -ne 0 ]; then
        printf '\n[warn] %s returned exit code %s\n' "$label" "$status"
    fi

    return 0
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        --no-auto-sync)
            NO_AUTO_SYNC=1
            shift
            ;;
        --skip-vscode)
            SKIP_VSCODE=1
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage:
  ./bootstrap.sh [--mode auto|initial|existing]
                 [--data-dir PATH]
                 [--no-auto-sync]
                 [--skip-vscode]
EOF
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

install_homebrew_macos() {
    if have brew; then
        return 0
    fi

    if ! have curl; then
        printf '[error] curl is required to install Homebrew.\n' >&2
        return 1
    fi

    section "Installing Homebrew"

    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    have brew
}

install_macos_core() {
    install_homebrew_macos || return 1

    section "Installing core prerequisites"

    brew install git nushell neovim chezmoi || return 1

    if [ "$SKIP_VSCODE" -eq 0 ]; then
        run_optional "Install VS Code" brew install --cask visual-studio-code
    fi
}

install_nushell_debian() {
    if have nu; then
        return 0
    fi

    sudo apt-get install -y wget ca-certificates gnupg || return 1
    sudo mkdir -p /etc/apt/keyrings

    wget -qO- https://apt.fury.io/nushell/gpg.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/fury-nushell.gpg

    printf '%s\n' \
        'deb [signed-by=/etc/apt/keyrings/fury-nushell.gpg] https://apt.fury.io/nushell/ /' \
        | sudo tee /etc/apt/sources.list.d/fury-nushell.list >/dev/null

    sudo apt-get update || return 1
    sudo apt-get install -y nushell
}

install_nushell_fedora() {
    if have nu; then
        return 0
    fi

    cat <<'EOF' | sudo tee /etc/yum.repos.d/fury-nushell.repo >/dev/null
[gemfury-nushell]
name=Gemfury Nushell Repo
baseurl=https://yum.fury.io/nushell/
enabled=1
gpgcheck=0
gpgkey=https://yum.fury.io/nushell/gpg.key
EOF

    sudo dnf install -y nushell
}

install_chezmoi_fallback() {
    if have chezmoi; then
        return 0
    fi

    if ! have curl; then
        return 1
    fi

    mkdir -p "$HOME/.local/bin"

    sh -c "$(curl -fsLS https://get.chezmoi.io)" -- \
        -b "$HOME/.local/bin" || return 1

    export PATH="$HOME/.local/bin:$PATH"
    have chezmoi
}

install_linux_core() {
    section "Installing core prerequisites"

    if have apt-get; then
        sudo apt-get update || return 1
        sudo apt-get install -y git curl neovim || return 1
        install_nushell_debian || return 1

        if ! have chezmoi; then
            run_optional "Install chezmoi with apt" sudo apt-get install -y chezmoi
        fi

    elif have dnf; then
        sudo dnf install -y git curl neovim || return 1
        install_nushell_fedora || return 1

        if ! have chezmoi; then
            run_optional "Install chezmoi with dnf" sudo dnf install -y chezmoi
        fi

    elif have pacman; then
        sudo pacman -S --needed --noconfirm git curl neovim nushell chezmoi || return 1

    elif have zypper; then
        sudo zypper --non-interactive install git curl neovim nushell chezmoi || return 1

    elif have apk; then
        sudo apk add git curl neovim chezmoi || return 1

        if ! have nu; then
            printf '%s\n' 'https://alpine.fury.io/nushell/' \
                | sudo tee -a /etc/apk/repositories >/dev/null
            sudo apk update || return 1
            sudo apk add --allow-untrusted nushell || return 1
        fi

    else
        printf '[error] Unsupported Linux package manager.\n' >&2
        return 1
    fi

    install_chezmoi_fallback || {
        printf '[error] chezmoi could not be installed.\n' >&2
        return 1
    }
}

section "Initial-setup 0.5.0 bootstrap"

case "$(uname -s)" in
    Darwin)
        install_macos_core || exit 1
        ;;
    Linux)
        install_linux_core || exit 1
        ;;
    *)
        printf '[error] Unsupported operating system: %s\n' "$(uname -s)" >&2
        exit 1
        ;;
esac

for required in nu nvim chezmoi git; do
    if ! have "$required"; then
        printf '[error] Required command is unavailable after bootstrap: %s\n' "$required" >&2
        exit 1
    fi
done

section "Starting Nushell setup"

NU_ARGS=(
    "$ROOT/setup.nu"
    "--mode"
    "$MODE"
)

if [ -n "$DATA_DIR" ]; then
    NU_ARGS+=("--data-dir" "$DATA_DIR")
fi

if [ "$NO_AUTO_SYNC" -eq 1 ]; then
    NU_ARGS+=("--no-auto-sync")
fi

nu "${NU_ARGS[@]}"
STATUS=$?

if [ "$STATUS" -ne 0 ]; then
    printf '[error] setup.nu exited with code %s\n' "$STATUS" >&2
    exit "$STATUS"
fi

section "Bootstrap complete"
printf 'Open a new terminal after setup so newly installed programs are visible in PATH.\n'
