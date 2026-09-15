#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def powershell-command [] {
    if not (which pwsh | is-empty) { return "pwsh" }
    if not (which powershell | is-empty) { return "powershell" }
    ""
}

def main [
    mode: string
    package_id: string
    --source: string = "winget"
] {
    if $nu.os-info.name != "windows" {
        exit 2
    }

    if (which winget | is-empty) {
        exit 2
    }

    let shell = (powershell-command)

    if ($shell | is-empty) {
        exit 2
    }

    let script = ($TOOLS_ROOT | path join "scripts" "windows" "winget-package-state.ps1")
    let args = [
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        ($script | into string)
        "-Mode"
        $mode
        "-PackageId"
        $package_id
        "-Source"
        $source
    ]

    ^$shell ...$args | ignore
    exit ($env.LAST_EXIT_CODE | default 2)
}
