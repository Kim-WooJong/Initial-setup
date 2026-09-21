#!/bin/sh
set -eu
printf "%s\n" "$*" >> "$NU_CARGO_TEST_LOG"
if [ "$1" = "toolchain" ]; then exit 0; fi
shift 2
if [ "$1" = "rustc" ]; then printf "release: 99.0.0\nhost: x86_64-unknown-linux-gnu\n"; exit 0; fi
[ "$1" = "cargo" ] || exit 66
[ "${NU_CARGO_TEST_FAIL:-0}" = 0 ] || exit 37
root=""; version=""
while [ "$#" -gt 0 ]; do
 case "$1" in --root) root="$2"; shift 2;; --version) version="$2"; shift 2;; *) shift;; esac
done
mkdir -p "$root/bin"
cp "$NU_CARGO_TEST_EXE" "$root/bin/nu"
printf '{"installs":{"nu %s (registry+https://github.com/rust-lang/crates.io-index)":{"bins":["nu"]}}}\n' "$version" > "$root/.crates2.json"
