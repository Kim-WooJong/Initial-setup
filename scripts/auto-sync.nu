#!/usr/bin/env nu
# Idle cycles use a compatible runtime; actual push/pull verifies latest stable.
const RUNTIME = path self ./modules/nu-runtime.nu
const IMPL = path self ./auto-sync-main.nu
use $RUNTIME [runtime-execute]
def main [] {
    runtime-execute $IMPL [] --background
}
