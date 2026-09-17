#!/usr/bin/env nu
const ROOT = path self ..

def fail [message: string] {
    error make {msg: $message}
}

def main [] {
    let wiki = ($ROOT | path join "docs" "wiki")
    let required = [
        "Home.md"
        "Installation-Linux.md"
        "First-Run.md"
        "Profiles-and-Features.md"
        "Features-and-Roles.md"
        "Command-Reference.md"
        "Architecture.md"
        "Synchronization.md"
        "Cloud-Wins.md"
        "Recovery-and-Safety.md"
        "Troubleshooting.md"
        "Internal-Components.md"
        "Development-and-Testing.md"
        "_Sidebar.md"
    ]

    for name in $required {
        let file = ($wiki | path join $name)
        if not ($file | path exists) { fail ("Wiki page missing: " + $name) }
    }

    let commands = [
        "dotstatus" "dotdiff" "dotpush" "dotpull" "dotresolve" "dotsync"
        "dotsnapshot" "dotrollback" "dotversion" "dotrepo" "dotrelease"
        "dotcleanup" "dotaudit" "dotstate" "dotmigrate" "dotchecklist"
        "dotcapture" "dotrestoreenv" "dotdoctor" "dotupdate" "dotreport"
        "dotlog" "dotconfig" "dotonedrive" "dotrclone" "dotlocal" "dotsecrets"
        "dotgitids" "dotsshkeys" "dotgitlocal" "dotsshlocal" "dotnvim" "dotnu"
        "dotenv" "dotwezterm" "dotstarship" "dotrun" "dotvalidate" "dottest"
        "dotpreflight" "dotlocalbackup" "dotlocalrestore" "newproj" "dotdata"
        "dottools" "dotplan" "dotapply" "dotverify" "dottoolchain" "dotmergecfg"
        "dotvault" "dotbackend" "dotupgrade" "dotsecuritytest" "dotnuupdate" "dotcloud"
    ]
    let reference = (open --raw ($wiki | path join "Command-Reference.md"))
    for command in $commands {
        if not ($reference | str contains $command) {
            fail ("User command missing from wiki reference: " + $command)
        }
    }

    let home = (open --raw ($wiki | path join "Home.md"))
    for name in ($required | where {|item| $item != "Home.md" and $item != "_Sidebar.md" }) {
        if not ($home | str contains $name) {
            fail ("Wiki Home does not link required page: " + $name)
        }
    }

    print "[pass] Wiki pages and user command coverage are present."
}
