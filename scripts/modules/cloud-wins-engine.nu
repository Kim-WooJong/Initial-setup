# Builds are explicit; previews never install Rust crates or write the checkout.
const OUTPUT = path self ./process-output.nu
use $OUTPUT [output-text]
const ROOT = path self ../..
const SAFETY = path self ./safety.nu
const CORE = path self ./core.nu
use $SAFETY [state-root]
use $CORE [error-message]

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
    let result = (do { ^$exe ...$args } | complete)
    if $result.exit_code != 0 {
        if not ($result.stderr | output-text | is-empty) { print --stderr ($result.stderr | output-text) }
        error make {msg: ("cloudwins failed (exit " + ($result.exit_code | into string) + "). Payload/baseline success is not assumed.")}
    }
    if not ($result.stderr | output-text | is-empty) { print --stderr ($result.stderr | output-text) }
    try { $result.stdout | output-text | from json } catch {|err|
        error make {msg: ("Invalid cloudwins JSON: " + (error-message $err))}
    }
}
