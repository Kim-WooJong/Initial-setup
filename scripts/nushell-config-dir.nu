const SUBPROCESS = path self ./modules/subprocess.nu
use $SUBPROCESS [run-command]

def nu-home-dir [] {
    let modern = ($nu | get -o home-dir)

    if $modern != null {
        $modern
    } else {
        $nu | get home-path
    }
}

def normalize-path [value: path] {
    let expanded = ($value | path expand | into string)

    if $nu.os-info.name == 'windows' {
        $expanded | str lowercase
    } else {
        $expanded
    }
}

def prepare-autoload-dirs [] {
    for dir in $nu.user-autoload-dirs {
        mkdir $dir
        print $'[nushell] Autoload directory prepared: ($dir)'
    }
}

export def ensure-nushell-config-dir [] {
    let os = $nu.os-info.name
    let home = (nu-home-dir)

    let desired_xdg = (
        $home
        | path join '.config'
        | path expand
    )

    let desired_config = (
        $desired_xdg
        | path join 'nushell'
        | path expand
    )

    mkdir $desired_xdg

    if $os != 'windows' {
        print $'[nushell] Config directory: ($nu.default-config-dir)'
        prepare-autoload-dirs

        return {
            ready: true
            relaunch_required: false
            xdg_config_home: ($env.XDG_CONFIG_HOME? | default null)
            config_dir: $nu.default-config-dir
        }
    }

    let current_config = (normalize-path $nu.default-config-dir)
    let target_config = (normalize-path $desired_config)

    if $current_config == $target_config {
        print $'[nushell] Config directory already configured: ($desired_config)'
        prepare-autoload-dirs

        return {
            ready: true
            relaunch_required: false
            xdg_config_home: $desired_xdg
            config_dir: $desired_config
        }
    }

    print $'[nushell] Current config directory: ($nu.default-config-dir)'
    print $'[nushell] Target config directory:  ($desired_config)'
    print $'[nushell] Setting XDG_CONFIG_HOME: ($desired_xdg)'

    let result = (
        run-command 'setx.exe' [
            'XDG_CONFIG_HOME'
            $desired_xdg
        ]
    )

    if not $result.ok {
        let stderr = ($result.stderr | default '' | str trim)

        let detail = if ($stderr | is-empty) {
            $'setx.exe exited with code ($result.exit_code)'
        } else {
            $stderr
        }

        error make {
            msg: $'Failed to set XDG_CONFIG_HOME: ($detail)'
        }
    }

    {
        ready: false
        relaunch_required: true
        xdg_config_home: $desired_xdg
        config_dir: $desired_config
    }
}