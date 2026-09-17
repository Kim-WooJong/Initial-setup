# Desired-state planner for packages, configuration, protected files, and toolchains.

const TOOLS_ROOT = path self ../..
const CORE_MODULE = path self ./core.nu
const CONFLICTS_MODULE = path self ./conflicts.nu
const TOOLCHAINS_MODULE = path self ./toolchains.nu
use $CORE_MODULE [nu-home machine-context]
const PROVIDER_MODULE = path self ./sync-provider.nu
use $PROVIDER_MODULE [load-provider provider-head provider-id load-provider-state]
const VAULT_MODULE = path self ./vault.nu
use $VAULT_MODULE [vault-configured]
use $CONFLICTS_MODULE [protected-conflicts]
use $TOOLCHAINS_MODULE [toolchain-status]

export def plans-root [] {
    (nu-home) | path join ".config" "dotfiles" "plans"
}

def useful-lines [file: path] {
    open --raw $file | lines | each { |line| $line | str trim } | where { |line| not ($line | is-empty) and not ($line | str starts-with "#") }
}

def platform-map [] {
    let file = ($TOOLS_ROOT | path join "packages" ($nu.os-info.name + ".txt"))
    if not ($file | path exists) { return [] }
    useful-lines $file | each { |line|
        let cols = ($line | split row "|")
        { name: ($cols | get 0) command: ($cols | get 1) }
    }
}

def command-present [name: string command: string] {
    if not (which $command | is-empty) { return true }
    if $nu.os-info.name == "linux" and $name == "fd" and not (which fdfind | is-empty) { return true }
    if $nu.os-info.name == "linux" and $name == "bat" and not (which batcat | is-empty) { return true }
    false
}

export def package-status [] {
    let wanted = (useful-lines ($TOOLS_ROOT | path join "packages" "common.txt"))
    let mapping = (platform-map)
    $wanted | each { |name|
        let matches = ($mapping | where name == $name)
        let row = (if ($matches | is-empty) { {name: $name command: ""} } else { $matches | first })
        let command = ($row.command? | default "")
        {
            name: $name
            command: $command
            status: (if ($command | is-empty) { "unmapped" } else if (command-present $name $command) { "ok" } else { "missing" })
        }
    }
}

export def config-status [data_root: path] {
    if (which chezmoi | is-empty) or not ($data_root | path exists) {
        return { available: false lines: [] count: 0 diff_count: 0 verify_ok: false }
    }
    let result = (do { ^chezmoi --source ($data_root | into string) status --path-style relative } | complete)
    let lines = (($result.stdout? | default "") | lines | where { |line| not ($line | str trim | is-empty) })
    let diff_result = (do { ^chezmoi --source ($data_root | into string) diff } | complete)
    let diff_lines = (($diff_result.stdout? | default "") | lines | where { |line| not ($line | str trim | is-empty) })
    let verify_result = (do { ^chezmoi --source ($data_root | into string) verify } | complete)
    {
        available: ($result.exit_code == 0)
        lines: $lines
        count: ($lines | length)
        diff_count: ($diff_lines | length)
        verify_ok: ($verify_result.exit_code == 0)
    }
}

export def build-plan [direction: string = "none"] {
    if not ($direction in ["none" "pull" "push"]) {
        error make { msg: "Plan direction must be one of: none, pull, push." }
    }
    let context = (machine-context)
    let data_root = ($context.data_root | path expand)
    let packages = (if ($context.features.cli_tools? | default true) { package-status } else { package-status | where name == "rclone" })
    let config = (config-status $data_root)
    let protected = (if $config.available { protected-conflicts $data_root } else { [] })
    let all_toolchains = (toolchain-status)
    let toolchains = ($all_toolchains | where { |item|
        ($item.name == "nushell") or ($item.name == "rust" and ($context.features.rust? | default false)) or ($item.name == "julia" and ($context.features.julia? | default false))
    })
    let transport = (try {
        let provider = (load-provider)
        let head = (provider-head $provider)
        let state = (load-provider-state $provider)
        {available: true provider_id: (provider-id $provider) kind: $provider.kind revision: $head.revision tree_hash: $head.tree_hash baseline_missing: ($state == null) remote_changed: ($state != null and ($state.revision? | default "") != $head.revision)}
    } catch { {available: false provider_id: "" kind: "unknown" revision: "" tree_hash: "" baseline_missing: true remote_changed: true} })
    let project_version = (open --raw ($TOOLS_ROOT | path join "VERSION") | str trim)
    {
        schema_version: 1
        app_version: $project_version
        created_at: (date now)
        machine: ($context.machine.name? | default "unknown")
        profile: ($context.machine.profile? | default "unknown")
        direction: $direction
        transport: $transport
        encrypted_vault_configured: (vault-configured)
        packages: $packages
        missing_packages: ($packages | where status == "missing")
        config: $config
        protected_conflicts: $protected
        toolchains: $toolchains
        toolchain_drift: ($toolchains | where status != "ok")
    }
}

export def save-plan [plan: record] {
    let root = (plans-root)
    mkdir $root
    let stamp = (date now | format date "%Y%m%d-%H%M%S")
    let file = ($root | path join ($stamp + ".nuon"))
    $plan | to nuon | save --force $file
    $plan | to nuon | save --force ($root | path join "latest.nuon")
    $file
}

export def resolve-plan-path [requested: string] {
    if not ($requested | is-empty) { return ($requested | path expand) }
    let latest = (plans-root | path join "latest.nuon")
    if not ($latest | path exists) { error make { msg: "No saved plan exists. Run dotplan first." } }
    $latest
}
