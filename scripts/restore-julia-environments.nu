#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
def copy-if-exists [source: path destination: path] {
    if not ($source | path exists) { return }
    mkdir ($destination | path dirname)
    cp $source $destination
}

def main [--source-root: string = ""] {
    let context = (machine-context)

    if not $context.features.julia {
        print "[skip] Julia disabled"
        return
    }

    let source_root = if ($source_root | str trim | is-empty) { $context.data_root | path expand } else { $source_root | path expand }
    let cloud_root = ($source_root | path join "toolchains" "julia" "environments")

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
