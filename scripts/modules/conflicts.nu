const PROCESS_OUTPUT = path self ./process-output.nu
use $PROCESS_OUTPUT [output-text]
# Protected-file and three-way conflict helpers.

const CORE_MODULE = path self ./core.nu
const DEFAULT_POLICY = path self ../../defaults/conflict-policy.nuon
use $CORE_MODULE [nu-home]

export def local-policy-path [] {
    (nu-home) | path join ".config" "dotfiles" "conflict-policy.nuon"
}

export def load-conflict-policy [] {
    let defaults = (open $DEFAULT_POLICY)
    let local_file = (local-policy-path)
    let local = (if ($local_file | path exists) { open $local_file } else { {} })

    {
        version: 1
        protected: (
            ($defaults.protected? | default [])
            | append ($local.protected? | default [])
            | uniq
        )
        merge_preferred: (
            ($defaults.merge_preferred? | default [])
            | append ($local.merge_preferred? | default [])
            | uniq
        )
    }
}

export def target-path [entry: string] {
    let trimmed = ($entry | str trim)

    if ($trimmed | is-empty) {
        error make { msg: "Target path cannot be empty." }
    }

    if ($trimmed | str starts-with "~") {
        return ($trimmed | path expand)
    }

    if ($trimmed | str starts-with ".") {
        return ((nu-home) | path join $trimmed | path expand)
    }

    $trimmed | path expand
}

export def is-protected-target [target: path] {
    let expanded = ($target | path expand | into string)
    let policy = (load-conflict-policy)

    $policy.protected
    | any { |entry| ((target-path $entry) | into string) == $expanded }
}

export def protected-conflicts [source: path] {
    let policy = (load-conflict-policy)
    mut conflicts = []

    for entry in $policy.protected {
        let target = (target-path $entry)

        # A missing destination has no local content to protect.
        if not ($target | path exists) {
            continue
        }

        # Policy entries may exist on only some machines. Do not turn an
        # unmanaged local file into a false conflict.
        let managed = (
            do { ^chezmoi --source ($source | into string) source-path ($target | into string) }
            | complete
        )
        if $managed.exit_code != 0 or (($managed.stdout? | default "" | str trim) | is-empty) {
            continue
        }

        let result = (
            do { ^chezmoi --source ($source | into string) diff ($target | into string) }
            | complete
        )

        if $result.exit_code != 0 {
            $conflicts = ($conflicts | append {
                entry: $entry
                target: ($target | into string)
                error: ($result.stderr? | output-text | str trim | default "chezmoi diff failed")
            })
            continue
        }

        let diff = ($result.stdout? | default "" | str trim)
        if not ($diff | is-empty) {
            $conflicts = ($conflicts | append {
                entry: $entry
                target: ($target | into string)
                error: ""
            })
        }
    }

    $conflicts
}

export def print-protected-conflicts [conflicts: list] {
    if ($conflicts | is-empty) {
        print "Protected-file conflicts: none"
        return
    }

    print "Protected-file conflicts"
    print "────────────────────────────────────────────────────────────"
    for item in $conflicts {
        print ("  [protected] " + $item.target)
        if not (($item.error? | default "") | is-empty) {
            print ("              " + $item.error)
        }
    }
}
