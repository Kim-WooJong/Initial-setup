# Local-only control state. Never store this file in the cloud mirror.
const TEXT_CASE = path self ./text-case.nu
use $TEXT_CASE [text-lower]
const CORE = path self ./core.nu
const SAFETY = path self ./safety.nu
use $CORE [machine-context]
use $SAFETY [state-root disjoint-paths]

export def cloud-config-path [] { (state-root) | path join "cloud-wins.nuon" }
export def load-cloud-config [] {
    let file = (cloud-config-path)
    if not ($file | path exists) { return null }
    let config = (open --raw $file | from nuon)
    if ($config.version? | default 0) != 1 or ($config.active? | describe) != "bool" {
        error make {msg: "Invalid cloud-wins control state. Refusing to assume bidirectional mode."}
    }
    for key in ["source" "target"] {
        let value = ($config | get $key)
        if ($value | describe) != "string" or ($value | is-empty) { error make {msg: "Invalid cloud-wins root."} }
    }
    $config
}
export def cloud-mode-active [] {
    let config = (load-cloud-config)
    if $config == null { false } else { $config.active }
}
export def cloud-state-dir [target: path] {
    let expanded = ($target | path expand | into string)
    # Hash the UTF-8 path for a filesystem-safe, per-workspace state directory.
    let identity = if $nu.os-info.name == "windows" { $expanded | text-lower } else { $expanded }
    (state-root) | path join "cloud-wins" ($identity | hash sha256)
}
export def cloud-roots [source: string target: string] {
    if ($source | is-empty) or ($target | is-empty) {
        error make {msg: "Both source and target are required. Configure them with dotcloud configure first."}
    }
    for root in [$source $target] {
        if not ($root | path exists) or ($root | path type) != "dir" {
            error make {msg: ("An existing, non-link directory is required: " + $root)}
        }
    }
    let src = ($source | path expand | into string)
    let dst = ($target | path expand | into string)
    let state = (cloud-state-dir $dst)
    disjoint-paths $src $dst
    disjoint-paths $state $src
    disjoint-paths $state $dst
    # A workspace must be a dedicated source tree, not all of HOME or the state tree.
    disjoint-paths (state-root) $src
    disjoint-paths (state-root) $dst
    {source: $src target: $dst state_dir: ($state | into string)}
}
export def assert-cloud-workspace [context: record] {
    let config = (load-cloud-config)
    if $config == null or not $config.active { return }
    if ($context.data_root | path expand) != ($config.target | path expand) {
        error make {msg: "cloud-wins activation is incomplete or data_root changed. Inspect dotcloud status; do not push."}
    }
    let provider_file = ((state-root) | path join "sync-provider.nuon")
    if ($provider_file | path exists) {
        let provider = (open --raw $provider_file | from nuon)
        if $provider.kind != "directory" {
            error make {msg: "Active cloud-wins requires the directory provider pointed at the local workspace."}
        }
    }
}
