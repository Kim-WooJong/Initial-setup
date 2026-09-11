#!/usr/bin/env nu

# ============================================================
# Capture the exact current VS Code extension set.
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

    mkdir (
        $extension_file
        | path dirname
    )

    let args = [
        "--list-extensions"
    ]

    let current = (
        ^code ...$args
        | lines
        | where { |item|
            not ($item | is-empty)
        }
        | sort
        | uniq
        | str join (char nl)
    )

    let output = (
        if ($current | is-empty) {
            ""
        } else {
            $current
            + (char nl)
        }
    )

    $output
    | save --force $extension_file

    print (
        "[ok] VS Code extension set -> "
        + ($extension_file | into string)
    )
}
