#!/usr/bin/env nu

const MODULE = path self ./modules/toolchains.nu
use $MODULE [toolchain-lock-path load-toolchain-lock toolchain-status write-current-lock apply-toolchain-lock]

def print-status [] {
    print "Toolchain lock"
    print "────────────────────────────────────────────────────────────"
    print ("Lock file: " + (toolchain-lock-path | into string))
    print ""
    for item in (toolchain-status) {
        print ($item.name + "  desired=" + $item.desired + " (" + $item.mode + ")  actual=" + (if ($item.actual | is-empty) { "missing" } else { $item.actual }) + "  [" + $item.status + "]")
    }
}

def main [--status --apply --lock-current] {
    if $lock_current {
        let file = (write-current-lock)
        print ("[save] Exact current toolchain lock -> " + ($file | into string))
        print-status
        return
    }
    if $apply {
        apply-toolchain-lock
        print-status
        return
    }
    print-status
}
