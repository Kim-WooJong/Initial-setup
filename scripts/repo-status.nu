#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $SUBPROCESS [run-command command-failure-message]
use $INSTALL_UTILS [probe-tool]

def run-git [args: list] {
    let git = (probe-tool "git" ["--version"])
    if not $git.healthy {
        print "[warn] git is unavailable or unhealthy"
        return false
    }
    let result = (run-command $git.path (["-C" ($TOOLS_ROOT | into string)] | append $args) --live)
    if not $result.ok {
        print --stderr ("[warn] " + (command-failure-message "git" $result))
        return false
    }
    true
}

def main [] {
    let git = (probe-tool "git" ["--version"])
    if not $git.healthy {
        print "[warn] git not found or unhealthy"
        return
    }

    if not (($TOOLS_ROOT | path join ".git") | path exists) {
        print "[warn] Initial-setup is not a Git checkout"
        return
    }

    print "Repository"
    print "────────────────────────────────"
    run-git ["status" "--short" "--branch"] | ignore

    print ""
    print "Remote"
    print "────────────────────────────────"
    run-git ["remote" "-v"] | ignore
}
