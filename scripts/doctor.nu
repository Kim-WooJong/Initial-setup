#!/usr/bin/env nu

# ============================================================
# Inspect machine paths and available tools.
# ============================================================

def main [] {
    let config_file = (
        $nu.home-path
        | path join ".config" "dotfiles" "config.nuon"
    )

    print $"Nushell      : ($env.NU_VERSION)"
    print $"OS           : ($nu.os-info.name)"
    print $"Machine cfg  : ($config_file)"

    if not ($config_file | path exists) {
        print "[FAIL] Machine config is missing"
        return
    }

    let context = (open $config_file)
    let data_root = ($context.data_root | path expand)
    let tools_root = ($context.tools_root | path expand)

    print $"Tools root   : ($tools_root)"
    print $"Private data : ($data_root)"
    print ""

    if ($data_root | path exists) {
        print "[ok] Private data root exists"
    } else {
        print "[FAIL] Private data root is unavailable"
    }

    if (($data_root | path join ".chezmoiroot") | path exists) {
        print "[ok] .chezmoiroot exists"
    } else {
        print "[FAIL] .chezmoiroot is missing"
    }

    for tool in ["git" "chezmoi" "nvim" "starship" "wezterm" "code" "rg" "fd" "fzf" "bat" "zoxide" "direnv" "rustup" "cargo" "juliaup" "julia"] {
        if (which $tool | is-empty) {
            print $"[--] ($tool) not found"
        } else {
            print $"[ok] ($tool)"
        }
    }

    let sync_state = (
        $nu.home-path
        | path join ".config" "dotfiles" "sync-state.nuon"
    )

    let conflict_file = (
        $nu.home-path
        | path join ".config" "dotfiles" "SYNC-CONFLICT.txt"
    )

    if ($sync_state | path exists) {
        print "[ok] Automatic sync baseline exists"
    } else {
        print "[--] Automatic sync baseline is missing"
    }

    if ($conflict_file | path exists) {
        print "[WARN] Automatic sync conflict exists"
        print (
            "       "
            + ($conflict_file | into string)
        )
    } else {
        print "[ok] No automatic sync conflict"
    }

    print ""
    print "chezmoi status:"

    if not (which chezmoi | is-empty) and ($data_root | path exists) {
        let args = [
            "--source"
            ($data_root | into string)
            "status"
        ]

        ^chezmoi ...$args
    }
}
