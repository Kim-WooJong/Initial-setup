#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def nu-home [] {
    let home_path = ($nu | get --optional home-path)
    if $home_path != null { return $home_path }

    let home_dir = ($nu | get --optional home-dir)
    if $home_dir != null { return $home_dir }

    error make { msg: "Unable to determine the Nushell home directory." }
}

def config-path [] {
    (nu-home) | path join ".config" "dotfiles" "config.nuon"
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

def migrate-0-to-1 [config: record] {
    let without_legacy = (
        if ($config | get --optional version) == null {
            $config
        } else {
            $config | reject version
        }
    )

    $without_legacy
    | upsert app_version (app-version)
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

def migrate-step [config: record from_schema: int] {
    match $from_schema {
        0 => { migrate-0-to-1 $config }
        1 => { migrate-1-to-2 $config }
        2 => { migrate-2-to-3 $config }
        3 => { migrate-3-to-4 $config }
        _ => {
            error make {
                msg: (
                    "No machine-config migration is defined from schema " + ($from_schema | into string) + "."
                )
            }
        }
    }
}

def main [--check] {
    let file = (config-path)
    let current_schema = (schema-version)
    let current_app = (app-version)

    if not ($file | path exists) {
        print "[ok] No machine config exists yet; migration is not required."
        return
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

    if $schema < $current_schema {
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

    $migrated | to nuon | save --force $file

    print ("[ok] Machine config schema " + ($detected_schema | into string) + " -> " + ($current_schema | into string))
}
