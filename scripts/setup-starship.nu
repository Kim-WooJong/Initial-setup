#!/usr/bin/env nu

# ============================================================
# Generate Starship's machine-local Nushell vendor autoload.
# ============================================================

def find-starship [] {
    let found = (which starship)

    if not ($found | is-empty) {
        return (
            $found
            | first
            | get path
            | path expand
        )
    }

    if $nu.os-info.name == "windows" {
        let local_appdata = ($env.LOCALAPPDATA? | default "")

        if not ($local_appdata | is-empty) {
            let candidate = (
                $local_appdata
                | path join "Microsoft" "WinGet" "Links" "starship.exe"
            )

            if ($candidate | path exists) {
                return $candidate
            }
        }
    }

    null
}

def main [] {
    let starship = (find-starship)

    if $starship == null {
        print "[skip] Starship executable is not visible yet."
        print "[info] Restart Nushell and rerun setup-starship.nu."
        return
    }

    let autoload_dir = (
        $nu.data-dir
        | path join "vendor" "autoload"
    )

    let autoload_file = (
        $autoload_dir
        | path join "starship.nu"
    )

    mkdir $autoload_dir

    let args = [
        "init"
        "nu"
    ]

    ^$starship ...$args
    | save --force $autoload_file

    if $env.LAST_EXIT_CODE != 0 {
        error make {
            msg: "starship init nu failed"
        }
    }

    print $"[ok] Starship Nushell integration -> ($autoload_file)"
}
