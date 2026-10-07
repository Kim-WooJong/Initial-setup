#!/usr/bin/env nu
# Narrow manual diagnostic/operation entrypoint. Enrollment is explicit and
# machine-local; never print tunnel content or private keys.
const CORE = path self ./modules/core.nu
const SAFETY = path self ./modules/safety.nu
const WG = path self ./modules/wireguard-sync.nu
use $CORE [machine-context]
use $SAFETY [state-root operation-lock lock-release]
use $WG [capture-wireguard prepare-wireguard-restore commit-prepared-wireguard discard-prepared-wireguard wireguard-local-hash]

def main [--capture --restore --check] {
    if (($capture | into int) + ($restore | into int) + ($check | into int)) > 1 {
        error make {msg: "Use only one of --capture, --restore, or --check."}
    }
    let config = ((state-root) | path join "wireguard.nuon")
    if not $capture and not $restore and not $check {
        print {configured: ($config | path exists) policy: $config guide: "WIREGUARD-CONFIG-SYNC.md"}
        return
    }
    let lock = (operation-lock)
    let result = (try {
        let root = ((machine-context).data_root | path expand)
        if $capture {
            capture-wireguard $root | ignore
            print "WireGuard capture completed. Use dotpush to publish."
        } else if $restore {
            let plan = (prepare-wireguard-restore $root)
            try { commit-prepared-wireguard $plan | ignore } catch {|err|
                discard-prepared-wireguard $plan
                error make {msg: $err.msg}
            }
            discard-prepared-wireguard $plan
            print "WireGuard restore completed; no tunnel was activated."
        } else {
            let hash = (wireguard-local-hash)
            print (if $hash == "DISABLED" { "WireGuard synchronization is disabled." } else { "WireGuard capture access verified; no configuration content displayed." })
        }
        null
    } catch {|err| $err })
    lock-release $lock
    if $result != null { error make {msg: $result.msg} }
}
