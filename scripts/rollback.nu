#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
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

def main [
    --list
    --snapshot: string = ""
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

    run-script "write-sync-meta.nu" "--action" "rollback"
    run-script "sync-down.nu"

    print ("[ok] Restored snapshot: " + ($selected | path basename))
}
