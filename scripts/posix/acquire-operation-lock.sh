#!/bin/sh
# Exit contract: 0 acquired, 17 existing path, 74 I/O/invalid path, 64 usage.
# The token is supplied as argv, never evaluated as shell source.
# Never remove a lock on error: a write failure can leave a partial lock, which
# must be reviewed separately after confirming all writers have stopped.
if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    printf '%s\n' 'INITIAL_SETUP_LOCK_USAGE: expected a path and nonempty token' >&2
    exit 64
fi
if [ -L "$1" ] || { [ -e "$1" ] && [ ! -f "$1" ]; }; then
    printf '%s\n' 'INITIAL_SETUP_LOCK_IO: path is a symbolic link or non-regular file' >&2
    exit 74
fi
# Keep the descriptor from exclusive creation through the entire token write.
# Explicitly exit on open failure: bash can otherwise continue after a failed
# exec redirection, unlike dash in some invocation modes.
(
    set -C
    umask 077
    exec 3> "$1" || exit 73
    if ! printf '%s' "$2" >&3; then
        printf '%s\n' 'INITIAL_SETUP_LOCK_IO: token write failed; inspect any partial file' >&2
        exit 74
    fi
    exec 3>&-
)
result=$?
if [ "$result" -eq 0 ] || [ "$result" -eq 74 ]; then
    exit "$result"
fi
if [ -e "$1" ] || [ -L "$1" ]; then
    printf '%s\n' 'INITIAL_SETUP_LOCK_EXISTS: existing lock path was not replaced' >&2
    exit 17
fi
printf '%s\n' 'INITIAL_SETUP_LOCK_IO: exclusive creation failed' >&2
exit 74
