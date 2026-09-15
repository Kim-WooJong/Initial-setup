#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def app-version [] {
    open --raw ($TOOLS_ROOT | path join "VERSION")
    | decode utf-8
    | str trim
}

def schema-version [] {
    open --raw ($TOOLS_ROOT | path join "SCHEMA_VERSION")
    | decode utf-8
    | str trim
    | into int
}

def main [] {
    let config_file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")
    let conflict_file = ((nu-home) | path join ".config" "dotfiles" "SYNC-CONFLICT.txt")
    let tool_state = ((nu-home) | path join ".config" "dotfiles" "state" "tools.nuon")

    mut critical = 0
    mut warnings = 0

    print "Initial-setup audit"
    print "==================="

    if not ($config_file | path exists) {
        print "[FAIL] Machine config is missing."
        exit 1
    }

    let context = (open $config_file)
    let expected_app = (app-version)
    let expected_schema = (schema-version)
    let actual_app = ($context.app_version? | default (($context | get --optional version) | default "unknown"))
    let actual_schema = ($context.schema_version? | default 0)

    print ("Application    : " + $actual_app + " / expected " + $expected_app)
    print ("Config schema  : " + ($actual_schema | into string) + " / expected " + ($expected_schema | into string))
    print ("Machine        : " + $context.machine.name)
    print ("Profile        : " + $context.machine.profile)
    print ("Prune extras   : " + (($context.sync.prune_extras? | default false) | into string))
    print ""

    if $actual_app == $expected_app {
        print "[ok] Application version matches machine config."
    } else {
        print "[WARN] Machine config app_version differs from repository VERSION."
        $warnings = $warnings + 1
    }

    if $actual_schema == $expected_schema {
        print "[ok] Machine config schema is current."
    } else {
        print "[FAIL] Machine config schema is not current."
        $critical = $critical + 1
    }

    let data_root = ($context.data_root | path expand)
    let tools_root = ($context.tools_root | path expand)

    if ($data_root | path exists) {
        print "[ok] Private data root exists."
    } else {
        print "[FAIL] Private data root is unavailable."
        $critical = $critical + 1
    }

    if ($tools_root | path exists) {
        print "[ok] Tools root exists."
    } else {
        print "[FAIL] Tools root is unavailable."
        $critical = $critical + 1
    }

    if (which chezmoi | is-empty) {
        print "[FAIL] chezmoi is not available."
        $critical = $critical + 1
    } else {
        print "[ok] chezmoi is available."
    }

    if (which git | is-empty) {
        print "[WARN] Git is not available."
        $warnings = $warnings + 1
    } else {
        print "[ok] Git is available."
    }

    if $context.features.neovim {
        if (which nvim | is-empty) {
            print "[FAIL] Neovim feature is enabled but nvim is unavailable."
            $critical = $critical + 1
        } else {
            print "[ok] Neovim is available."
        }
    }

    if $context.features.starship {
        if (which starship | is-empty) {
            print "[WARN] Starship feature is enabled but starship is unavailable."
            $warnings = $warnings + 1
        } else {
            print "[ok] Starship is available."
        }
    }

    if $context.features.rust {
        if (which cargo | is-empty) {
            print "[WARN] Rust feature is enabled but cargo is unavailable."
            $warnings = $warnings + 1
        } else {
            print "[ok] Cargo is available."
        }
    }

    if $context.features.julia {
        if (which julia | is-empty) {
            print "[WARN] Julia feature is enabled but julia is unavailable."
            $warnings = $warnings + 1
        } else {
            print "[ok] Julia is available."
        }
    }

    if ($conflict_file | path exists) {
        print "[FAIL] Automatic synchronization conflict marker exists."
        $critical = $critical + 1
    } else {
        print "[ok] No synchronization conflict marker."
    }

    if ($tool_state | path exists) {
        print "[ok] Tool-version snapshot exists."
    } else {
        print "[WARN] Tool-version snapshot is missing; run `dotstate`."
        $warnings = $warnings + 1
    }

    print ""
    print "Summary"
    print "-------"
    print ("Critical : " + ($critical | into string))
    print ("Warnings : " + ($warnings | into string))

    if $critical > 0 {
        exit 1
    }
}
