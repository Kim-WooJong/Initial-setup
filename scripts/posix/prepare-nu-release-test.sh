#!/usr/bin/env bash
# Offline tests for the official-release Nushell bootstrap selector.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$ROOT/scripts/posix/prepare-nu-release.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/initial-setup-nu-release-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
REAL_PATH="$PATH"
mkdir -p "$TMP/bin" "$TMP/home"

cat > "$TMP/bin/nu" <<'EOF'
#!/bin/sh
[ "${1:-}" = "--version" ] && { printf '0.115.1\n'; exit 0; }
exit 0
EOF
chmod +x "$TMP/bin/nu"
out="$(HOME="$TMP/home" PATH="$TMP/bin:$REAL_PATH" bash "$HELPER" --check)"
[ "$out" = "$TMP/bin/nu" ] || { echo "[fail] compatible PATH Nu was not reused" >&2; exit 1; }
echo "[pass] compatible PATH Nu is reused without download"

cat > "$TMP/bin/nu" <<'EOF'
#!/bin/sh
[ "${1:-}" = "--version" ] && { printf '0.108.0\n'; exit 0; }
exit 0
EOF
chmod +x "$TMP/bin/nu"
set +e
HOME="$TMP/home" PATH="$TMP/bin:$REAL_PATH" bash "$HELPER" --check >"$TMP/out" 2>"$TMP/err"
code=$?
set -e
[ "$code" -ne 0 ] || { echo "[fail] old PATH Nu was accepted" >&2; exit 1; }
grep -q 'NU_RELEASE_MISSING' "$TMP/err" || { cat "$TMP/err" >&2; exit 1; }
[ ! -e "$TMP/home/.local/share/initial-setup/runtime/nu" ] || { echo "[fail] check mode wrote runtime state" >&2; exit 1; }
echo "[pass] check mode rejects old Nu and writes no runtime state"

# Manifest invariants: one stable version, unique targets, lowercase SHA-256.
awk -F'|' '
  $1 !~ /^#/ && NF {
    if ($1 !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) exit 10;
    if ($3 !~ /^[a-f0-9]{64}$/) exit 11;
    if (seen[$2]++) exit 12;
    versions[$1]=1; rows++
  }
  END { if (rows < 1) exit 13; n=0; for (v in versions) n++; if (n != 1) exit 14 }
' "$ROOT/toolchains/nushell-release.txt"
echo "[pass] pinned Nushell release manifest invariants hold"

echo "[ok] POSIX official-release Nushell selector tests passed (offline)."
