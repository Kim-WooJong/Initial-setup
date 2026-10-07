#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home machine-context]
const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command]

# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def post-status [
    kind: string
    message: string
] {
    let prefix = match $kind {
        "ok" => "[ok]"
        "warn" => "[warn]"
        "manual" => "[manual]"
        "info" => "[info]"
        _ => "[info]"
    }

    print $"($prefix) ($message)"
}

# ----------------------------------------------------------------
# Git
# ----------------------------------------------------------------

def git-identity-present [] {
    if (which git | is-empty) {
        return false
    }

    let result = (run-command "git" [
        "config"
        "--global"
        "user.email"
    ])

    $result.ok and not ($result.stdout | str trim | is-empty)
}

def folder-git-identities-present [] {
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "git-identities.nuon"
    )

    if not ($file | path exists) {
        return false
    }

    let manifest = (open $file)
    let identities = ($manifest.identities? | default [])

    $identities
    | any { |identity|
        $identity.enabled? | default true
    }
}

# ----------------------------------------------------------------
# GitHub CLI
# ----------------------------------------------------------------

def github-cli-present [] {
    not (which gh | is-empty)
}

def github-auth-ok [] {
    if not (github-cli-present) {
        return false
    }

    let result = (run-command "gh" [
        "auth"
        "status"
        "--active"
    ])

    $result.ok
}

# ----------------------------------------------------------------
# SSH
# ----------------------------------------------------------------

def ssh-private-key-present [] {
    let ssh_dir = ((nu-home) | path join ".ssh")

    if not ($ssh_dir | path exists) {
        return false
    }

    let ignored = [
        "config"
        "config.local"
        "known_hosts"
        "known_hosts.old"
        "authorized_keys"
    ]

    let files = (
        ls $ssh_dir
        | where type == file
    )

    for item in $files {
        let name = ($item.name | path basename)

        if ($name | str ends-with ".pub") {
            continue
        }

        if $name in $ignored {
            continue
        }

        return true
    }

    false
}

# ----------------------------------------------------------------
# Tools
# ----------------------------------------------------------------

def vscode-present [] {
    not (which code | is-empty)
}

def julia-present [] {
    not (which julia | is-empty)
}

# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------

def main [] {
    let context = (machine-context)

    let secrets_file = (
        $nu.data-dir
        | path join "vendor" "autoload" "dotfiles-secrets.nu"
    )

    let font_marker = (
        (nu-home)
        | path join ".config" "dotfiles" "fonts" "d2coding.nuon"
    )

    print ""
    print "Post-setup status"
    print "────────────────────────────────"

    # ------------------------------------------------------------
    # Git identity
    # ------------------------------------------------------------

    if (git-identity-present) {
        post-status "ok" "Git global identity is configured"
    } else if (folder-git-identities-present) {
        post-status "ok" "Folder-specific Git identities are configured"
    } else {
        post-status "warn" "Git identity is not configured; configure one globally or run `dotgitids --edit`"
    }

    # ------------------------------------------------------------
    # SSH
    # ------------------------------------------------------------

    if (ssh-private-key-present) {
        post-status "ok" "At least one machine-local SSH private key appears to exist"
        post-status "manual" "Run `dotsshkeys` to verify matching public keys"
    } else {
        post-status "warn" "No machine-local SSH private key was detected"
        post-status "info" "Restore or generate SSH keys if this machine requires SSH authentication"
    }

    # ------------------------------------------------------------
    # Machine-local secrets
    # ------------------------------------------------------------

    if ($secrets_file | path exists) {
        post-status "ok" "Machine-local secrets file is present"
        post-status "info" "Run `dotsecrets` when API tokens or local secrets need review"
    } else {
        post-status "info" "No machine-local secrets file exists; create one only if required"
    }

    # ------------------------------------------------------------
    # Fonts
    # ------------------------------------------------------------

    if ($context.features.fonts? | default false) {
        if ($font_marker | path exists) {
            post-status "ok" "D2Coding installation was detected or completed"
        } else {
            post-status "warn" "D2Coding installation could not be verified"
        }
    }

    # ------------------------------------------------------------
    # Private cloud
    #
    # Login/sync completion cannot currently be reliably determined
    # from this script, so this remains a manual check.
    # ------------------------------------------------------------

    post-status "manual" "Verify Private Cloud client login and sync status"

    # ------------------------------------------------------------
    # GitHub CLI
    # ------------------------------------------------------------

    if (github-auth-ok) {
        post-status "ok" "GitHub CLI authentication is valid"
    } else if (github-cli-present) {
        post-status "warn" "GitHub CLI is installed but authentication is not valid; run `gh auth login`"
    } else {
        post-status "info" "GitHub CLI is not installed; configure Git hosting credentials if required"
    }

    # ------------------------------------------------------------
    # VS Code
    # ------------------------------------------------------------

    if (vscode-present) {
        post-status "ok" "VS Code command-line interface is available"
        post-status "manual" "Sign in to VS Code extensions/services that require accounts"
    } else {
        post-status "info" "VS Code command-line interface was not detected"
    }

    # ------------------------------------------------------------
    # Julia
    # ------------------------------------------------------------

    if ($context.features.julia? | default false) {
        if (julia-present) {
            post-status "ok" "Julia is available"
        } else {
            post-status "warn" "Julia support is enabled but Julia was not found in PATH"
        }
    }

    print ""
    print "Operational guidance"
    print "────────────────────────────────"

    post-status "info" "Run `dotaudit` after manual credential/tool restoration"
    post-status "info" "Use `dotpreflight --diff` before accepting unexpected private-source changes"
    post-status "info" "Use `dotlocalbackup` before large manual configuration edits"

    if ($context.features.julia? | default false) {
        post-status "info" "Instantiate Julia environments when first used on this machine"
    }

    post-status "info" "Add computer-specific Nushell setup with `dotlocal` only if needed"
}
