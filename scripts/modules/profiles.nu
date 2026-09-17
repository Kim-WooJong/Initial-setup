# Declarative layered machine-profile loader.
# Merge order: common -> OS -> role/profile -> repository machine -> local machine.

const PROFILES_ROOT = path self ../../profiles
const CORE_MODULE = path self ./core.nu
use $CORE_MODULE [nu-home]

export def profile-names [] {
    ["workstation" "laptop" "server" "minimal"]
}

export def machine-overlay-path [] {
    (nu-home) | path join ".config" "dotfiles" "machine-overlay.nuon"
}

def open-record-if-exists [file: path] {
    if ($file | path exists) { open $file } else { {} }
}

def merge-profile [base: record overlay: record] {
    let base_features = ($base.features? | default {})
    let overlay_features = ($overlay.features? | default {})
    ($base | merge $overlay) | upsert features ($base_features | merge $overlay_features)
}

export def profile-defaults [profile: string machine_name: string = ""] {
    if not ($profile in (profile-names)) {
        error make {
            msg: ("Unknown profile '" + $profile + "'. Use " + ((profile-names) | str join ", ") + ".")
        }
    }

    let common_file = ($PROFILES_ROOT | path join "common.nuon")
    let role_file = ($PROFILES_ROOT | path join ($profile + ".nuon"))
    let os_file = ($PROFILES_ROOT | path join "os" ($nu.os-info.name + ".nuon"))

    if not ($common_file | path exists) {
        error make { msg: ("Common profile manifest not found: " + ($common_file | into string)) }
    }
    if not ($role_file | path exists) {
        error make { msg: ("Profile manifest not found: " + ($role_file | into string)) }
    }

    mut result = (open $common_file)
    $result = (merge-profile $result (open-record-if-exists $os_file))
    $result = (merge-profile $result (open $role_file))

    if not ($machine_name | is-empty) {
        let repo_machine = ($PROFILES_ROOT | path join "machines" ($machine_name + ".nuon"))
        $result = (merge-profile $result (open-record-if-exists $repo_machine))
    }

    $result = (merge-profile $result (open-record-if-exists (machine-overlay-path)))
    $result
}

export def profile-forced-features [profile: string machine_name: string] {
    let os_file = ($PROFILES_ROOT | path join "os" ($nu.os-info.name + ".nuon"))
    let repo_machine = ($PROFILES_ROOT | path join "machines" ($machine_name + ".nuon"))
    let os_features = ((open-record-if-exists $os_file).features? | default {})
    let machine_features = ((open-record-if-exists $repo_machine).features? | default {})
    let local_features = ((open-record-if-exists (machine-overlay-path)).features? | default {})
    $os_features | merge $machine_features | merge $local_features
}

export def profile-layers [profile: string machine_name: string] {
    let repo_machine = ($PROFILES_ROOT | path join "machines" ($machine_name + ".nuon"))
    {
        common: ($PROFILES_ROOT | path join "common.nuon" | into string)
        os: ($PROFILES_ROOT | path join "os" ($nu.os-info.name + ".nuon") | into string)
        role: ($PROFILES_ROOT | path join ($profile + ".nuon") | into string)
        machine: (if ($repo_machine | path exists) { $repo_machine | into string } else { "" })
        local: (if ((machine-overlay-path) | path exists) { (machine-overlay-path) | into string } else { "" })
    }
}
