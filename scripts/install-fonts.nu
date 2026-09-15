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

def run-program [label: string program: string args: list] {
    print ("[run] " + $label)
    ^$program ...$args
    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        print ("[warn] " + $label + " returned exit code " + ($exit_code | into string))
    }

    $exit_code
}

def marker-file [] {
    (nu-home) | path join ".config" "dotfiles" "fonts" "d2coding.nuon"
}

def mark-installed [method: string] {
    let file = (marker-file)
    mkdir ($file | path dirname)

    {
        font: "D2Coding"
        method: $method
        checked_at: (date now | format date "%Y-%m-%d %H:%M:%S %z")
    }
    | to nuon
    | save --force $file
}

def windows-font-present [] {
    let local_app_data = ($env.LOCALAPPDATA? | default "")
    let windows_dir = ($env.WINDIR? | default "C:\\Windows")
    mut patterns = []

    if not ($local_app_data | is-empty) {
        let local_fonts = ($local_app_data | path join "Microsoft" "Windows" "Fonts" | into string | str replace --all '\' '/')
        $patterns = ($patterns | append ($local_fonts + "/*D2Coding*"))
    }

    let system_fonts = ($windows_dir | path join "Fonts" | into string | str replace --all '\' '/')
    $patterns = ($patterns | append ($system_fonts + "/*D2Coding*"))

    for pattern in $patterns {
        let matches = (glob $pattern)
        if not ($matches | is-empty) { return true }
    }

    false
}

def unix-font-present [] {
    let home = (nu-home)
    let candidates = [
        ($home | path join ".local" "share" "fonts")
        ($home | path join ".fonts")
        ($home | path join "Library" "Fonts")
    ]

    for dir in $candidates {
        if not ($dir | path exists) { continue }

        let normalized = ($dir | into string | str replace --all '\' '/')
        let matches = (glob ($normalized + "/**/*D2Coding*"))

        if not ($matches | is-empty) { return true }
    }

    false
}

def d2coding-present [] {
    if $nu.os-info.name == "windows" { return (windows-font-present) }
    unix-font-present
}

def install-windows [] {
    let shell = (
        if not (which pwsh | is-empty) {
            "pwsh"
        } else if not (which powershell | is-empty) {
            "powershell"
        } else {
            ""
        }
    )

    if ($shell | is-empty) {
        print "[warn] PowerShell not found; D2Coding installation skipped."
        return false
    }

    let command = "irm https://github.com/naver/d2-coding-font/raw/master/install/install.ps1 | iex"
    let exit_code = (run-program "Install D2Coding with official PowerShell installer" $shell ["-NoProfile" "-Command" $command])
    $exit_code == 0
}

def install-macos [] {
    if not (which brew | is-empty) {
        let exit_code = (run-program "Install D2Coding with Homebrew" "brew" ["install" "--cask" "font-d2coding"])
        if $exit_code == 0 { return true }
    }

    if (which curl | is-empty) or (which sh | is-empty) {
        print "[warn] curl and sh are required for the D2Coding fallback installer."
        return false
    }

    let command = "curl -fsSL https://github.com/naver/d2-coding-font/raw/master/install/install.sh | sh"
    let exit_code = (run-program "Install D2Coding with official installer" "sh" ["-c" $command])
    $exit_code == 0
}

def install-linux [] {
    if (which curl | is-empty) or (which sh | is-empty) {
        print "[warn] curl and sh are required for D2Coding installation."
        return false
    }

    let command = "curl -fsSL https://github.com/naver/d2-coding-font/raw/master/install/install.sh | sh"
    let exit_code = (run-program "Install D2Coding with official installer" "sh" ["-c" $command])
    $exit_code == 0
}

def main [] {
    let context = (machine-context)

    if not $context.features.fonts {
        print "[skip] Font installation disabled"
        return
    }

    if (d2coding-present) {
        mark-installed "detected"
        print "[ok] D2Coding already available"
        return
    }

    let installed = (
        if $nu.os-info.name == "windows" {
            install-windows
        } else if $nu.os-info.name == "macos" {
            install-macos
        } else if $nu.os-info.name == "linux" {
            install-linux
        } else {
            false
        }
    )

    if $installed {
        mark-installed "automatic"
        print "[ok] D2Coding installation completed"
        print "[info] Restart terminals/editors before checking the new font."
    } else {
        print "[warn] D2Coding could not be installed automatically."
    }
}
