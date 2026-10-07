#!/usr/bin/env nu
const CORE = path self ./modules/core.nu
use $CORE [nu-home project-version project-schema-version]
const TOOLS_ROOT = path self ..
const MACHINE_CONFIG = path self ./modules/machine-config.nu
use $MACHINE_CONFIG [write-machine-config]

def config-path [] {
    (nu-home) | path join ".config" "dotfiles" "config.nuon"
}

def migrate-0-to-1 [config: record] {
    let without_legacy = (
        if ($config | get --optional version) == null {
            $config
        } else {
            $config | reject version
        }
    )

    $without_legacy
    | upsert app_version (project-version $TOOLS_ROOT)
    | upsert schema_version 1
}

def migrate-1-to-2 [config: record] {
    let old_sync = ($config.sync? | default {})
    let new_sync = ($old_sync | upsert prune_extras ($old_sync.prune_extras? | default false))

    $config
    | upsert sync $new_sync
    | upsert schema_version 2
}

def migrate-2-to-3 [config: record] {
    let old_features = ($config.features? | default {})
    let new_features = ($old_features | upsert rclone_config ($old_features.rclone_config? | default true))

    $config
    | upsert features $new_features
    | upsert schema_version 3
}

def migrate-3-to-4 [config: record] {
    let old_features = ($config.features? | default {})
    let profile = ($config.machine.profile? | default "workstation")
    let default_enabled = ($profile == "workstation" or $profile == "laptop")
    let new_features = (
        $old_features
        | upsert onedrive_ignore_uploads ($old_features.onedrive_ignore_uploads? | default $default_enabled)
    )

    $config
    | upsert features $new_features
    | upsert schema_version 4
}


def migrate-4-to-5 [config: record] {
    let old_machine = ($config.machine? | default {})
    let profile = ($old_machine.profile? | default "workstation")
    let machine = ($old_machine.name? | default "unknown-machine")
    let layers = { common: "common" os: $nu.os-info.name role: $profile machine: $machine }
    $config | upsert machine ($old_machine | upsert layers $layers) | upsert schema_version 5
}

def migrate-step [config: record from_schema: int] {
    match $from_schema {
        0 => { migrate-0-to-1 $config }
        1 => { migrate-1-to-2 $config }
        2 => { migrate-2-to-3 $config }
        3 => { migrate-3-to-4 $config }
        4 => { migrate-4-to-5 $config }
        _ => {
            error make {
                msg: (
                    "No machine-config migration is defined from schema " + ($from_schema | into string) + "."
                )
            }
        }
    }
}

def main [--check --transaction --expected-sha256: string = ""] {
    let file = (config-path)
    let current_schema = (project-schema-version $TOOLS_ROOT)
    let current_app = (project-version $TOOLS_ROOT)

    if not ($file | path exists) {
        print "[ok] No machine config exists yet; migration is not required."
        return
    }

    if $transaction and not $check {
        let expected = ($expected_sha256 | str trim)
        if not ($expected =~ '^[a-f0-9]{64}$') {
            error make {msg: "Transaction mode requires --expected-sha256 from the verified preflight backup."}
        }
        let actual = (open --raw $file | hash sha256)
        if $actual != $expected {
            error make {msg: "Machine config changed after migration preflight; refusing to commit."}
        }
    }

    let original = (open $file)
    let detected_schema = ($original.schema_version? | default 0)

    if $detected_schema > $current_schema {
        error make {
            msg: (
                "Machine config schema " + ($detected_schema | into string) + " is newer than this Initial-setup supports (" + ($current_schema | into string) + ")."
            )
        }
    }

    if $check {
        print ("Machine config : " + ($file | into string))
        print ("Detected schema: " + ($detected_schema | into string))
        print ("Current schema : " + ($current_schema | into string))

        if $detected_schema == $current_schema {
            print "[ok] Machine config schema is current."
        } else {
            print "[warn] Machine config requires migration."
        }

        return
    }

    mut migrated = $original
    mut schema = $detected_schema

    if ($schema < $current_schema) and (not $transaction) {
        let backup = (($file | into string) + ".pre-schema-v" + ($current_schema | into string))

        if not ($backup | path exists) {
            cp $file $backup
            print ("[backup] " + $backup)
        }
    }

    while $schema < $current_schema {
        $migrated = (migrate-step $migrated $schema)
        $schema = ($migrated.schema_version? | default ($schema + 1))
    }

    $migrated = ($migrated | upsert app_version $current_app | upsert schema_version $current_schema)

    write-machine-config $migrated | ignore

    print ("[ok] Machine config schema " + ($detected_schema | into string) + " -> " + ($current_schema | into string))
}
