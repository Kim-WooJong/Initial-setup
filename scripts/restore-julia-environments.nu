#!/usr/bin/env nu

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

def copy-if-exists [source: path destination: path] {
    if not ($source | path exists) { return }
    mkdir ($destination | path dirname)
    cp $source $destination
}

def main [] {
    let context = (machine-context)

    if not $context.features.julia {
        print "[skip] Julia disabled"
        return
    }

    let cloud_root = ($context.data_root | path expand | path join "toolchains" "julia" "environments")

    if not ($cloud_root | path exists) {
        print "[skip] No captured Julia environments"
        return
    }

    let local_root = ((nu-home) | path join ".julia" "environments")
    mkdir $local_root

    let environments = (ls $cloud_root | where type == dir)

    for environment in $environments {
        let name = ($environment.name | path basename)
        let target = ($local_root | path join $name)
        let project = ($environment.name | path join "Project.toml")
        let manifest = ($environment.name | path join "Manifest.toml")

        copy-if-exists $project ($target | path join "Project.toml")
        copy-if-exists $manifest ($target | path join "Manifest.toml")
    }

    print "[ok] Julia Project/Manifest files restored"
    print "[info] Instantiate Julia environments when first used on this machine."
}
