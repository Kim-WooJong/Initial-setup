#!/usr/bin/env nu

def main [mode: string] {
    match $mode {
        "ok" => { print "fixture-ok" }
        "fail" => { print "fixture-stdout"; print --stderr "fixture-stderr"; exit 23 }
        _ => { print --stderr "unknown fixture mode"; exit 2 }
    }
}
