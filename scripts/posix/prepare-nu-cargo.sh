#!/usr/bin/env bash
# Prepare Cargo-built Nu even if no usable Nushell parser exists yet.
# stdout: ONE selected executable path. Progress and compiler diagnostics: stderr.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK=0
if [ "${1:-}" = "--check" ]; then CHECK=1; shift; fi
if [ "$#" -ne 0 ]; then printf 'Usage: bash prepare-nu-cargo.sh [--check]\n' >&2; exit 2; fi
CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export CARGO_HOME
export PATH="$CARGO_HOME/bin:$PATH"
# Do not trust a session inherited from another terminal or an earlier release.
unset INITIAL_SETUP_NU_SESSION_EXE INITIAL_SETUP_NU_SESSION_VERSION INITIAL_SETUP_NU_SESSION_PROVIDER
seed_ready() {
    local version
    version="$("$1" --version)" || return 1
    printf '%s\n' "$version" | awk -F. 'BEGIN {ok=0} NF == 3 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {ok=(($1+0)>0 || ($2+0)>106 || (($2+0)==106 && ($3+0)>=1))} END {exit !ok}'
}
SEED=""
if command -v nu >/dev/null 2>&1; then
    candidate="$(command -v nu)"
    if seed_ready "$candidate"; then SEED="$candidate"; fi
fi
# Never execute an arbitrary build directory before checking its local receipt.
# Only simple, generated scalar fields are extracted; none is evaluated as code.
RUNTIME_ROOT="$CARGO_HOME/initial-setup/nu"
receipt="$RUNTIME_ROOT/current.json"
if [ -z "$SEED" ] && [ -f "$receipt" ]; then
    format="$(sed -nE 's/^[[:space:]]*"format":[[:space:]]*([0-9]+),?[[:space:]]*$/\1/p' "$receipt")"
    provider="$(sed -nE 's/^[[:space:]]*"provider":[[:space:]]*"([a-z]+)",?[[:space:]]*$/\1/p' "$receipt")"
    directory="$(sed -nE 's/^[[:space:]]*"directory":[[:space:]]*"(build-[a-f0-9-]+)",?[[:space:]]*$/\1/p' "$receipt")"
    digest="$(sed -nE 's/^[[:space:]]*"binary_sha256":[[:space:]]*"([a-f0-9]+)",?[[:space:]]*$/\1/p' "$receipt")"
    if [[ "$format" != 2 || "$provider" != cargo || ! "$directory" =~ ^build-[a-f0-9-]{32,36}$ || ! "$digest" =~ ^[a-f0-9]{64}$ ]]; then
        printf 'NU_CACHE_INVALID: malformed Cargo receipt; no cached program was executed.\n' >&2; exit 1
    fi
    candidate="$RUNTIME_ROOT/versions/$directory/bin/nu"
    if [ -f "$candidate" ] && [ ! -L "$candidate" ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            actual="$(sha256sum "$candidate" | awk '{print $1}')"
        elif command -v shasum >/dev/null 2>&1; then
            actual="$(shasum -a 256 "$candidate" | awk '{print $1}')"
        else printf 'NU_HASH_MISSING: sha256sum or shasum is required.\n' >&2; exit 1; fi
        if [ "$actual" != "$digest" ]; then printf 'NU_CACHE_CHANGED: refusing to execute modified Cargo Nu.\n' >&2; exit 1; fi
        if seed_ready "$candidate"; then SEED="$candidate"; fi
    else
        printf 'NU_CACHE_INVALID: receipt binary is missing or not a regular file.\n' >&2; exit 1
    fi
fi
if [ -z "$SEED" ]; then
    if [ "$CHECK" -eq 1 ]; then printf 'NU_SEED_MISSING: check mode never installs. Run bootstrap first.\n' >&2; exit 1; fi
    if command -v rustup >/dev/null 2>&1; then
        rustup toolchain install stable --profile minimal >&2
        CARGO=(rustup run stable cargo)
    elif command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
        CARGO=(cargo)
    else
        printf 'NU_CARGO_MISSING: install Rust/Cargo; bootstrap can prepare Rustup.\n' >&2
        exit 1
    fi
    # Unique installation roots do not overwrite a running binary or another build.
    id="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    stage="$RUNTIME_ROOT/versions/build-$id"
    mkdir -p "$stage"
    export CARGO_TARGET_DIR="$RUNTIME_ROOT/target"
    printf '[nushell] No usable Nu seed. Cargo compiling an initial interpreter.\n' >&2
    if ! "${CARGO[@]}" install nu --locked --bin nu --registry crates-io --root "$stage" >&2; then
        printf 'NU_SEED_BUILD_FAILED: previous runtimes were not changed; inspect Cargo output. Incomplete files: %s\n' "$stage" >&2
        exit 1
    fi
    SEED="$stage/bin/nu"
    if ! seed_ready "$SEED"; then printf 'NU_SEED_INVALID: built executable cannot start the runtime gate.\n' >&2; exit 1; fi
fi
args=(--prepare)
if [ "$CHECK" -eq 1 ]; then args+=(--check); fi
# The gate selects an exact newest stable version. With current Rust, the initial
# Cargo install normally already built it and is adopted without rebuilding.
exec "$SEED" --no-config-file "$ROOT/scripts/runtime-launch.nu" "${args[@]}"
