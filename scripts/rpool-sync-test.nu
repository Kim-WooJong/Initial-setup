#!/usr/bin/env nu
# Integration test for rpool portable-config synchronization.
#
# Verifies semantic-hash change detection: a timestamp bump alone must not
# register as a change (capture-rpool-config returns "unchanged" and preserves
# the raw bundle bytes), while a real configuration edit registers as
# "captured". A fake `rpool` binary is built in a sandbox and placed on PATH;
# no real rpool or network is used.

const ROOT = path self ..
const RPOOL = path self ./modules/rpool-sync.nu
use $RPOOL [capture-rpool-config restore-rpool-config rpool-restore-preflight rpool-local-hash rpool-semantic-hash]
const PROVIDER = path self ./modules/sync-provider.nu
use $PROVIDER [provider-init provider-head publish-revision fetch-revision install-workspace]

def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[rpool-sync-test] " + $message)} }
    print ("[pass] " + $message)
}

# Fake rpool: `config export` writes a portable bundle whose exported_at_unix
# increments on every call, while gui.workers is read from a file so a real
# configuration change can be injected between calls. The script is embedded as
# a Nushell single-quoted string (no interpolation); inner JSON quotes are
# escaped for the shell so the script itself contains no single quotes.
def fake-rpool-script [] {
    '#!/bin/sh
case "$1 $2" in
        "config --help") echo "usage: rpool config export|import" ;;
        "config export")
        n=$(cat "$RP_COUNTER" 2>/dev/null || echo 0)
        n=$((n+1)); echo $n > "$RP_COUNTER"
        ts=$((1000 + n))
        workers=$(cat "$RP_WORKERS_FILE" 2>/dev/null || echo 8)
        printf "{\"format\":\"rpool-portable\",\"version\":\"0.5.15\",\"exported_at_unix\":%s,\"pools\":[{\"name\":\"p1\"}],\"gui\":{\"workers\":%s}}" "$ts" "$workers" > "$3"
          ;;
        "config import")
        if [ "$4" != "--dry-run" ]; then cp "$3" "$RP_IMPORTED"; fi
        echo "imported" ;;
        *) echo "unknown" >&2; exit 2 ;;
esac
'
}

def tests [base: path] {
    let bin = ($base | path join "bin")
    let root = ($base | path join "root")
    let counter = ($base | path join "counter")
    let workers = ($base | path join "workers")
    mkdir $bin
    mkdir $root
    "0" | save --force $counter
    "8" | save --force $workers

    let script = (fake-rpool-script)
    $script | save --force ($bin | path join "rpool")
    ^chmod +x ($bin | path join "rpool")

    let newpath = ($bin + ":" + ($env.PATH | str join ":"))
    with-env {
        PATH: $newpath
        RP_COUNTER: ($counter | into string)
        RP_WORKERS_FILE: ($workers | into string)
        RP_IMPORTED: ($base | path join imported.json)
    } {
        # 1. First capture with no prior bundle -> "captured".
        let c1 = (capture-rpool-config $root)
        check ($c1.status == "captured") "First capture of a new bundle is captured"
        let raw1 = (open --raw ($c1.path | path expand) | hash sha256)
        let sem1 = $c1.semantic

        # 2. Timestamp-only change (still workers=8) -> "unchanged", raw preserved.
        let c2 = (capture-rpool-config $root)
        check ($c2.status == "unchanged") "Timestamp-only re-export is unchanged"
        check ($c2.sha256 == $raw1) "Unchanged capture returns the retained bundle raw SHA-256"
        check ($c2.semantic == $sem1) "Semantic hash is stable across a timestamp bump"
        let raw2 = (open --raw ($c2.path | path expand) | hash sha256)
        check ($raw1 == $raw2) "Raw bundle bytes are preserved on unchanged"

        # 3. rpool-local-hash is stable across a timestamp-only re-export.
        let h1 = (rpool-local-hash)
        let h2 = (rpool-local-hash)
        check ($h1 == $h2) "Local fingerprint is stable across timestamp-only re-exports"

        # 4. Real configuration change (workers 8 -> 16) -> "captured".
        "16" | save --force $workers
        let c3 = (capture-rpool-config $root)
        check ($c3.status == "captured") "Real configuration edit is captured"
        check ($c3.semantic != $sem1) "Semantic hash changes on a real configuration edit"

        # Exercise the same transport primitives used by push/pull, not only
        # export. A local revision store avoids cloud/user credentials.
        let provider = {version: 1 kind: "local" remote: ($base | path join store) data_root: $root}
        provider-init $provider
        let head = (publish-revision $provider (provider-head $provider))
        let fetched = (fetch-revision $provider $head ($base | path join fetched))
        let receiver = ($base | path join receiver)
        mkdir $receiver
        install-workspace {data_root: $receiver} $fetched | ignore
        check ((open --raw ($receiver | path join rpool portable-config.json) | from json).gui.workers == 16) "Push/pull transports the latest rpool settings"
        restore-rpool-config $receiver --dry-run | ignore
        check (not ($env.RP_IMPORTED | path exists)) "Pull preflight does not import live settings"
        let restored = (restore-rpool-config $receiver)
        check ($restored.status == "restored" and (open --raw $env.RP_IMPORTED | from json).gui.workers == 16) "Pull invokes import using the received rpool settings"

        # rpool absent: pull must SKIP rpool (not block) when the machine has no
        # rpool and no active rpool settings.
        let norpool = ($base | path join norpool)
        mkdir ($norpool | path join rpool config)
        '{"format":"rpool-portable","gui":{"workers":8}}' | save ($norpool | path join rpool config portable-config.json)
        let emptybin = ($base | path join emptybin)
        mkdir $emptybin
        with-env {PATH: ($emptybin | into string)} {
            check ((rpool-restore-preflight $norpool).status == "skipped") "Pull preflight skips rpool when rpool is not installed"
            check ((restore-rpool-config $norpool).status == "skipped") "Restore skips rpool when rpool is not installed"
        }

        # 5. rpool-semantic-hash returns "" for non-record input.
        check ((rpool-semantic-hash null) == "") "Semantic hash of null is empty"
        check ((rpool-semantic-hash [1 2 3]) == "") "Semantic hash of a list is empty"
    }
}

def main [] {
    let base = (($env.TEMP? | default ($env.TMPDIR? | default "/tmp")) | path join ("initial-setup-rpool-sync-" + (random uuid)))
    mkdir $base
    try {
        with-env {INITIAL_SETUP_TEST_MODE: "1" INITIAL_SETUP_HOME_OVERRIDE: $base HOME: $base USERPROFILE: $base} {
            tests $base
        }
     } catch {|err| print --stderr ("[kept] " + $base); error make {msg: $err.msg} }
    rm --recursive --force $base
}
