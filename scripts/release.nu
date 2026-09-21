#!/usr/bin/env nu

const TOOLS_ROOT = path self ..
const SUBPROCESS = path self ./modules/subprocess.nu
const INSTALL_UTILS = path self ./modules/install-utils.nu
use $SUBPROCESS [run-command command-failure-message]
use $INSTALL_UTILS [probe-tool]

def version-file [] {
    $TOOLS_ROOT | path join "VERSION"
}

def app-version [] {
    open (version-file) --raw | into string | str trim
}

def parse-version [value: string] {
    let parts = ($value | split row ".")
    if ($parts | length) != 3 {
        error make { msg: ("VERSION must be MAJOR.MINOR.PATCH, got: " + $value) }
    }

    {
        major: ($parts | get 0 | into int)
        minor: ($parts | get 1 | into int)
        patch: ($parts | get 2 | into int)
    }
}

def bump-version [current: string mode: string requested: string] {
    if $mode == "set" {
        parse-version $requested | ignore
        return $requested
    }

    let value = (parse-version $current)

    if $mode == "patch" {
        return (($value.major | into string) + "." + ($value.minor | into string) + "." + (($value.patch + 1) | into string))
    }

    if $mode == "minor" {
        return (($value.major | into string) + "." + (($value.minor + 1) | into string) + ".0")
    }

    if $mode == "major" {
        return ((($value.major + 1) | into string) + ".0.0")
    }

    error make { msg: "Use patch, minor, major, or set." }
}

def git-output [args: list] {
    let git = (probe-tool "git" ["--version"])
    if not $git.healthy { error make {msg: "git is unavailable or unhealthy."} }
    let result = (run-command $git.path (["-C" ($TOOLS_ROOT | into string)] | append $args))
    if not $result.ok { error make {msg: (command-failure-message "git" $result)} }
    $result.stdout | str trim
}

def git-run [label: string args: list] {
    let git = (probe-tool "git" ["--version"])
    if not $git.healthy { error make {msg: "git is unavailable or unhealthy."} }
    print ("[git] " + $label)
    let result = (run-command $git.path (["-C" ($TOOLS_ROOT | into string)] | append $args) --live)
    if not $result.ok { error make {msg: (command-failure-message $label $result)} }
}

def run-gate [label: string script: path args: list = []] {
    let result = (run-command ($nu.current-exe | into string) (["--no-config-file" ($script | into string)] | append $args) --live)
    if not $result.ok { error make {msg: (command-failure-message $label $result)} }
}

def update-readme-version [version: string] {
    let file = ($TOOLS_ROOT | path join "README.md")

    if not ($file | path exists) {
        return
    }

    let text = (open --raw $file | into string)
    let updated = (
        $text
        | str replace --regex '^# Initial-setup v[0-9]+\.[0-9]+\.[0-9]+' ("# Initial-setup v" + $version)
    )

    $updated | save --force $file
}

def validate-release [] {
    run-gate "Project validation" ($TOOLS_ROOT | path join "scripts" "validate-project.nu")
    run-gate "Sandbox self-test" ($TOOLS_ROOT | path join "scripts" "self-test.nu") ["--sandbox"]
    run-gate "Cloud-wins Rust release gate" ($TOOLS_ROOT | path join "scripts" "cloud-wins-build.nu") ["--test"]
    run-gate "Cloud-wins integration release gate" ($TOOLS_ROOT | path join "scripts" "cloud-wins-test.nu") ["--require-engine"]
    run-gate "Security/integration release gate" ($TOOLS_ROOT | path join "scripts" "security-self-test.nu") ["--require-age" "--require-rclone"]
}

def prepend-changelog [version: string] {
    let file = ($TOOLS_ROOT | path join "CHANGELOG.md")
    if not ($file | path exists) { return }

    let text = (open $file --raw | into string)
    let heading = ("## " + $version)
    if ($text | str contains $heading) { return }

    let body = (
        if ($text | str starts-with "# Changelog") {
            $text | str replace --regex '^# Changelog\s*' ''
        } else {
            $text
        }
    )

    let entry = ("# Changelog" + (char nl) + (char nl) + $heading + (char nl) + (char nl) + "- Release v" + $version + "." + (char nl) + (char nl))
    ($entry + $body) | save --force $file
}

def main [
    mode: string
    requested: string = ""
    --push
    --no-tag
] {
    let git_probe = (probe-tool "git" ["--version"])
    if not $git_probe.healthy {
        error make { msg: "git is required and must pass `git --version`." }
    }

    if not (($TOOLS_ROOT | path join ".git") | path exists) {
        error make { msg: "Initial-setup is not a Git checkout." }
    }

    if $mode == "set" and ($requested | is-empty) {
        error make { msg: "Usage: dotrelease set <version>" }
    }

    let dirty = (git-output ["status" "--porcelain"])
    if not ($dirty | is-empty) {
        error make { msg: "Working tree is not clean. Commit or stash existing changes before creating a release." }
    }

    let current = (app-version)
    let next = (bump-version $current $mode $requested)
    let tag = ("v" + $next)

    if not $no_tag {
        let existing = (git-output ["tag" "--list" $tag])
        if not ($existing | is-empty) {
            error make { msg: ("Git tag already exists: " + $tag) }
        }
    }

    ($next + (char nl)) | save --force (version-file)
    update-readme-version $next
    let cargo_file = ($TOOLS_ROOT | path join "tools" "cloudwins" "Cargo.toml")
    let cargo_text = (open --raw $cargo_file)
    ($cargo_text | str replace --regex '(?m)^version = "[0-9]+\.[0-9]+\.[0-9]+"$' ('version = "' + $next + '"')) | save --force $cargo_file
    prepend-changelog $next
    run-gate "Release manifest generation" ($TOOLS_ROOT | path join "scripts" "make-release-manifest.nu")
    validate-release

    git-run ("Stage release " + $next) ["add" "VERSION" "README.md" "CHANGELOG.md" "RELEASE-MANIFEST.json" "tools/cloudwins/Cargo.toml"]
    git-run ("Commit release " + $next) ["commit" "-m" ("Release v" + $next)]

    if not $no_tag {
        git-run ("Create tag " + $tag) ["tag" "-a" $tag "-m" ("Release " + $tag)]
    }

    if $push {
        git-run "Push current branch" ["push"]
        if not $no_tag {
            git-run ("Push " + $tag) ["push" "origin" $tag]
        }
    }

    print ""
    print ("[ok] Released v" + $next)

    if not $push {
        print "[info] Nothing was pushed to a remote. Use --push when remote publication is intended."
    }
}
