#!/usr/bin/env nu

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    open $file
}

def ssh-private-key-present [] {
    let ssh_dir = ((nu-home) | path join ".ssh")

    if not ($ssh_dir | path exists) { return false }

    let ignored = ["config" "config.local" "known_hosts" "known_hosts.old" "authorized_keys"]
    let files = (ls $ssh_dir | where type == file)

    for item in $files {
        let name = ($item.name | path basename)

        if ($name | str ends-with ".pub") { continue }
        if $name in $ignored { continue }

        return true
    }

    false
}

def git-identity-present [] {
    if (which git | is-empty) { return false }

    let email = (^git config --global user.email | str trim)
    let exit_code = ($env.LAST_EXIT_CODE | default 1)
    $exit_code == 0 and not ($email | is-empty)
}

def folder-git-identities-present [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "git-identities.nuon")

    if not ($file | path exists) {
        return false
    }

    let manifest = (open $file)
    let identities = ($manifest.identities? | default [])

    $identities | any { |identity| $identity.enabled? | default true }
}

def main [] {
    let context = (machine-context)
    let secrets_file = ($nu.data-dir | path join "vendor" "autoload" "dotfiles-secrets.nu")
    let font_marker = ((nu-home) | path join ".config" "dotfiles" "fonts" "d2coding.nuon")

    print ""
    print "Post-setup checklist"
    print "────────────────────────────────"

    if (git-identity-present) {
        print "[ok] Git global identity is configured"
    } else if (folder-git-identities-present) {
        print "[ok] Folder-specific Git identities are configured"
    } else {
        print "[ ] Configure a global Git identity or run `dotgitids --edit`"
    }

    if (ssh-private-key-present) {
        print "[ok] At least one machine-local SSH private key appears to exist"
        print "[ ] Run `dotsshkeys` to verify matching public keys"
    } else {
        print "[ ] Restore/generate SSH private keys if this machine needs SSH authentication"
    }

    if ($secrets_file | path exists) {
        print "[ ] Review machine-local API tokens/secrets with `dotsecrets`"
    } else {
        print "[ ] Create machine-local secrets if required"
    }

    if $context.features.fonts {
        if ($font_marker | path exists) {
            print "[ok] D2Coding installation was detected or completed"
        } else {
            print "[ ] Verify D2Coding installation"
        }
    }

    print "[ ] Verify Private Cloud client login and sync status"
    print "[ ] Authenticate GitHub/Git hosting credentials if required"
    print "[ ] Sign in to VS Code extensions/services that require accounts"
    print "[ ] Run `dotaudit` after any manual credential/tool restoration"
    print "[ ] Use `dotpreflight --diff` before accepting unexpected private-source changes"
    print "[ ] Use `dotlocalbackup` before large manual configuration edits"

    if $context.features.julia {
        print "[ ] Instantiate Julia environments when first used on this machine"
    }

    print ""
    print "[ ] Add computer-specific Nushell setup with `dotlocal` if needed"
}
