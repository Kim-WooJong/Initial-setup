#!/usr/bin/env nu
# Regression checks for the interactive Nushell command/completion surface.

const DOTFILES = path self ./modules/dotfiles.nu
use $DOTFILES *

def expect [ok: bool message: string] {
    if not $ok { error make {msg: ("[command-completion-test] " + $message)} }
    print ("[pass] " + $message)
}

def completions [line: string] {
    $line | commandline complete | each {|item| $item | into string }
}

def expect-completions [line: string wanted: list<string>] {
    let actual = (completions $line)
    for item in $wanted {
        expect ($item in $actual) ("`" + $line + "<Tab>` includes " + $item)
    }
}

def main [] {
    let required = [
        "dotstatus" "dotsync" "dotpush" "dotpull"
        "dotsnapshot" "dotrollback"
        "dotdoctor" "dotupdate" "dotreport" "dotlog"
        "dotversion" "dotrepo" "dotrelease" "dotaudit" "dotstate"
        "dotmigrate" "dotcleanup" "dotlocal" "dotchecklist"
        "dotcapture" "dotrestoreenv"
        "dotconfig" "dotsecrets"
        "dotgitids" "dotsshkeys" "dotgitlocal" "dotsshlocal"
        "dotpreflight" "dotlocalbackup" "dotlocalrestore"
        "dotvalidate" "dottest" "dotrun" "dotresolve"
        "dotplan" "dotapply" "dotverify" "dottoolchain" "dotmergecfg"
        "dotvault" "dotbackend" "dotupgrade" "dotsecuritytest"
    ]

    let command_rows = (scope commands)
    let dot_names = (completions "dot")
    for name in $required {
        expect ($name in $dot_names) ("dot<Tab> exposes " + $name)
        let matches = ($command_rows | where name == $name)
        expect (not ($matches | is-empty)) ("command is in scope: " + $name)
        let description = (($matches | first | get --optional description) | default "" | str trim)
        expect (not ($description | is-empty)) ("command has Tab/help description: " + $name)
    }

    let newproj_names = (completions "newp")
    expect ("newproj" in $newproj_names) "newp<Tab> exposes newproj"
    let newproj_row = ($command_rows | where name == "newproj" | first)
    expect (not ((($newproj_row | get --optional description) | default "" | str trim) | is-empty)) "newproj has Tab/help description"

    expect-completions "dotpull --" ["--prune" "--force" "--backup" "--source-only" "--discard-source" "--discard-local" "--reload"]
    expect-completions "dotrun --" ["--list" "--status" "--logs" "--resume" "--rollback" "--run-id"]
    expect-completions "dotupdate --" ["--repo" "--tools" "--config" "--all"]
    expect-completions "dotlocalrestore --" ["--list" "--backup" "--force"]
    expect-completions "dotupgrade --" ["--from" "--manifest-sha256" "--ref" "--commit" "--yes" "--list" "--rollback"]
    expect-completions "dotsecuritytest --" ["--require-age" "--require-rclone" "--keep"]
    expect-completions "dotrelease " ["patch" "minor" "major" "set"]
    expect-completions "newproj " ["rust" "julia" "python" "generic"]
    expect-completions "dotplan --direction " ["none" "pull" "push"]

    print "[ok] Nushell command discovery/completion surface passed."
}
