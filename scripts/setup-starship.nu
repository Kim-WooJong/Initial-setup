#!/usr/bin/env nu

use modules/starship.nu [probe-starship-candidates resolve-starship]

# ============================================================
# Generate Starship's machine-local Nushell vendor autoload.
#
# Starship is optional. A broken Starship executable must not
# abort the rest of machine setup. The generated script is only
# replaced after `starship init nu` succeeds and produces output.
# ============================================================

def print-probe-failure [probe: record] {
    print ("[warn] Unusable Starship candidate: " + ($probe.path | into string))

    if ($probe.version | str trim | is-empty) == false {
        print ("       version: " + ($probe.version | str trim))
    }

    if $probe.init_exit_code != null {
        print ("       `starship init nu` exit code: " + ($probe.init_exit_code | into string))
    } else {
        print ("       `starship --version` exit code: " + ($probe.version_exit_code | into string))
    }

    let stderr = ($probe.stderr | str trim)
    if not ($stderr | is-empty) {
        print "       stderr:"
        print $stderr
    }
}

def main [] {
    let selected = (resolve-starship)

    if $selected == null {
        let probes = (probe-starship-candidates)

        if ($probes | is-empty) {
            print "[skip] Starship executable is not visible."
        } else {
            print "[warn] Starship is installed or visible, but Nushell initialization is not healthy."
            for probe in $probes {
                print-probe-failure $probe
            }
        }

        print "[warn] Starship is optional; setup will continue without changing the existing autoload file."
        print "[info] Run `starship --version` and `starship init nu` manually for the underlying error."
        return
    }

    let autoload_dir = ($nu.data-dir | path join "vendor" "autoload")
    let autoload_file = ($autoload_dir | path join "starship.nu")

    mkdir $autoload_dir

    try {
        # Keep the previous working autoload untouched until Starship has already
        # returned a complete initialization script in memory.
        $selected.init_script | save --force $autoload_file
    } catch {|err|
        print ("[warn] Could not write Starship Nushell integration: " + ($err.msg? | default ($err | into string)))
        print "[warn] Starship is optional; setup will continue without replacing the existing autoload file."
        return
    }

    print ("[ok] Starship " + ($selected.version | str trim))
    print ("[ok] Starship executable -> " + ($selected.path | into string))
    print ("[ok] Starship Nushell integration -> " + ($autoload_file | into string))
}
