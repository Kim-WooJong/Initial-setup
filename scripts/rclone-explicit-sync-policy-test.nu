#!/usr/bin/env nu
const ROOT = path self ..

def fail [message: string] { error make {msg: $message} }

def main [] {
    let facade = (open --raw ($ROOT | path join "scripts" "modules" "dotfiles.nu"))
    let transport = (open --raw ($ROOT | path join "scripts" "sync-transport-main.nu"))
    let provider = (open --raw ($ROOT | path join "scripts" "modules" "sync-provider.nu"))
    let explicit = (open --raw ($ROOT | path join "scripts" "rclone-sync.nu"))

    for token in ["export def dotrpush" "export def dotrpull" "rclone-sync.nu"] {
        if not ($facade | str contains $token) { fail ("Missing rclone-only facade contract: " + $token) }
    }
    for token in ["INITIAL_SETUP_PROVIDER_OVERRIDE_REMOTE" "INITIAL_SETUP_PROVIDER_STATE_SCOPE"] {
        if not ($provider | str contains $token) { fail ("Missing provider override isolation: " + $token) }
    }
    for token in ["INITIAL_SETUP_TRANSPORT_ONLY" "INITIAL_SETUP_SUPPRESS_GLOBAL_SYNC_STATE" "if $transport_only" "not $suppress_global_state"] {
        if not ($transport | str contains $token) { fail ("Missing transport-only isolation contract: " + $token) }
    }
    for token in ["rclone-sync.nuon" "--save-remote" "INITIAL_SETUP_TRANSPORT_ONLY" "INITIAL_SETUP_SUPPRESS_GLOBAL_SYNC_STATE"] {
        if not ($explicit | str contains $token) { fail ("Missing explicit rclone command contract: " + $token) }
    }
    if ($explicit | str contains "sync-provider.nuon") and not ($explicit | str contains "load-provider") {
        fail "rclone-only command must not rewrite the normal provider configuration."
    }
    print "[pass] Explicit rclone push/pull remains isolated from the normal provider and global sync baseline."
}
