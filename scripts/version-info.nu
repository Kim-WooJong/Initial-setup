#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $SUBPROCESS [run-command]
use $INSTALL_UTILS [probe-tool]

def app-version [] {
    let file = ($TOOLS_ROOT | path join "VERSION")
    open $file --raw | into string | str trim
}

def schema-version [] {
    let file = ($TOOLS_ROOT | path join "SCHEMA_VERSION")
    open $file --raw | into string | str trim
}

def git-output [args: list] {
    let git = (probe-tool "git" ["--version"])
    if not $git.healthy { return "" }
    let result = (run-command $git.path (["-C" ($TOOLS_ROOT | into string)] | append $args))
    if $result.ok { $result.stdout | str trim } else { "" }
}

def main [] {
    let version = (app-version)
    let git_dir = ($TOOLS_ROOT | path join ".git")

    print ("Initial-setup : " + $version)
    print ("Config schema : " + (schema-version))

    if not ($git_dir | path exists) {
        print "Git repository : no"
        return
    }

    let branch = (git-output ["branch" "--show-current"])
    let describe = (git-output ["describe" "--tags" "--always" "--dirty"])
    let remote = (git-output ["remote" "get-url" "origin"])
    let status = (git-output ["status" "--porcelain"])
    let state = (if ($status | is-empty) { "clean" } else { "dirty" })

    print "Git repository : yes"
    print ("Git branch     : " + (if ($branch | is-empty) { "(detached)" } else { $branch }))
    print ("Git describe   : " + (if ($describe | is-empty) { "unknown" } else { $describe }))
    print ("Git state      : " + $state)

    if not ($remote | is-empty) {
        print ("Git remote     : " + $remote)
    }
}
