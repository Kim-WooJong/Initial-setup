#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [project-version project-schema-version]
const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $SUBPROCESS [run-command]
use $INSTALL_UTILS [probe-tool]

def git-output [args: list] {
    let git = (probe-tool "git" ["--version"])
    if not $git.healthy { return "" }
    let result = (run-command $git.path (["-C" ($TOOLS_ROOT | into string)] | append $args))
    if $result.ok { $result.stdout | str trim } else { "" }
}

def main [] {
    let version = (project-version $TOOLS_ROOT)
    let git_dir = ($TOOLS_ROOT | path join ".git")

    print ("Initial-setup : " + $version)
    print ("Config schema : " + ((project-schema-version $TOOLS_ROOT) | into string))

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
