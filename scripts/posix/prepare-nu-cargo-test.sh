#!/usr/bin/env bash
# Exercise the real POSIX preparation helper with fake Cargo/rustup/Nu commands.
# No network, compiler, package manager, or user runtime state is used.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT
PROJECT="$TEMP_ROOT/Project [한글]"
mkdir -p "$PROJECT/scripts/posix" "$TEMP_ROOT/bin" "$TEMP_ROOT/home"
cp "$HERE/prepare-nu-cargo.sh" "$PROJECT/scripts/posix/"
printf '# fixture path only\n' > "$PROJECT/scripts/runtime-launch.nu"
HELPER="$PROJECT/scripts/posix/prepare-nu-cargo.sh"
export HOME="$TEMP_ROOT/home" CARGO_HOME="$TEMP_ROOT/Cargo [한글]"
export PATH="$TEMP_ROOT/bin:$PATH"
export FAKE_LOG="$TEMP_ROOT/commands.log" FAKE_TEMPLATE="$TEMP_ROOT/fake-nu"
export FAKE_NU_VERSION="0.114.12" FAKE_LAUNCH_STATUS=0 FAKE_CARGO_STATUS=0 FAKE_RUSTUP_STATUS=0
cat > "$FAKE_TEMPLATE" <<'SH'
#!/bin/bash
set -eu
if [ "${1:-}" = '--version' ]; then printf '%s\n' "${FAKE_NU_VERSION:-0.114.12}"; exit 0; fi
printf 'launch:' >> "$FAKE_LOG"
printf '<%s>' "$@" >> "$FAKE_LOG"
printf '\n' >> "$FAKE_LOG"
if [ "${FAKE_LAUNCH_STATUS:-0}" != 0 ]; then exit "$FAKE_LAUNCH_STATUS"; fi
case "$0" in
 */initial-setup/nu/versions/build-*/bin/nu)
   directory="$(basename "$(dirname "$(dirname "$0")")")"
   if command -v sha256sum >/dev/null 2>&1; then
     digest="$(sha256sum "$0" | awk '{print $1}')"
   else digest="$(shasum -a 256 "$0" | awk '{print $1}')"; fi
   printf '{\n  "format": 2,\n  "provider": "cargo",\n  "directory": "%s",\n  "binary_sha256": "%s"\n}\n' "$directory" "$digest" > "$CARGO_HOME/initial-setup/nu/current.json"
   ;;
