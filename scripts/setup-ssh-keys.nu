#!/usr/bin/env nu

const SSH_KEYS_MODULE = path self ./modules/ssh-keys.nu

use $SSH_KEYS_MODULE [check-ssh-keys generate-missing-public-keys]

def main [
    --check
    --generate
] {
    if $generate {
        generate-missing-public-keys | ignore
        check-ssh-keys
        return
    }

    check-ssh-keys
}
