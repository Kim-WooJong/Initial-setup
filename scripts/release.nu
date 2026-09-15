#!/usr/bin/env nu

const TOOLS_ROOT = path self ..

def version-file [] {
    $TOOLS_ROOT | path join "VERSION"
}

def app-version [] {
    open (version-file) --raw | decode utf-8 | str trim
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
    let output = (^git -C $TOOLS_ROOT ...$args | str trim)
    let exit_code = ($env.LAST_EXIT_CODE | default 1)
    if $exit_code != 0 { "" } else { $output }
}

def git-run [label: string args: list] {
    print ("[git] " + $label)
    ^git -C $TOOLS_ROOT ...$args
    let exit_code = ($env.LAST_EXIT_CODE | default 0)

    if $exit_code != 0 {
        error make { msg: ($label + " failed with exit code " + ($exit_code | into string)) }
    }
}

def prepend-changelog [version: string] {
    let file = ($TOOLS_ROOT | path join "CHANGELOG.md")
    if not ($file | path exists) { return }

    let text = (open $file --raw | decode utf-8)
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
    if (which git | is-empty) {
        error make { msg: "git is required." }
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
    prepend-changelog $next

    git-run ("Stage release " + $next) ["add" "VERSION" "CHANGELOG.md"]
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
