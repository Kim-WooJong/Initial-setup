#!/usr/bin/env nu
# Pure bundle boundary tests. No native stores, privileged helpers or real keys.
source ./modules/wireguard-sync.nu

def must-reject [action: closure] {
    let rejected = (try { do $action | ignore; false } catch { true })
    if not $rejected { error make {msg: "Expected invalid WireGuard bundle to be rejected."} }
}

def main [] {
    let stage = ($env.TMPDIR? | default "/tmp" | path join ("wireguard-test-" + (random uuid)))
    mkdir $stage
    let file = ($stage | path join "fixture.json")
    let policy = {device_id: "test-device" tunnels: ["wg0" "wg1"]}
    let first = {name: "wg0" config: "[Interface]\n# dummy fixture 0\n"}
    let second = {name: "wg1" config: "[Interface]\n# dummy fixture 1\n"}
    try {
        {schema_version: 1 device_id: "test-device" tunnels: [$second $first]} | to json | save $file
        let canonical = (canonical-bundle $file $policy --complete)
        if $canonical.tunnels.0.name != "wg0" { error make {msg: "Bundle ordering must be deterministic."} }
        let expected = (bundle-hash $canonical)
        {schema_version: 1 device_id: "test-device" tunnels: [$first $second]} | to json | save --force $file
        if (bundle-hash (canonical-bundle $file $policy --complete)) != $expected { error make {msg: "JSON ordering changed the content fingerprint."} }
        {schema_version: 1 device_id: "other-device" tunnels: [$first $second]} | to json | save --force $file
        must-reject { canonical-bundle $file $policy --complete }
        {schema_version: 1 device_id: "test-device" tunnels: [$first $first]} | to json | save --force $file
        must-reject { canonical-bundle $file $policy }
        {schema_version: 1 device_id: "test-device" tunnels: [$first]} | to json | save --force $file
        canonical-bundle $file $policy | ignore
        must-reject { canonical-bundle $file $policy --complete }
        {schema_version: 1 device_id: "test-device" tunnels: []} | to json | save --force $file
        canonical-bundle $file $policy | ignore
        must-reject { canonical-bundle $file $policy --complete }
        rm --recursive $stage
        print "WireGuard bundle boundary tests passed."
    } catch {
        if ($stage | path exists) { rm --recursive $stage }
        error make {msg: "WireGuard bundle boundary test failed."}
    }
}
