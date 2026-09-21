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
        "Code-Architecture.md"
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
        "dotstatus" "dotdiff" "dotpush" "dotpull" "dotrpush" "dotrpull" "dotresolve" "dotsync"
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


    let architecture = (open --raw ($wiki | path join "Code-Architecture.md"))
    let module_root = ($ROOT | path join "scripts" "modules")
    for module in (ls $module_root | where type == file | get name | where {|file| $file | str ends-with ".nu" } | each {|file| $file | path basename } | sort) {
        if not ($architecture | str contains ("`" + $module + "`")) {
            fail ("Shared module missing from code architecture map: " + $module)
        }
    }

    let scripts_root = ($ROOT | path join "scripts")
    for script in (ls $scripts_root | where type == file | get name | where {|file| $file | str ends-with ".nu" } | each {|file| $file | path basename } | sort) {
        if not ($architecture | str contains ("`" + $script + "`")) {
            fail ("Top-level script missing from code architecture map: " + $script)
        }
    }

    for anchor in [
        "setup.nu"
        "setup-main.nu"
        "bootstrap.sh"
        "subprocess.nu"
        "sync-provider.nu"
        "cloud-wins-engine.nu"
        "verify.nu"
    ] {
        if not ($architecture | str contains $anchor) {
            fail ("Architecture map is missing a required ownership anchor: " + $anchor)
        }
    }

    print "[pass] Wiki pages, architecture ownership, and user command coverage are present."
}
