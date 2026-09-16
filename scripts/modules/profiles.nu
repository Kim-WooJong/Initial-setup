# Declarative machine-profile loader.

const PROFILES_ROOT = path self ../../profiles

export def profile-names [] {
    ["workstation" "laptop" "server" "minimal"]
}

export def profile-defaults [profile: string] {
    if not ($profile in (profile-names)) {
        error make {
            msg: (
                "Unknown profile '" + $profile + "'. Use " + ((profile-names) | str join ", ") + "."
            )
        }
    }

    let common_file = ($PROFILES_ROOT | path join "common.nuon")
    let profile_file = ($PROFILES_ROOT | path join ($profile + ".nuon"))

    if not ($common_file | path exists) {
        error make {
            msg: ("Common profile manifest not found: " + ($common_file | into string))
        }
    }

    if not ($profile_file | path exists) {
        error make {
            msg: ("Profile manifest not found: " + ($profile_file | into string))
        }
    }

    let common = (open $common_file)
    let overlay = (open $profile_file)
    let common_features = ($common.features? | default {})
    let overlay_features = ($overlay.features? | default {})
    let merged = ($common | merge $overlay)

    $merged | upsert features ($common_features | merge $overlay_features)
}
