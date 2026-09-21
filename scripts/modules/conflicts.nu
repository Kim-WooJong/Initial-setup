const SUBPROCESS = path self ./subprocess.nu
const CONSOLE = path self ./console.nu
use $SUBPROCESS [run-command]
use $CONSOLE [print-ok print-warn style]
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
        let managed = (run-command "chezmoi" ["--source" ($source | into string) "source-path" ($target | into string)])
        if not $managed.ok or (($managed.stdout | str trim) | is-empty) {
            continue
        }

        let result = (run-command "chezmoi" ["--source" ($source | into string) "--no-pager" "--use-builtin-diff" "diff" ($target | into string)])

        if not $result.ok {
            $conflicts = ($conflicts | append {
                entry: $entry
                target: ($target | into string)
                error: ($result.diagnostic | str trim | default "chezmoi diff failed")
            })
            continue
        }

        let diff = ($result.stdout | str trim)
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
        print-ok "Protected-file conflicts: none"
        return
    }

    print (style "warn" "Protected-file conflicts")
    print "────────────────────────────────────────────────────────────"
    for item in $conflicts {
        print ((style "warn" "  [protected]") + " " + $item.target)
        if not (($item.error? | default "") | is-empty) {
            print ("              " + $item.error)
        }
    }
}
