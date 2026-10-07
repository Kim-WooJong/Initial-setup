#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const CORE = path self ./modules/core.nu
const DIAGNOSTICS = path self ./modules/diagnostics.nu
use $CORE [nu-home project-version project-schema-version fixed-private-context]
use $DIAGNOSTICS [diagnostic-check tool-diagnostic print-diagnostic summarize-diagnostics]

def main [] {
    let config_file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    let conflict_file = ((nu-home) | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")
    let tool_state = ((nu-home) | path join ".config" "dotfiles" "state" "tools.nuon")

    print "Initial-setup audit"
    print "==================="

    if not ($config_file | path exists) {
        print "[FAIL] Machine config is missing."
        exit 1
    }

    let context = (fixed-private-context (open $config_file))
    let expected_app = (project-version $TOOLS_ROOT)
    let expected_schema = (project-schema-version $TOOLS_ROOT)
    let actual_app = ($context.app_version? | default (($context | get --optional version) | default "unknown"))
    let actual_schema = ($context.schema_version? | default 0)
    let data_root = ($context.data_root | path expand)
    let tools_root = ($context.tools_root | path expand)

    print ("Application    : " + $actual_app + " / expected " + $expected_app)
    print ("Config schema  : " + ($actual_schema | into string) + " / expected " + ($expected_schema | into string))
    print ("Machine        : " + $context.machine.name)
    print ("Profile        : " + $context.machine.profile)
    print ("Prune extras   : " + (($context.sync.prune_extras? | default false) | into string))
    print ""

    let data_root_ok = if ($data_root | path exists) { ($data_root | path type) == "dir" } else { false }
    let tools_root_ok = if ($tools_root | path exists) { ($tools_root | path type) == "dir" } else { false }

    mut checks = []
    $checks = ($checks | append (diagnostic-check "config:app-version" "Application version matches machine config" "warning" ($actual_app == $expected_app) (if $actual_app == $expected_app { $actual_app } else { "machine=" + $actual_app + ", repository=" + $expected_app }) "Run `nu setup.nu` after reviewing the configuration diff."))
    $checks = ($checks | append (diagnostic-check "config:schema" "Machine config schema is current" "critical" ($actual_schema == $expected_schema) ("machine=" + ($actual_schema | into string) + ", expected=" + ($expected_schema | into string)) "Run `nu setup.nu` or `dotdoctor --fix`."))
    $checks = ($checks | append (diagnostic-check "path:private-data" "Private data root exists" "critical" $data_root_ok ($data_root | into string) "Restore or reconnect the configured private data root."))
    $checks = ($checks | append (diagnostic-check "path:tools-root" "Tools root exists" "critical" $tools_root_ok ($tools_root | into string) "Update the machine config or restore the project directory."))

    $checks = ($checks | append (tool-diagnostic "chezmoi" ["--version"] "critical" "chezmoi"))
    $checks = ($checks | append (tool-diagnostic "git" ["--version"] "warning" "Git"))

    if $context.features.neovim {
        $checks = ($checks | append (tool-diagnostic "nvim" ["--version"] "warning" "Neovim"))
    }
    if $context.features.starship {
        $checks = ($checks | append (tool-diagnostic "starship" ["--version"] "warning" "Starship"))
    }
    if $context.features.rust {
        $checks = ($checks | append (tool-diagnostic "cargo" ["--version"] "warning" "Cargo"))
    }
    if $context.features.julia {
        $checks = ($checks | append (tool-diagnostic "julia" ["--version"] "warning" "Julia"))
    }

    $checks = ($checks | append (diagnostic-check "sync:conflict" "No synchronization conflict marker" "critical" (not ($conflict_file | path exists)) ($conflict_file | into string) "Resolve the conflict before the next automatic synchronization."))
    $checks = ($checks | append (diagnostic-check "state:tools" "Tool-version snapshot exists" "warning" ($tool_state | path exists) ($tool_state | into string) "Run `dotstate` to capture the current tool versions."))

    for row in $checks {
        print-diagnostic $row
    }

    let summary = (summarize-diagnostics $checks)
    print ""
    print "Summary"
    print "-------"
    print ("Passed   : " + ($summary.passed | into string))
    print ("Critical : " + ($summary.failed | into string))
    print ("Warnings : " + ($summary.warnings | into string))

    if $summary.failed > 0 { exit 1 }
}
