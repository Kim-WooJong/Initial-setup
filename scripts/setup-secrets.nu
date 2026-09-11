#!/usr/bin/env nu

# ============================================================
# Create a machine-local Nushell autoload file for secrets.
# This file is intentionally outside the synchronized source.
# ============================================================

def main [] {
    let autoload_dir = ($nu.data-dir | path join "vendor" "autoload")
    let secrets_file = ($autoload_dir | path join "dotfiles-secrets.nu")

    mkdir $autoload_dir

    if not ($secrets_file | path exists) {
        [
            "# Machine-local secrets for Nushell."
            "# This file is intentionally NOT synchronized."
            "#"
            "# Examples:"
            '# $env.OPENAI_API_KEY = "..."'
            '# $env.GITHUB_TOKEN = "..."'
            ""
        ]
        | str join (char nl)
        | save $secrets_file

        print ("[create] " + ($secrets_file | into string))
    } else {
        print "[ok] Local secrets autoload already exists"
    }
}
