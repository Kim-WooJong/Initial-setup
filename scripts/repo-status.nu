#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def run-git [args: list] {
    ^git -C $TOOLS_ROOT ...$args
    $env.LAST_EXIT_CODE | default 0
}

def main [] {
    if (which git | is-empty) {
        print "[warn] git not found"
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
