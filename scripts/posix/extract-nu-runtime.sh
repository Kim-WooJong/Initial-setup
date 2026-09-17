#!/bin/sh
# Called only AFTER archive SHA-256 verification. Extract just the Nu executable,
# not arbitrary paths/plugins from the archive. Requires tar; no Python/jq.
set -eu
archive=$1
destination=$2
[ ! -e "$destination" ] || { echo 'NU_EXTRACT_EXISTS' >&2; exit 1; }
listing=$(tar -tzf "$archive")
member=$(printf '%s\n' "$listing" | awk '$0 == "nu" || $0 ~ /\/nu$/ {print}')
count=$(printf '%s\n' "$member" | awk 'NF {n++} END {print n+0}')
[ "$count" -eq 1 ] || { echo 'NU_EXTRACT_AMBIGUOUS: expected one nu executable' >&2; exit 1; }
case "$member" in ''|/*|../*|*/../*|*/..|-*|*'\'*) echo 'NU_EXTRACT_UNSAFE_PATH' >&2; exit 1 ;; esac
# A link must not masquerade as the selected executable.
kind=$(tar -tvzf "$archive" -- "$member" | cut -c 1)
[ "$kind" = '-' ] || { echo 'NU_EXTRACT_NOT_REGULAR' >&2; exit 1; }
(umask 077; set -C; tar -xOzf "$archive" -- "$member" > "$destination")
chmod 700 "$destination"
