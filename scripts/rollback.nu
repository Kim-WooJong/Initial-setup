#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const CORE = path self ./modules/core.nu
use $CORE [error-message failure-envelope captured-failure]

def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)

    if $test_mode == "1" and not ($override | is-empty) {
        return ($override | path expand)
    }

    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    open $file
}

def snapshot-root [] {
    (nu-home)
    | path join ".config" "dotfiles" "snapshots"
}

def snapshot-list [] {
    let root = (snapshot-root)

    if not ($root | path exists) {
        return []
    }

    ls $root
    | where type == dir
    | sort-by name
    | reverse
}

def run-script [
    name: string
    ...args: string
] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)

    ^nu $script ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        error make {
            msg: ("Script failed: " + $name)
        }
    }
}

def restore-item [source: path destination: path] {
    if ($destination | path exists) {
        if (($destination | path type) == "dir") {
            rm -r $destination
        } else {
            rm $destination
        }
    }

    if not ($source | path exists) {
        return
    }

    if (($source | path type) == "dir") {
        cp -r $source $destination
    } else {
        cp $source $destination
    }
}

def rollback-impl [
    --list
    --snapshot: string = ""
    --source-only
] {
    let snapshots = (snapshot-list)

    if $list {
        if ($snapshots | is-empty) {
            print "No snapshots."
            return
        }

        $snapshots
        | each { |item| $item.name | path basename }
        | print

        return
    }

    if ($snapshots | is-empty) {
        error make {
            msg: "No snapshot is available."
        }
    }

    let selected = (
        if ($snapshot | is-empty) {
            $snapshots | first | get name
        } else {
            if ($snapshot | path basename) != $snapshot or $snapshot in ["." ".."] { error make {msg: "Snapshot must be a name, not a path."} }
            snapshot-root | path join $snapshot
        }
    )

    if not ($selected | path exists) {
        error make {
            msg: ("Snapshot not found: " + ($selected | into string))
        }
    }

    let context = (machine-context)
    let data_root = ($context.data_root | path expand)

    run-script "create-snapshot.nu" "--label" "pre-rollback" "--quiet"

    restore-item ($selected | path join ".chezmoiroot") ($data_root | path join ".chezmoiroot")
    restore-item ($selected | path join "home") ($data_root | path join "home")
    restore-item ($selected | path join "vscode") ($data_root | path join "vscode")
    restore-item ($selected | path join "toolchains") ($data_root | path join "toolchains")
    let meta = (open ($selected | path join "snapshot.nuon"))
    if ($meta.version? | default "1" | into string) == "2" {
        restore-item ($selected | path join "secrets") ($data_root | path join "secrets")
    } else { print "[keep] Older snapshot predates the encrypted vault; current ciphertext is retained." }
    restore-item ($selected | path join ".dotfiles-sync-meta.nuon") ($data_root | path join ".dotfiles-sync-meta.nuon")

    if $source_only {
        print ("[ok] Restored private source snapshot without applying it locally: " + ($selected | path basename))
        return
    }

    run-script "write-sync-meta.nu" "--action" "rollback"
    run-script "sync-down-local.nu"

    print ("[ok] Restored snapshot: " + ($selected | path basename))
}

const SAFETY = path self ./modules/safety.nu
const PROVIDER = path self ./modules/sync-provider.nu
use $SAFETY [operation-lease release-lease]
use $PROVIDER [load-provider assert-expected-head assert-same-head provider-head record-provider-state remote-lock release-remote-lock]

def main [--list --snapshot: string = "" --source-only] {
    if $list { rollback-impl --list; return }
    let lease = (operation-lease)
    mut shared = null
    let operation_result = (try {
        $env.INITIAL_SETUP_OPERATION_TOKEN = $lease.lock.token
        let provider = (load-provider)
        $shared = (remote-lock $provider)
        let head = (assert-expected-head $provider)
        rollback-impl --snapshot $snapshot --source-only=$source_only
        if $provider.kind == "directory" {
            record-provider-state $provider (provider-head $provider)
            if not $source_only { run-script "update-sync-state.nu" }
        } else {
            assert-same-head $provider $head
            print "[info] Remote HEAD is unchanged. Run dotpush only after reviewing the reverted workspace."
        }
        null
    } catch {|err| failure-envelope $err })
    let operation_failure = (captured-failure $operation_result)

    # Snapshot the error in catch; inspect mutable handles in the outer block.
    # Attempt both releases, including when the remote lock cannot be removed.
    let remote_cleanup_result = (try { release-remote-lock $shared; null } catch {|err| failure-envelope $err })
    let local_cleanup_result = (try { release-lease $lease; null } catch {|err| failure-envelope $err })
    let remote_cleanup_error = (captured-failure $remote_cleanup_result)
    let local_cleanup_error = (captured-failure $local_cleanup_result)
    if $operation_failure != null { error make {msg: (error-message $operation_failure "Rollback failed.")} }
    if $remote_cleanup_error != null { error make {msg: (error-message $remote_cleanup_error "Remote-lock cleanup failed.")} }
    if $local_cleanup_error != null { error make {msg: (error-message $local_cleanup_error "Local-lock cleanup failed.")} }
}
