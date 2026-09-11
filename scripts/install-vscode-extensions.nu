#!/usr/bin/env nu

# ============================================================
# Reconcile VS Code extensions to exactly match the private
# extension list.
# ============================================================

def nu-home [] {
    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

def machine-context [] {
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

    if not ($file | path exists) {
        error make {
            msg: (
                "Machine config not found: "
                + ($file | into string)
            )
        }
    }

    open $file
}

def main [] {
    if (which code | is-empty) {
        print "[skip] VS Code CLI not found"
        return
    }

    let context = (
        machine-context
    )

    let data_root = (
        $context.data_root
        | path expand
    )

    let extension_file = (
        $data_root
        | path join "vscode" "extensions.txt"
    )

    if not ($extension_file | path exists) {
        print "[skip] VS Code extension list not found"
        return
    }

    let list_args = [
        "--list-extensions"
    ]

    let installed = (
        ^code ...$list_args
        | lines
        | where { |item|
            not ($item | is-empty)
        }
        | sort
        | uniq
    )

    let desired = (
        open --raw $extension_file
        | lines
        | where { |item|
            not ($item | is-empty)
        }
        | sort
        | uniq
    )

    let missing = (
        $desired
        | where { |extension|
            not ($extension in $installed)
        }
    )

    let extra = (
        $installed
        | where { |extension|
            not ($extension in $desired)
        }
    )

    for extension in $missing {
        print (
            "[install] "
            + $extension
        )

        let args = [
            "--install-extension"
            $extension
        ]

        ^code ...$args

        if $env.LAST_EXIT_CODE != 0 {
            print (
                "[warn] Failed to install "
                + $extension
            )
        }
    }

    for extension in $extra {
        print (
            "[remove] "
            + $extension
        )

        let args = [
            "--uninstall-extension"
            $extension
        ]

        ^code ...$args

        if $env.LAST_EXIT_CODE != 0 {
            print (
                "[warn] Failed to remove "
                + $extension
            )
        }
    }

    print "[ok] VS Code extension set reconciled"
}
