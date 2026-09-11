#!/usr/bin/env nu

def machine-context [] {
    let file = ($nu.home-path | path join ".config" "dotfiles" "config.nuon")

    if ($file | path exists) {
        open $file
    } else {
        {
            machine: {
                name: "unknown"
            }
            maintenance: {
                log_keep_lines: 2000
            }
        }
    }
}

def main [
    --level: string = "INFO"
    --message: string
] {
    let context = (machine-context)
    let log_dir = ($nu.home-path | path join ".config" "dotfiles" "logs")
    let log_file = ($log_dir | path join "sync.log")

    mkdir $log_dir

    let timestamp = (date now | format date "%Y-%m-%d %H:%M:%S %z")
    let machine = ($context.machine.name? | default "unknown")
    let line = ($timestamp + " [" + $level + "] [" + $machine + "] " + $message)

    ($line + (char nl)) | save --append $log_file

    let keep = ($context.maintenance.log_keep_lines? | default 2000)

    if $keep > 0 {
        let lines = (open --raw $log_file | lines)
        let count = ($lines | length)

        if $count > $keep {
            let start = ($count - $keep)

            (
                $lines
                | skip $start
                | str join (char nl)
            )
            | save --force $log_file
        }
    }
}
