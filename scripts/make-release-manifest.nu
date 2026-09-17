#!/usr/bin/env nu
const ROOT = path self ..
const MODULE = path self ./modules/upgrade.nu
use $MODULE [write-release-manifest]
def main [] {
    let digest = (write-release-manifest $ROOT)
    print ("RELEASE-MANIFEST.json SHA-256: " + $digest)
}
