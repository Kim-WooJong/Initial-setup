#!/usr/bin/env nu

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

    if not ($file | path exists) {
        error make {
            msg: "Machine config is missing."
        }
    }

    open $file
}

def sanitize-label [label: string] {
    $label
    | str replace --all ' ' '-'
    | str replace --all '/' '-'
    | str replace --all '\' '-'
    | str replace --all ':' '-'
}

def copy-if-exists [source: path destination: path] {
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
    --label: string = "manual"
    --quiet
] {
    let context = (machine-context)

    if not $context.maintenance.snapshots_enabled {
        if not $quiet {
            print "[skip] Snapshots are disabled."
        }
        return
    }

    let data_root = ($context.data_root | path expand)

    if not ($data_root | path exists) {
        if not $quiet {
            print "[skip] Private data root is unavailable."
        }
        return
    }

    let snapshot_root = ((nu-home) | path join ".config" "dotfiles" "snapshots")
    mkdir $snapshot_root

    let timestamp = (date now | format date "%Y%m%d-%H%M%S")
    let safe_label = (sanitize-label $label)
    let snapshot_dir = ($snapshot_root | path join ($timestamp + "-" + $safe_label))

    mkdir $snapshot_dir

    copy-if-exists ($data_root | path join ".chezmoiroot") ($snapshot_dir | path join ".chezmoiroot")
    copy-if-exists ($data_root | path join "home") ($snapshot_dir | path join "home")
    copy-if-exists ($data_root | path join "vscode") ($snapshot_dir | path join "vscode")
    copy-if-exists ($data_root | path join "toolchains") ($snapshot_dir | path join "toolchains")

    {
        version: "1"
        created_at: (date now | format date "%Y-%m-%d %H:%M:%S %z")
        label: $label
        machine: $context.machine.name
        data_root: ($data_root | into string)
    }
    | to nuon
    | save ($snapshot_dir | path join "snapshot.nuon")

    let keep = $context.maintenance.snapshot_keep

    if $keep > 0 {
        let snapshots = (
            ls $snapshot_root
            | where type == dir
            | sort-by name
            | reverse
        )

        let count = ($snapshots | length)

        if $count > $keep {
            let old_snapshots = ($snapshots | skip $keep)

            for item in $old_snapshots {
                rm -r $item.name
            }
        }
    }

    if not $quiet {
        print ("[snapshot] " + ($snapshot_dir | into string))
    }
}
