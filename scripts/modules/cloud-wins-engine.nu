# Builds are explicit; previews never install Rust crates or write the checkout.
const ROOT = path self ../..
const SAFETY = path self ./safety.nu
const CORE = path self ./core.nu
const SUBPROCESS = path self ./subprocess.nu
use $SAFETY [state-root]
use $CORE [error-message]
use $SUBPROCESS [run-command command-failure-message]

export def cloud-build-layout [] {
    let source = ($ROOT | path join "tools" "cloudwins")
    let inputs = (["Cargo.toml" "src/main.rs" "src/tests.rs"] | each {|name|
        {path: $name sha256: (open --raw ($source | path join $name) | hash sha256)}
    })
    let id = ($inputs | to json --raw | hash sha256)
    let root = ((state-root) | path join "cache" "cloudwins" $id)
    {root: $root source: $source inputs: $inputs source_hash: $id build_source: ($root | path join "source") target_dir: ($root | path join "target") receipt: ($root | path join "receipt.nuon")}
}

export def cloud-engine [] {
    let layout = (cloud-build-layout)
    if not ($layout.receipt | path exists) {
        error make {msg: "cloudwins is not built for this source revision. Run: nu --no-config-file scripts/cloud-wins-build.nu"}
    }
    let receipt = (open --raw $layout.receipt | from nuon)
    let exe = $receipt.exe
    if ($receipt.source_hash? | default "") != $layout.source_hash or not ($exe | path exists) {
        error make {msg: "cloudwins receipt is stale; rebuild explicitly."}
    }
    if (open --raw $exe | hash sha256) != $receipt.sha256 {
        error make {msg: "cloudwins binary differs from its local receipt; rebuild explicitly."}
    }
    $exe
}

export def engine-json [exe: path args: list] {
    let result = (run-command ($exe | into string) $args)
    if not ($result.stderr | str trim | is-empty) { print --stderr ($result.stderr | str trim --right) }
    if not $result.ok {
        error make {msg: ((command-failure-message "cloudwins" $result) + (char nl) + "Payload/baseline success is not assumed.")}
    }
    try { $result.stdout | from json } catch {|err|
        error make {msg: ("Invalid cloudwins JSON: " + (error-message $err))}
    }
}
