const SUBPROCESS = path self ./subprocess.nu
use $SUBPROCESS [run-command print-result]
const CORE = path self ./core.nu
use $CORE [nu-home]

def tool-candidates [name: string extra: list = []] {
    mut out = []
    let rows = (which ("^" + $name))
    for row in $rows {
        let p = ($row.path? | default "")
        if not ($p | is-empty) and not ($p in $out) { $out = ($out | append $p) }
    }
    for candidate in $extra {
        let p = ($candidate | path expand)
        if ($p | path exists) and not (($p | into string) in ($out | each {|x| $x | into string })) {
            $out = ($out | append $p)
        }
    }
    $out
}

export def probe-tool [name: string args: list = ["--version"] extra: list = []] {
    let candidates = (tool-candidates $name $extra)
    if ($candidates | is-empty) {
        return {found: false healthy: false path: "" version: "" result: null}
    }
    mut first_failure: any = null
    for candidate in $candidates {
        let result = (run-command ($candidate | into string) $args)
        let version_lines = (($result.stdout + "\n" + $result.stderr) | lines | where {|x| not ($x | str trim | is-empty) })
        let version = ($version_lines | get 0? | default "" | str trim)
        if $result.ok {
            return {found: true healthy: true path: ($candidate | into string) version: $version result: $result}
        }
        if $first_failure == null { $first_failure = {path: ($candidate | into string) result: $result} }
    }
    {found: true healthy: false path: $first_failure.path version: "" result: $first_failure.result}
}

export def run-installer [label: string program: string args: list] {
    print ("[run] " + $label)
    let result = (run-command $program $args)
    print-result $label $result
    $result
}

export def winget-package-state [tools_root: path package_id: string source: string = "winget"] {
    let script = ($tools_root | path join "scripts" "winget-package-state.nu")
    let result = (run-command ($nu.current-exe | into string) ["--no-config-file" $script "installed" $package_id "--source" $source])
    if not $result.launched { return "error" }
    match $result.exit_code {
        0 => "yes"
        10 => "no"
        _ => "error"
    }
}

export def linux-is-root [] {
    let result = (run-command "id" ["-u"])
    $result.ok and ($result.stdout | str trim) == "0"
}

export def privileged-command [program: string args: list] {
    if (linux-is-root) { return {ok: true program: $program args: $args reason: ""} }
    let sudo_probe = (probe-tool "sudo" ["-V"])
    if not $sudo_probe.healthy {
        return {ok: false program: "" args: [] reason: ("Root privileges are required for " + $program + ", but sudo is unavailable or unhealthy.")}
    }
    {ok: true program: "sudo" args: ([$program] | append $args) reason: ""}
}

export def user-tool-paths [] {
    let home = (nu-home)
    {
        cargo: ($home | path join ".cargo" "bin")
        juliaup: ($home | path join ".juliaup" "bin")
        local: ($home | path join ".local" "bin")
    }
}
