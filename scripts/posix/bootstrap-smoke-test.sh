#!/usr/bin/env bash
# Offline smoke test for the POSIX fallback bootstrap. No packages/files outside temp HOME.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/initial-setup-bootstrap-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/cwd"
LOG="$TMP/nu-args.txt"
cat > "$TMP/bin/nu" <<'FAKENU'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--version" ]; then
    printf '0.115.1\n'
    exit 0
fi
printf '%s\n' "$@" > "${INITIAL_SETUP_FAKE_NU_LOG:?}"
exit 0
FAKENU
chmod 0755 "$TMP/bin/nu"

DATA="$TMP/home/private data"
(
    cd "$TMP/cwd"
    env \
        -u DISPLAY -u WAYLAND_DISPLAY -u XDG_CURRENT_DESKTOP \
        HOME="$TMP/home" \
        PATH="$TMP/bin:/usr/bin:/bin" \
        INITIAL_SETUP_FAKE_NU_LOG="$LOG" \
        bash "$ROOT/bootstrap.sh" --dry-run --no-auto-sync --profile server --config-policy push-local --data-dir "$DATA" >/dev/null
)

[ -s "$LOG" ] || { echo 'FAIL: fake Nu was not invoked' >&2; exit 1; }
grep -Fx -- '--no-config-file' "$LOG" >/dev/null
grep -Fx -- "$ROOT/setup.nu" "$LOG" >/dev/null
grep -Fx -- '--profile' "$LOG" >/dev/null
grep -Fx -- 'server' "$LOG" >/dev/null
grep -Fx -- '--config-policy' "$LOG" >/dev/null
grep -Fx -- 'push-local' "$LOG" >/dev/null
grep -Fx -- '--data-dir' "$LOG" >/dev/null
grep -Fx -- "$DATA" "$LOG" >/dev/null
grep -Fx -- '--dry-run' "$LOG" >/dev/null
grep -Fx -- '--no-auto-sync' "$LOG" >/dev/null
printf '[pass] POSIX fallback routes to script-relative setup.nu without changing requested setup policy.\n'
