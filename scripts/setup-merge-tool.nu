#!/usr/bin/env nu

# Configure Neovim diff mode as chezmoi's three-way merge tool without
# overwriting a custom merge configuration. If chezmoi uses a TOML config
# template, update the source template and regenerate the config instead of
# editing only the generated file.

const CORE_MODULE = path self ./modules/core.nu
use $CORE_MODULE [nu-home machine-context]

const BEGIN = "# BEGIN Initial-setup managed merge tool"
const END = "# END Initial-setup managed merge tool"

def data-root [] {
    let context = (machine-context)
    $context.data_root | path expand
}

def template-value [root: path expression: string] {
    let result = (do { ^chezmoi --source ($root | into string) execute-template $expression } | complete)
    let output = ($result.stdout? | default "" | str trim)
    if $result.exit_code == 0 and not ($output | is-empty) { $output } else { "" }
}

def config-path [root: path] {
    if not (which chezmoi | is-empty) {
        let output = (template-value $root "{{ .chezmoi.configFile }}")
        if not ($output | is-empty) { return ($output | path expand) }
    }
    (nu-home) | path join ".config" "chezmoi" "chezmoi.toml"
}

def config-template-path [root: path] {
    if (which chezmoi | is-empty) { return null }
    let source_dir = (template-value $root "{{ .chezmoi.sourceDir }}")
    if ($source_dir | is-empty) { return null }
    let candidate = (($source_dir | path expand) | path join ".chezmoi.toml.tmpl")
    if ($candidate | path exists) { $candidate } else { null }
}

def managed-block [] {
    [
        $BEGIN
        "[merge]"
        'command = "nvim"'
        "args = ["
        '    "-d",'
        '    "{{ .Destination }}",'
        '    "{{ .Source }}",'
        '    "{{ .Target }}"'
        "]"
        $END
    ] | str join (char nl)
}

def managed-template-block [] {
    [
        $BEGIN
        "[merge]"
        'command = "nvim"'
        "args = ["
        '    "-d",'
        '    {{ printf "%q" "{{ .Destination }}" }},'
        '    {{ printf "%q" "{{ .Source }}" }},'
        '    {{ printf "%q" "{{ .Target }}" }},'
        "]"
        $END
    ] | str join (char nl)
}

def strip-managed [text: string] {
    if not ($text | str contains $BEGIN) { return $text }
    let before = ($text | split row $BEGIN | first)
    let after_parts = ($text | split row $END)
    let after = (if ($after_parts | length) > 1 { $after_parts | last } else { "" })
    ($before | str trim --right) + (char nl) + ($after | str trim --left)
}

def write-managed [file: path block: string] {
    let current = (if ($file | path exists) { open --raw $file } else { "" })
    let base = (strip-managed $current | str trim --right)
    let custom_merge = ($base | lines | any { |line| ($line | str trim) == "[merge]" })

    if $custom_merge {
        print ("[keep] Existing custom chezmoi [merge] configuration: " + ($file | into string))
        return false
    }

    mkdir ($file | path dirname)
    let output = (if ($base | is-empty) { $block + (char nl) } else { $base + (char nl) + (char nl) + $block + (char nl) })
    $output | save --force $file
    true
}

def main [--check --force] {
    let root = (data-root)
    let file = (config-path $root)
    let template = (config-template-path $root)
    let ext = ($file | path parse | get extension | default "")

    if $ext != "toml" {
        print ("[warn] Automatic merge-tool configuration preserves non-TOML chezmoi configs unchanged: " + ($file | into string))
        print "[info] Configure merge.command=nvim and merge.args=-d, Destination, Source, Target manually."
        return
    }

    let template_text = (if $template == null { "" } else { open --raw $template })
    let config_text = (if ($file | path exists) { open --raw $file } else { "" })
    let managed_template = (not ($template_text | is-empty) and ($template_text | str contains $BEGIN))
    let managed_config = ($config_text | str contains $BEGIN)

    if $check {
        print ("Chezmoi config   : " + ($file | into string))
        print ("Config template  : " + (if $template == null { "none" } else { $template | into string }))
        print ("Neovim           : " + (if (which nvim | is-empty) { "missing" } else { "available" }))
        print ("Managed template : " + ($managed_template | into string))
        print ("Managed config   : " + ($managed_config | into string))
        return
    }

    if (which nvim | is-empty) { print "[skip] Neovim is not installed."; return }

    if $template != null {
        let changed = (write-managed $template (managed-template-block))
        if $changed {
            print ("[ok] Neovim merge configuration added to chezmoi config template: " + ($template | into string))
            print "[init] Regenerating chezmoi config from its template..."
            ^chezmoi --source ($root | into string) init
            if ($env.LAST_EXIT_CODE | default 0) != 0 {
                error make { msg: "chezmoi init failed while regenerating the configuration file." }
            }
        }
        return
    }

    if $force {
        print "[info] --force never replaces an unmanaged custom [merge] section; it only refreshes Initial-setup's managed block."
    }

    let changed = (write-managed $file (managed-block))
    if $changed { print ("[ok] Neovim three-way merge configured in " + ($file | into string)) }
}
