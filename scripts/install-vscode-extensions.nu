#!/usr/bin/env nu

const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command print-result]

const INSTALL_UTILS = path self ./modules/install-utils.nu
use $INSTALL_UTILS [run-installer probe-tool winget-package-state linux-is-root privileged-command]

def nu-home [] {
    let test_mode = ($env.INITIAL_SETUP_TEST_MODE? | default "" | str trim)
    let override = ($env.INITIAL_SETUP_HOME_OVERRIDE? | default "" | str trim)

    if $test_mode == "1" and not ($override | is-empty) {
        return ($override | path expand)
    }

    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

def machine-context [] {
    let file = ((nu-home) | path join ".config" "dotfiles" "config.nuon")

    if not ($file | path exists) {
        error make { msg: ("Machine config not found: " + ($file | into string)) }
    }

    open $file
}

def main [--prune --source-root: string = ""] {
    if (which code | is-empty) {
        print "[skip] VS Code CLI not found"
        return
    }

    let context = (machine-context)
    let configured_prune = ($context.sync.prune_extras? | default false)
    let should_prune = ($prune or $configured_prune)
    let source_root = if ($source_root | str trim | is-empty) { $context.data_root | path expand } else { $source_root | path expand }
    let extension_file = ($source_root | path join "vscode" "extensions.txt")

    if not ($extension_file | path exists) {
        print "[skip] VS Code extension list not found"
        return
    }

    let list_result = (run-command "code" ["--list-extensions"])
    if not $list_result.ok {
        print-result "List VS Code extensions" $list_result
        return
    }
    let installed = ($list_result.stdout | lines | where { |item| not ($item | is-empty) } | sort | uniq)
    let desired = (open --raw $extension_file | lines | where { |item| not ($item | is-empty) } | sort | uniq)
    let missing = ($desired | where { |extension| not ($extension in $installed) })
    let extra = ($installed | where { |extension| not ($extension in $desired) })

    for extension in $missing {
        print ("[install] " + $extension)
        let result = (run-command "code" ["--install-extension" $extension])
        if not $result.ok {
            print-result ("Install VS Code extension " + $extension) $result
        }
    }

    if $should_prune {
        for extension in $extra {
            print ("[remove] " + $extension)
            let result = (run-command "code" ["--uninstall-extension" $extension])
            if not $result.ok {
                print-result ("Remove VS Code extension " + $extension) $result
            }
        }

        print "[ok] VS Code extension set reconciled in prune mode"
    } else {
        if not ($extra | is-empty) {
            print ("[keep] Preserving " + (($extra | length) | into string) + " local-only VS Code extension(s)")
        }

        print "[ok] VS Code extension set reconciled in merge mode"
    }
}
