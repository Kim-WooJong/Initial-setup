const CORE = path self ./core.nu
use $CORE [nu-home]
const SUBPROCESS = path self ./subprocess.nu
use $SUBPROCESS [run-command]
# Shared Starship discovery and health checks.
#
# A Starship executable is considered usable only when both `--version`
# and `init nu` complete successfully. This avoids treating a stale PATH
# entry or a broken package installation as a valid prompt integration.

def add-candidate [paths: list candidate: any] {
    if $candidate == null {
        return $paths
    }

    let raw = ($candidate | into string | str trim)
    if ($raw | is-empty) {
        return $paths
    }

    let expanded = ($raw | path expand)
    if not ($expanded | path exists) {
        return $paths
    }

    if ($paths | any {|item| ($item | into string) == ($expanded | into string) }) {
        return $paths
    }

    $paths | append $expanded
}

def starship-candidates [] {
    mut paths = []

    let discovered = (which starship)
    if not ($discovered | is-empty) {
        for item in $discovered {
            $paths = (add-candidate $paths ($item | get --optional path))
        }
    }

    let home = (nu-home)
    let executable = if $nu.os-info.name == "windows" { "starship.exe" } else { "starship" }

    let cargo_home = ($env.CARGO_HOME? | default ($home | path join ".cargo"))
    $paths = (add-candidate $paths ($cargo_home | path join "bin" $executable))
    $paths = (add-candidate $paths ($home | path join ".local" "bin" $executable))

    if $nu.os-info.name == "windows" {
        let local_appdata = ($env.LOCALAPPDATA? | default "" | str trim)
        if not ($local_appdata | is-empty) {
            $paths = (add-candidate $paths ($local_appdata | path join "Microsoft" "WinGet" "Links" "starship.exe"))
        }

        $paths = (add-candidate $paths ($home | path join "scoop" "shims" "starship.exe"))
    }

    $paths
}

def probe-starship [path: path] {
    let version_result = (run-command ($path | into string) ["--version"])
    let version_stdout = ($version_result.stdout? | default "" | str trim)
    let version_stderr = ($version_result.stderr? | default "" | str trim)

    if (($version_result.exit_code? | default 1) != 0) {
        return {
            path: $path
            healthy: false
            version: $version_stdout
            version_exit_code: ($version_result.exit_code? | default 1)
            init_exit_code: null
            stderr: $version_stderr
            init_script: ""
        }
    }

    let init_result = (run-command ($path | into string) ["init" "nu"])
    let init_stdout = ($init_result.stdout? | default "")
    let init_stderr = ($init_result.stderr? | default "" | str trim)
    let init_exit_code = ($init_result.exit_code? | default 1)
    let script_nonempty = (not ($init_stdout | str trim | is-empty))

    {
        path: $path
        healthy: ($init_exit_code == 0 and $script_nonempty)
        version: $version_stdout
        version_exit_code: ($version_result.exit_code? | default 0)
        init_exit_code: $init_exit_code
        stderr: $init_stderr
        init_script: $init_stdout
    }
}

export def probe-starship-candidates [] {
    starship-candidates | each {|candidate| probe-starship $candidate }
}

export def resolve-starship [] {
    let probes = (probe-starship-candidates)
    let healthy = ($probes | where healthy == true)

    if ($healthy | is-empty) {
        return null
    }

    $healthy | first
}
