#!/usr/bin/env nu

# ============================================================
# Install 1-minute conflict-safe bidirectional dotfiles sync.
#
# Windows: Task Scheduler
# Linux:   systemd user timer
# macOS:   LaunchAgent
# ============================================================

def machine-context [] {
    let file = (
        $nu.home-path
        | path join ".config" "dotfiles" "config.nuon"
    )

    if not ($file | path exists) {
        error make {
            msg: (
                "Machine config not found: "
                + ($file | into string)
            )
        }
    }

    open $file
}

def run-program [
    label: string
    program: string
    args: list
] {
    print (
        "[run] "
        + $label
    )

    print ""

    ^$program ...$args

    let exit_code = (
        $env.LAST_EXIT_CODE
        | default 0
    )

    if $exit_code != 0 {
        error make {
            msg: (
                "Command failed with exit code "
                + ($exit_code | into string)
                + ": "
                + $label
            )
        }
    }
}

def install-windows [
    nu_exe: path
    sync_script: path
] {
    if (which schtasks.exe | is-empty) {
        error make {
            msg: "schtasks.exe is required on Windows."
        }
    }

    let command = (
        '"'
        + ($nu_exe | into string)
        + '" "'
        + ($sync_script | into string)
        + '"'
    )

    let args = [
        "/Create"
        "/F"
        "/SC"
        "MINUTE"
        "/MO"
        "1"
        "/TN"
        "DotfilesAutoSync"
        "/TR"
        $command
    ]

    run-program
        "Install Windows dotfiles auto-sync task"
        "schtasks.exe"
        $args
}

def install-linux [
    nu_exe: path
    sync_script: path
] {
    if (which systemctl | is-empty) {
        error make {
            msg: "systemctl is required for Linux auto-sync."
        }
    }

    let unit_dir = (
        $nu.home-path
        | path join ".config" "systemd" "user"
    )

    mkdir $unit_dir

    let service = (
        $unit_dir
        | path join "dotfiles-auto-sync.service"
    )

    let timer = (
        $unit_dir
        | path join "dotfiles-auto-sync.timer"
    )

    (
        [
            "[Unit]"
            "Description=Conflict-safe bidirectional dotfiles sync"
            ""
            "[Service]"
            "Type=oneshot"
            (
                'ExecStart="'
                + ($nu_exe | into string)
                + '" "'
                + ($sync_script | into string)
                + '"'
            )
            ""
        ]
        | flatten
        | str join (char nl)
    )
    | save --force $service

    (
        [
            "[Unit]"
            "Description=Run dotfiles synchronization every minute"
            ""
            "[Timer]"
            "OnBootSec=1min"
            "OnUnitActiveSec=1min"
            "Persistent=true"
            ""
            "[Install]"
            "WantedBy=timers.target"
            ""
        ]
        | str join (char nl)
    )
    | save --force $timer

    let reload_args = [
        "--user"
        "daemon-reload"
    ]

    run-program
        "Reload systemd user units"
        "systemctl"
        $reload_args

    let enable_args = [
        "--user"
        "enable"
        "--now"
        "dotfiles-auto-sync.timer"
    ]

    run-program
        "Enable dotfiles auto-sync timer"
        "systemctl"
        $enable_args
}

def xml-escape [value: string] {
    $value
    | str replace --all '&' '&amp;'
    | str replace --all '<' '&lt;'
    | str replace --all '>' '&gt;'
}

def install-macos [
    nu_exe: path
    sync_script: path
] {
    if (which launchctl | is-empty) {
        error make {
            msg: "launchctl is required on macOS."
        }
    }

    let launch_dir = (
        $nu.home-path
        | path join "Library" "LaunchAgents"
    )

    mkdir $launch_dir

    let plist = (
        $launch_dir
        | path join "com.wunjo.dotfiles-auto-sync.plist"
    )

    let nu_xml = (
        $nu_exe
        | into string
        | xml-escape
    )

    let script_xml = (
        $sync_script
        | into string
        | xml-escape
    )

    (
        [
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"'
            '  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
            '<plist version="1.0">'
            '<dict>'
            '  <key>Label</key>'
            '  <string>com.wunjo.dotfiles-auto-sync</string>'
            '  <key>ProgramArguments</key>'
            '  <array>'
            (
                "    <string>"
                + $nu_xml
                + "</string>"
            )
            (
                "    <string>"
                + $script_xml
                + "</string>"
            )
            '  </array>'
            '  <key>StartInterval</key>'
            '  <integer>60</integer>'
            '  <key>RunAtLoad</key>'
            '  <true/>'
            '</dict>'
            '</plist>'
            ''
        ]
        | flatten
        | str join (char nl)
    )
    | save --force $plist

    let unload_args = [
        "unload"
        ($plist | into string)
    ]

    ^launchctl ...$unload_args

    let unload_exit_code = (
        $env.LAST_EXIT_CODE
        | default 0
    )

    if $unload_exit_code != 0 {
        print "[info] Existing LaunchAgent was not loaded"
    }

    let load_args = [
        "load"
        ($plist | into string)
    ]

    run-program
        "Load macOS dotfiles LaunchAgent"
        "launchctl"
        $load_args
}

def main [] {
    let context = (
        machine-context
    )

    let tools_root = (
        $context.tools_root
        | path expand
    )

    let sync_script = (
        $tools_root
        | path join "scripts" "auto-sync.nu"
    )

    if not ($sync_script | path exists) {
        error make {
            msg: (
                "auto-sync.nu not found: "
                + ($sync_script | into string)
            )
        }
    }

    let nu_exe = (
        $nu.current-exe
        | path expand
    )

    match $nu.os-info.name {
        "windows" => {
            install-windows
                $nu_exe
                $sync_script
        }

        "linux" => {
            install-linux
                $nu_exe
                $sync_script
        }

        "macos" => {
            install-macos
                $nu_exe
                $sync_script
        }

        _ => {
            error make {
                msg: (
                    "Unsupported OS: "
                    + $nu.os-info.name
                )
            }
        }
    }
}
