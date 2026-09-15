#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def app-version [] {
    let file = ($TOOLS_ROOT | path join "VERSION")
    open $file --raw | decode utf-8 | str trim
}

def git-output [args: list] {
    if (which git | is-empty) { return "" }

    let output = (^git -C $TOOLS_ROOT ...$args | str trim)
    let exit_code = ($env.LAST_EXIT_CODE | default 1)
    if $exit_code != 0 { "" } else { $output }
}

def main [] {
    let version = (app-version)
    let git_dir = ($TOOLS_ROOT | path join ".git")

    print ("Initial-setup : " + $version)

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