esac
printf '%s\n' "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
SH
chmod +x "$FAKE_TEMPLATE"
cp "$FAKE_TEMPLATE" "$TEMP_ROOT/bin/nu"
cat > "$TEMP_ROOT/bin/cargo" <<'SH'
#!/bin/bash
set -eu
printf 'cargo:' >> "$FAKE_LOG"; printf '<%s>' "$@" >> "$FAKE_LOG"; printf '\n' >> "$FAKE_LOG"
if [ "${FAKE_CARGO_STATUS:-0}" != 0 ]; then exit "$FAKE_CARGO_STATUS"; fi
root=""
while [ "$#" -gt 0 ]; do case "$1" in --root) root="$2"; shift 2;; *) shift;; esac; done
[ -n "$root" ] || exit 90
mkdir -p "$root/bin"
cp "$FAKE_TEMPLATE" "$root/bin/nu"
# Built seed has a new stable version even if the PATH interpreter was too old.
sed -i.bak 's/${FAKE_NU_VERSION:-0.114.12}/0.114.12/' "$root/bin/nu"
chmod +x "$root/bin/nu"
printf 'progress on stdout\n'
SH
cat > "$TEMP_ROOT/bin/rustup" <<'SH'
#!/bin/bash
set -eu
printf 'rustup:' >> "$FAKE_LOG"; printf '<%s>' "$@" >> "$FAKE_LOG"; printf '\n' >> "$FAKE_LOG"
if [ "$1" = toolchain ]; then exit "${FAKE_RUSTUP_STATUS:-0}"; fi
[ "$1" = run ] && [ "$2" = stable ] && [ "$3" = cargo ] || exit 91
shift 3
exec cargo "$@"
SH
chmod +x "$TEMP_ROOT/bin/"*
pass() { printf '[pass] %s\n' "$1"; }
run_helper() { bash "$HELPER" "$@" > "$TEMP_ROOT/out" 2> "$TEMP_ROOT/err"; }
: > "$FAKE_LOG"
run_helper
! grep -q '^cargo:' "$FAKE_LOG"
[ "$(wc -l < "$TEMP_ROOT/out" | tr -d ' ')" = 1 ]
grep -Fq "<--no-config-file><$PROJECT/scripts/runtime-launch.nu><--prepare>" "$FAKE_LOG"
pass 'Usable seed forwards literal Unicode/bracketed path, without compiling'
: > "$FAKE_LOG"
run_helper --check
! grep -q '^cargo:' "$FAKE_LOG"
grep -Fq '<--prepare><--check>' "$FAKE_LOG"
[ ! -e "$CARGO_HOME" ]
pass 'Check mode forwards --check and creates no Cargo state'
FAKE_NU_VERSION=0.106.0; export FAKE_NU_VERSION
: > "$FAKE_LOG"
if run_helper --check; then exit 1; fi
! grep -q '^launch:' "$FAKE_LOG"
[ ! -e "$CARGO_HOME" ]
pass 'Seed 0.106.0 is rejected without launch or installation in check mode'
FAKE_NU_VERSION=0.106.1; export FAKE_NU_VERSION
: > "$FAKE_LOG"
run_helper --check
! grep -q '^cargo:' "$FAKE_LOG"
pass 'Seed 0.106.1 is accepted at the documented boundary'
FAKE_NU_VERSION=0.114.12; export FAKE_NU_VERSION
FAKE_LAUNCH_STATUS=37; export FAKE_LAUNCH_STATUS
if run_helper; then exit 1; else code=$?; fi
[ "$code" = 37 ]
pass 'A gate failure preserves its exit status'
FAKE_LAUNCH_STATUS=0 FAKE_NU_VERSION=0.99.0; export FAKE_LAUNCH_STATUS FAKE_NU_VERSION
: > "$FAKE_LOG"
if run_helper --check; then exit 1; fi
! grep -q '^cargo:' "$FAKE_LOG"
[ ! -e "$CARGO_HOME" ]
pass 'Old seed + check refuses instead of installing'
: > "$FAKE_LOG"
run_helper
[ "$(wc -l < "$TEMP_ROOT/out" | tr -d ' ')" = 1 ]
grep -Fq '<toolchain><install><stable><--profile><minimal>' "$FAKE_LOG"
grep -Fq '<install><nu><--locked><--bin><nu><--registry><crates-io><--root>' "$FAKE_LOG"
[ -x "$(cat "$TEMP_ROOT/out")" ]
grep -Fq 'progress on stdout' "$TEMP_ROOT/err"
pass 'Old seed compiles with Cargo; logs cannot contaminate returned path'
: > "$FAKE_LOG"
run_helper
! grep -q '^cargo:' "$FAKE_LOG"
pass 'Prepared seed is reused on the next native invocation'
prepared="$(cat "$TEMP_ROOT/out")"
cp "$prepared" "$TEMP_ROOT/saved-seed"
printf '\n# changed bytes\n' >> "$prepared"
: > "$FAKE_LOG"
if run_helper; then exit 1; fi
! grep -q '^launch:' "$FAKE_LOG"
grep -q 'NU_CACHE_CHANGED' "$TEMP_ROOT/err"
cp "$TEMP_ROOT/saved-seed" "$prepared"
pass 'Modified cached seed is refused before launch'

# A different Cargo home makes a genuinely separate first-build fixture.
export CARGO_HOME="$TEMP_ROOT/failed-build"
FAKE_CARGO_STATUS=37; export FAKE_CARGO_STATUS
if run_helper; then exit 1; fi
[ ! -s "$TEMP_ROOT/out" ]
[ ! -e "$CARGO_HOME/initial-setup/nu/current.json" ]
pass 'Cargo failure returns no runtime and publishes no receipt'
FAKE_CARGO_STATUS=0 FAKE_RUSTUP_STATUS=38; export FAKE_CARGO_STATUS FAKE_RUSTUP_STATUS
export CARGO_HOME="$TEMP_ROOT/failed-rustup"
: > "$FAKE_LOG"
if run_helper; then exit 1; fi
! grep -q '^cargo:' "$FAKE_LOG"
pass 'Rustup failure prevents Cargo build'
if run_helper --unknown; then exit 1; fi
pass 'Unknown helper options are rejected'
printf '[ok] POSIX Cargo preparation tests passed (mock tools, no Nu/Rust execution).\n'
