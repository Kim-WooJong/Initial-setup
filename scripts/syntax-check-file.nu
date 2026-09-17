#!/usr/bin/env nu
# Standalone parser worker. The target is an argv value, never interpolated into
# a nu --commands string. No project module imports and no target evaluation.
def main [file: path --as-module] {
    let valid = if $as_module {
        nu-check --debug --as-module $file
    } else {
        nu-check --debug $file
    }
    if not $valid { exit 1 }
}
