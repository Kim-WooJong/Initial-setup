#!/usr/bin/env nu
# Standalone dependency installer; no machine config, remote or credential needed.
const MODULE = path self ./modules/rclone-install.nu
use $MODULE [ensure-rclone]

def main [--dry-run --check] {
    let result = (ensure-rclone --dry-run=$dry_run --check=$check)
    if $result.state == "planned" {
        print "[dry-run] No packages or configuration files will be changed."
        if not $result.supported { print ("[blocked] " + $result.reason) }
        for step in $result.steps {
            print ("[would-run] " + $step.label)
            if $step.kind == "command" { print ([$step.program] | append $step.args | str join " ") }
        }
    } else {
        print ("[ok] " + $result.version + " (" + $result.state + ")")
        print ("[path] " + $result.path)
        if $result.manager == "brew" {
            print "[note] Homebrew rclone on macOS does not include the FUSE mount subcommand. This setup uses file-transfer commands, not mount."
        }
    }
}
