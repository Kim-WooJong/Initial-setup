const CORE_MODULE = path self ./core.nu
const GIT_IDENTITIES_MODULE = path self ./git-identities.nu

use $CORE_MODULE [nu-home]
use $GIT_IDENTITIES_MODULE [active-git-identities]

export def ssh-dir [] {
    (nu-home) | path join ".ssh"
}

def configured-private-keys [] {
    active-git-identities
    | each { |identity| $identity.ssh_key? | default "" }
    | where { |key| not ($key | is-empty) }
    | each { |key| $key | path expand }
}

def conventional-private-keys [] {
    let dir = (ssh-dir)

    if not ($dir | path exists) {
        return []
    }

    ls $dir
    | where type == file
    | where { |item|
        let name = ($item.name | path basename)
        ($name | str starts-with "id_") and not ($name | str ends-with ".pub") and not ($name | str ends-with "-cert")
    }
    | each { |item| $item.name | path expand }
}

export def ssh-private-key-candidates [] {
    (conventional-private-keys)
    | append (configured-private-keys)
    | uniq
}

def public-key-path [private_key: path] {
    (($private_key | into string) + ".pub") | path expand
}

export def check-ssh-keys [] {
    let keys = (ssh-private-key-candidates)

    if ($keys | is-empty) {
        print "[--] No SSH private keys were detected or referenced by Git identities"
        return
    }

    for key in $keys {
        let pub = (public-key-path $key)

        if not ($key | path exists) {
            print ("[WARN] SSH private key missing: " + ($key | into string))
            continue
        }

        if ($pub | path exists) {
            print ("[ok] SSH key pair: " + ($key | path basename))
        } else {
            print ("[WARN] SSH public key missing: " + ($pub | into string))
        }
    }
}

export def generate-missing-public-keys [] {
    if (which ssh-keygen | is-empty) {
        print "[WARN] ssh-keygen is not available; public keys cannot be generated"
        return 0
    }

    let keys = (ssh-private-key-candidates)
    mut generated = 0

    for key in $keys {
        if not ($key | path exists) {
            print ("[WARN] SSH private key missing: " + ($key | into string))
            continue
        }

        let pub = (public-key-path $key)

        if ($pub | path exists) {
            continue
        }

        let result = (do { ^ssh-keygen -y -P "" -f $key } | complete)
        let public_key = ($result.stdout? | default "" | str trim)

        if $result.exit_code == 0 and not ($public_key | is-empty) {
            ($public_key + (char nl)) | save $pub
            print ("[create] SSH public key -> " + ($pub | into string))
            $generated = $generated + 1
        } else {
            print ("[WARN] Could not generate public key non-interactively: " + ($key | into string))
            print "       The private key may be encrypted. Run `ssh-keygen -y -f <private-key>` manually if needed."
        }
    }

    print ("[ok] SSH public keys generated: " + ($generated | into string))
    $generated
}
