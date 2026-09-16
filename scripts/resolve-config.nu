#!/usr/bin/env nu

# Resolve local/private configuration divergence without falling through to
# chezmoi's overwrite-only prompt.

const TOOLS_ROOT = path self ..

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    if not ($file | path exists) {
        error make { msg: ("Dotfiles machine config not found: " + ($file | into string)) }
    }

    open $file
}

def run-script [name: string ...args: string] {
    let script = ($TOOLS_ROOT | path join "scripts" $name)
    ^nu $script ...$args

    let exit_code = ($env.LAST_EXIT_CODE | default 0)
    if $exit_code != 0 {
        error make { msg: ("Script failed: " + ($script | into string)) }
    }
}

def main [] {
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)

    if not ($data_root | path exists) {
        error make { msg: ("Private data root unavailable: " + ($data_root | into string)) }
    }

    print "Configuration differences"
    print "────────────────────────────────────────────────────────────"
    print ("Private data: " + ($data_root | into string))
    print ""

    ^chezmoi --source ($data_root | into string) status
    print ""
    ^chezmoi --source ($data_root | into string) diff

    print ""
    print "Resolve configuration"
    print "────────────────────────────────────────────────────────────"
    print "  1) Save this machine -> private drive"
    print "  2) Apply private drive -> this machine"
    print "  3) Backup this machine, then apply private drive"
    print "  4) Cancel"
    print ""

    mut selected = ""
    while ($selected | is-empty) {
        let answer = (input "Select [1]: " | str trim)
        let choice = (if ($answer | is-empty) { "1" } else { $answer })

        match $choice {
            "1" => { $selected = "push" }
            "2" => { $selected = "pull" }
            "3" => { $selected = "backup-pull" }
            "4" => { $selected = "cancel" }
            _ => { print "Choose 1, 2, 3, or 4." }
        }
    }

    match $selected {
        "push" => {
            print ""
            print "[sync] Publishing local managed configuration to private drive..."
            run-script "sync-up.nu"
        }
        "pull" => {
            print ""
            print "[sync] Applying private configuration to this machine..."
            run-script "sync-down.nu" "--force"
        }
        "backup-pull" => {
            print ""
            print "[backup] Saving current local configuration..."
            run-script "backup-local-config.nu" "--label" "before-private-pull"
            print "[sync] Applying private configuration to this machine..."
            run-script "sync-down.nu" "--force"
        }
        _ => {
            print "No configuration changes were applied."
        }
    }
}
