#!/usr/bin/env nu

const ROOT = path self ..

# Static regression guard for Phase 2. Installer scripts must use the shared
# subprocess contract instead of reading LAST_EXIT_CODE after the fact.
def main [] {
    let installers = (ls ($ROOT | path join "scripts") | where type == file | get name | where {|file| ($file | path basename | str starts-with "install-") and ($file | str ends-with ".nu") })
    mut failures = []

    for file in $installers {
        let source = (open --raw $file)
        if ($source | str contains "$env.LAST_EXIT_CODE") {
            $failures = ($failures | append (($file | path basename) + ": direct LAST_EXIT_CODE use"))
        }
        if ($source | str contains "do { ^") and not (($file | path basename) in ["install-fonts.nu"]) {
            $failures = ($failures | append (($file | path basename) + ": direct external-command complete path"))
        }
    }

    for required in [
        "scripts/modules/subprocess.nu"
        "scripts/modules/install-utils.nu"
    ] {
        if not (($ROOT | path join $required) | path exists) {
            $failures = ($failures | append ("missing shared installer module: " + $required))
        }
    }

    let bootstrap = (open --raw ($ROOT | path join "bootstrap.sh"))
    if not ($bootstrap | str contains "healthy_version chezmoi") {
        $failures = ($failures | append "bootstrap.sh does not health-check chezmoi")
    }
    if ($ROOT | path join "install.sh" | path exists) {
        $failures = ($failures | append "install.sh must remain absent")
    }

    if not ($failures | is-empty) {
        for item in $failures { print --stderr ("[FAIL] " + $item) }
        exit 1
    }
    print ("[pass] installer health-policy regression guard: " + (($installers | length) | into string) + " installer scripts")
}
