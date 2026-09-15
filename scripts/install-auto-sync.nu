#!/usr/bin/env nu

def nu-home [] {
    let home_path = ($nu | get --optional home-path)

    if $home_path != null {
        return $home_path
    }

    let home_dir = ($nu | get --optional home-dir)

    if $home_dir != null {
        return $home_dir
    }

    error make {
        msg: "Unable to determine the Nushell home directory."
    }
}

def machine-context [] {
    let file = (
        (nu-home)
        | path join ".config" "dotfiles" "config.nuon"
    )

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

def vbs-literal [value: string] {
    let escaped = ($value | str replace --all '"' '""')
    ('"' + $escaped + '"')
}

def windows-wscript [] {
    let system_root = ($env.SystemRoot? | default 'C:\Windows')
    let candidate = ($system_root | path join "System32" "wscript.exe")

    if ($candidate | path exists) {
        return ($candidate | path expand)
    }

    let rows = (which wscript.exe)

    if not ($rows | is-empty) {
        return ($rows | get 0.path | path expand)
    }

    error make {
        msg: "wscript.exe is required for hidden Windows auto-sync."
    }
}

def install-windows [
    nu_exe: path
    sync_script: path
    interval: int
] {
    let launcher_dir = ((nu-home) | path join ".config" "dotfiles" "scheduler")
    let launcher = ($launcher_dir | path join "auto-sync-hidden.vbs")

    mkdir $launcher_dir

    let nu_literal = (vbs-literal ($nu_exe | into string))
    let script_literal = (vbs-literal ($sync_script | into string))

    [
        "Option Explicit"
        ("Dim nuPath: nuPath = " + $nu_literal)
        ("Dim syncScript: syncScript = " + $script_literal)
        "Dim shell: Set shell = CreateObject(\"WScript.Shell\")"
        "Dim commandLine"
        "commandLine = Chr(34) & nuPath & Chr(34) & \" \" & Chr(34) & syncScript & Chr(34)"
        "Dim exitCode"
        "exitCode = shell.Run(commandLine, 0, True)"
        "WScript.Quit exitCode"
        ""
    ]
    | str join (char nl)
    | save --force $launcher

    let wscript = (windows-wscript)
    let command = ('"' + ($wscript | into string) + '" //B //Nologo "' + ($launcher | into string) + '"')

    let args = [
        "/Create"
        "/F"
        "/SC"
        "MINUTE"
        "/MO"
        ($interval | into string)
        "/TN"
        "DotfilesAutoSync"
        "/TR"
        $command
    ]

    run-program "Install hidden Windows dotfiles auto-sync task" "schtasks.exe" $args

    print ("[ok] Hidden launcher -> " + ($launcher | into string))
    print "[ok] DotfilesAutoSync runs without a terminal window."
}

def install-linux [
    nu_exe: path
    sync_script: path
    interval: int
] {
    let unit_dir = (
        (nu-home)
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
    | str join (char nl)
    | save --force $service

    [
        "[Unit]"
        "Description=Run dotfiles synchronization periodically"
        ""
        "[Timer]"
        "OnBootSec=1min"
        (
            "OnUnitActiveSec="
            + ($interval | into string)
            + "min"
        )
        "Persistent=true"
        ""
        "[Install]"
        "WantedBy=timers.target"
        ""
    ]
    | str join (char nl)
    | save --force $timer

    let reload_args = [
        "--user"
        "daemon-reload"
    ]

    run-program "Reload systemd user units" "systemctl" $reload_args

    let enable_args = [
        "--user"
        "enable"
        "--now"
        "dotfiles-auto-sync.timer"
    ]

    run-program "Enable dotfiles auto-sync timer" "systemctl" $enable_args
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
    interval: int
] {
    let launch_dir = (
        (nu-home)
        | path join "Library" "LaunchAgents"
    )

    mkdir $launch_dir

    let plist = (
        $launch_dir
        | path join "com.initial-setup.dotfiles-auto-sync.plist"
    )

    let seconds = (
        $interval
        * 60
    )

    let nu_xml = (xml-escape ($nu_exe | into string))
    let script_xml = (xml-escape ($sync_script | into string))

    [
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"'
        '  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        '<plist version="1.0">'
        '<dict>'
        '  <key>Label</key>'
        '  <string>com.initial-setup.dotfiles-auto-sync</string>'
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
        (
            "  <integer>"
            + ($seconds | into string)
            + "</integer>"
        )
        '  <key>RunAtLoad</key>'
        '  <true/>'
        '</dict>'
        '</plist>'
        ''
    ]
    | str join (char nl)
    | save --force $plist

    let unload_args = [
        "unload"
        ($plist | into string)
    ]

    ^launchctl ...$unload_args
    | ignore

    let load_args = [
        "load"
        ($plist | into string)
    ]

    run-program "Load macOS dotfiles LaunchAgent" "launchctl" $load_args
}

def main [] {
    let context = (
        machine-context
    )

    if not $context.sync.enabled {
        print "[skip] Automatic synchronization is disabled."
        return
    }

    let interval = (
        $context.sync.interval_minutes
    )

    if $interval < 1 {
        error make {
            msg: "sync.interval_minutes must be at least 1."
        }
    }

    let tools_root = (
        $context.tools_root
        | path expand
    )

    let sync_script = (
        $tools_root
        | path join "scripts" "auto-sync.nu"
    )

    let nu_exe = (
        $nu.current-exe
        | path expand
    )

    match $nu.os-info.name {
        "windows" => {
            install-windows $nu_exe $sync_script $interval
        }

        "linux" => {
            install-linux $nu_exe $sync_script $interval
        }

        "macos" => {
            install-macos $nu_exe $sync_script $interval
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
