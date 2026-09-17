#!/usr/bin/env bash
# Fast POSIX Nushell bootstrap using a pinned official release binary.
# stdout: exactly one selected executable path.
# diagnostics: stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/toolchains/nushell-release.txt"
CHECK=0
NO_LINK=0

usage() {
    cat >&2 <<'USAGE'
Usage: prepare-nu-release.sh [--check] [--no-link]

--check    Never download/install. Reuse an already compatible Nu if present.
--no-link  Do not create/update ~/.local/bin/nu when a managed runtime is installed.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) CHECK=1 ;;
        --no-link) NO_LINK=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
    shift
done

if [ ! -r "$MANIFEST" ]; then
    echo "NU_RELEASE_MANIFEST_MISSING: $MANIFEST" >&2
    exit 1
fi

version_ge() {
    # $1 actual, $2 minimum. Stable numeric x.y.z only.
    awk -v a="$1" -v b="$2" 'BEGIN {
        na=split(a,A,"."); nb=split(b,B,".");
        if (na != 3 || nb != 3) exit 2;
        for (i=1;i<=3;i++) {
            if (A[i]+0 > B[i]+0) exit 0;
            if (A[i]+0 < B[i]+0) exit 1;
        }
        exit 0;
    }'
}

nu_version() {
    "$1" --version 2>/dev/null | tr -d '\r\n'
}

usable_nu() {
    [ -x "$1" ] || return 1
    local v
    v="$(nu_version "$1")" || return 1
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    version_ge "$v" "0.109.1"
}

# Prefer a compatible interpreter already on PATH. This keeps offline reruns fast.
if command -v nu >/dev/null 2>&1; then
    EXISTING="$(command -v nu)"
    if usable_nu "$EXISTING"; then
        printf '%s\n' "$EXISTING"
        exit 0
    fi
fi

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
BIN_HOME="$HOME/.local/bin"
RUNTIME_BASE="$DATA_HOME/initial-setup/runtime/nu"

os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
    Linux)
        case "$arch" in
            x86_64|amd64) cpu="x86_64" ;;
            aarch64|arm64) cpu="aarch64" ;;
            armv7l|armv7) cpu="armv7" ;;
            *) echo "NU_RELEASE_UNSUPPORTED_ARCH: Linux $arch" >&2; exit 3 ;;
        esac
        libc="gnu"
        if (ldd --version 2>&1 || true) | grep -qi musl || compgen -G '/lib/ld-musl-*.so.1' >/dev/null 2>&1; then
            libc="musl"
        fi
        if [ "$cpu" = "armv7" ]; then
            if [ "$libc" = "musl" ]; then target="armv7-unknown-linux-musleabihf"; else target="armv7-unknown-linux-gnueabihf"; fi
        else
            target="$cpu-unknown-linux-$libc"
        fi
        ;;
    Darwin)
        case "$arch" in
            x86_64|amd64) target="x86_64-apple-darwin" ;;
            arm64|aarch64) target="aarch64-apple-darwin" ;;
            *) echo "NU_RELEASE_UNSUPPORTED_ARCH: macOS $arch" >&2; exit 3 ;;
        esac
        ;;
    *)
        echo "NU_RELEASE_UNSUPPORTED_OS: $os" >&2
        exit 3
        ;;
esac

row="$(awk -F'|' -v t="$target" '$1 !~ /^#/ && $2==t {print; exit}' "$MANIFEST")"
if [ -z "$row" ]; then
    echo "NU_RELEASE_UNMAPPED: no pinned release for $target" >&2
    exit 3
fi
IFS='|' read -r version mapped_target expected_sha <<EOFROW
$row
EOFROW
if [ "$mapped_target" != "$target" ] || ! [[ "$expected_sha" =~ ^[a-f0-9]{64}$ ]]; then
    echo "NU_RELEASE_MANIFEST_INVALID: $target" >&2
    exit 1
fi

install_dir="$RUNTIME_BASE/$version/$target"
managed="$install_dir/nu"
if usable_nu "$managed"; then
    actual="$(nu_version "$managed")"
    if [ "$actual" = "$version" ]; then
        printf '%s\n' "$managed"
        exit 0
    fi
fi

if [ "$CHECK" -eq 1 ]; then
    echo "NU_RELEASE_MISSING: Nu >=0.109.1 is not available; check mode does not install." >&2
    exit 1
fi

for cmd in curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "NU_RELEASE_DEPENDENCY_MISSING: $cmd" >&2
        exit 1
    fi
done
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "NU_RELEASE_DEPENDENCY_MISSING: sha256sum or shasum" >&2
    exit 1
fi

asset="nu-$version-$target.tar.gz"
url="https://github.com/nushell/nushell/releases/download/$version/$asset"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/initial-setup-nu.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
archive="$tmp/$asset"
extract="$tmp/extract"
mkdir -p "$extract"

echo "[nushell] Downloading official Nushell $version ($target)." >&2
curl --proto '=https' --tlsv1.2 --fail --show-error --location --retry 3 --connect-timeout 15 --max-time 300 "$url" -o "$archive"
if command -v sha256sum >/dev/null 2>&1; then
    actual_sha="$(sha256sum "$archive" | awk '{print $1}')"
else
    actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
fi
if [ "$actual_sha" != "$expected_sha" ]; then
    echo "NU_RELEASE_HASH_MISMATCH: expected $expected_sha, got $actual_sha" >&2
    exit 1
fi

# Refuse absolute paths, parent traversal, backslashes and option-like members.
while IFS= read -r member; do
    case "$member" in
        ''|/*|../*|*/../*|*/..|-*|*'\\'*)
            echo "NU_RELEASE_UNSAFE_ARCHIVE_MEMBER: $member" >&2
            exit 1
            ;;
    esac
done < <(tar -tzf "$archive")

tar -xzf "$archive" -C "$extract"
candidate="$(find "$extract" -type f -name nu -perm -u+x -print -quit)"
if [ -z "$candidate" ]; then
    echo "NU_RELEASE_BINARY_MISSING: archive did not contain executable nu" >&2
    exit 1
fi
if [ "$(nu_version "$candidate")" != "$version" ]; then
    echo "NU_RELEASE_VERSION_MISMATCH: extracted binary did not report $version" >&2
    exit 1
fi

mkdir -p "$install_dir"
stage="$install_dir/.nu.new.$$"
cp "$candidate" "$stage"
chmod 0755 "$stage"
if [ "$(nu_version "$stage")" != "$version" ]; then
    rm -f "$stage"
    echo "NU_RELEASE_INSTALL_VERIFY_FAILED" >&2
    exit 1
fi
mv -f "$stage" "$managed"

cat > "$install_dir/receipt.txt" <<EOFRECEIPT
provider=official-github-release
version=$version
target=$target
asset=$asset
sha256=$expected_sha
EOFRECEIPT

if [ "$NO_LINK" -eq 0 ]; then
    mkdir -p "$BIN_HOME"
    link="$BIN_HOME/nu"
    if [ -L "$link" ]; then
        ln -sfn "$managed" "$link"
    elif [ ! -e "$link" ]; then
        ln -s "$managed" "$link"
    else
        echo "[nushell] ~/.local/bin/nu already exists and is not a symlink; leaving it unchanged." >&2
    fi
fi

printf '%s\n' "$managed"
