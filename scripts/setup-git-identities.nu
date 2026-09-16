#!/usr/bin/env nu

const GIT_IDENTITIES_MODULE = path self ./modules/git-identities.nu

use $GIT_IDENTITIES_MODULE [
    git-identities-manifest-path
    ensure-git-identities-manifest
    apply-git-identities
    check-git-identities
]


def main [
    --init
    --apply
    --check
    --edit
] {
    if $edit {
        ensure-git-identities-manifest | ignore
        let file = (git-identities-manifest-path)

        if (which nvim | is-empty) {
            print ("Edit this file: " + ($file | into string))
        } else {
            ^nvim $file
        }

        if $apply {
            apply-git-identities | ignore
        }

        return
    }

    if $apply {
        apply-git-identities | ignore
        return
    }

    if $init {
        ensure-git-identities-manifest | ignore
        check-git-identities
        return
    }

    if $check {
        check-git-identities
        return
    }

    check-git-identities
}
