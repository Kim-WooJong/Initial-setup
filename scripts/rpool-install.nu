#!/usr/bin/env nu
# Install or update the RPool binary from its public GitHub releases.
const INSTALL = path self ./modules/rpool-install.nu
use $INSTALL [install-rpool rpool-install-check]

def main [--version: string = "" --check] {
    if $check {
        let r = (rpool-install-check $version)
        print $r
        if not $r.up_to_date { exit 1 }
        return
    }
    install-rpool $version | ignore
}
