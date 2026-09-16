#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    open $file
}

def rclone-config-path [] {
    let helper = ($TOOLS_ROOT | path join "scripts" "rclone-config-path.nu")

    ^nu $helper
    let exit_code = ($env.LAST_EXIT_CODE | default 2)

    if $exit_code != 0 {
        return null
    }

    let output = ($in | default "")
    $output
}

def resolve-rclone-config [] {
    if (which rclone | is-empty) {
        return null
    }

    let rows = (
        ^rclone config file
        | lines
        | each { |line| $line | str trim }
        | where { |line| not ($line | is-empty) }
    )

    let exit_code = ($env.LAST_EXIT_CODE | default 1)

    if $exit_code != 0 or ($rows | is-empty) {
        return null
    }

    $rows | last
}

def main [] {
    let context = (machine-context)

    if not ($context.features.rclone_config? | default false) {
        print "[skip] rclone config synchronization disabled"
        return
    }

    if (which rclone | is-empty) {
        print "[skip] rclone not found; config capture skipped"
        return
    }

    let source = (resolve-rclone-config)

    if $source == null or not ($source | path exists) {
        print "[skip] rclone config file does not exist"
        return
    }

    let destination = (
        $context.data_root
        | path expand
        | path join "rclone" "rclone.conf"
    )

    mkdir ($destination | path dirname)

    let source_hash = (open --raw $source | hash sha256)
    let destination_hash = (
        if ($destination | path exists) {
            open --raw $destination | hash sha256
        } else {
            ""
        }
    )

    if $source_hash == $destination_hash {
        print "[skip] rclone config already captured"
        return
    }

    cp $source $destination

    print ("[capture] rclone config -> " + ($destination | into string))
}
