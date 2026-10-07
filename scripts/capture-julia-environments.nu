#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
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

    let local_root = ((nu-home) | path join ".julia" "environments")
    let cloud_root = ($context.data_root | path expand | path join "toolchains" "julia" "environments")

    if not ($local_root | path exists) {
        print "[skip] Julia environments directory not found"
        return
    }

    if ($cloud_root | path exists) { rm -r $cloud_root }
    mkdir $cloud_root

    let environments = (ls $local_root | where type == dir)

    for environment in $environments {
        let name = ($environment.name | path basename)
        let target = ($cloud_root | path join $name)
        let project = ($environment.name | path join "Project.toml")
        let manifest = ($environment.name | path join "Manifest.toml")

        copy-if-exists $project ($target | path join "Project.toml")
        copy-if-exists $manifest ($target | path join "Manifest.toml")
    }

    print ("[ok] Julia environment metadata captured: " + ($cloud_root | into string))
}
