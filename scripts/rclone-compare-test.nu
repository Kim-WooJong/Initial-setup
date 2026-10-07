#!/usr/bin/env nu
# Pure regressions for rclone.conf section comparison and crypt hashing.
const COMPARE = path self ./modules/rclone-compare.nu
use $COMPARE [compare-rclone-texts rclone-crypt-sections-hash encrypted-rclone-config]

def check [ok: bool message: string] {
    if not $ok { error make {msg: ("[rclone-compare-test] " + $message)} }
    print ("[pass] " + $message)
}

def main [] {
    let base = "[gd]\ntype = drive\ntoken = {\"a\":1}\n\n[sec]\ntype = crypt\nremote = gd:/data\npassword = AAA\npassword2 = BBB\n"
    let h = (rclone-crypt-sections-hash $base)
    check (($h | str length) == 64) "Crypt hash computed"
    check ((rclone-crypt-sections-hash ($base | str replace 'token = {"a":1}' 'token = {"a":2}')) == $h) "Token refresh does not change crypt hash"
    check ((rclone-crypt-sections-hash ($base | str replace 'password = AAA' 'password = ZZZ')) != $h) "Password change alters crypt hash"
    check ((rclone-crypt-sections-hash ($base | str replace 'password2 = BBB' 'password2 = CCC')) != $h) "Password2 change alters crypt hash"
    check ((rclone-crypt-sections-hash "[sec]\npassword2 = BBB\npassword = AAA\nremote = gd:/data\ntype = crypt\n") == $h) "Crypt hash ignores key order and other remotes"
    check ((rclone-crypt-sections-hash "[gd]\ntype = drive\n") == "") "No crypt remotes gives an empty hash"
    check ((rclone-crypt-sections-hash ($base | str replace --all "\n" "\r\n")) == $h) "CRLF line endings are tolerated"

    check (compare-rclone-texts $base ("# comment\n" + $base)).identical "Comments do not count as differences"
    let token = (compare-rclone-texts $base ($base | str replace '{"a":1}' '{"a":2}'))
    check ((not $token.identical) and $token.changed == [{name: "gd" crypt: false keys: ["token"]}]) "Token change is reported as gd/token only"
    let crypt = (compare-rclone-texts $base ($base | str replace 'password = AAA' 'password = ZZZ'))
    check ($crypt.changed == [{name: "sec" crypt: true keys: ["password"]}]) "Crypt password change names the crypt remote and key"
    let extra = (compare-rclone-texts ($base + "\n[new]\ntype = local\n") $base)
    check ($extra.only_local == ["new"] and ($extra.only_synced | is-empty)) "Remotes present on one side are listed"
    check (not (($crypt | to nuon) | str contains "ZZZ")) "Comparison results contain no values"
    check (encrypted-rclone-config "# Encrypted rclone configuration File\n\nRCLONE_ENCRYPT_V0:\nabc") "Password-encrypted rclone config is recognized"
    print "[ok] rclone comparison regressions passed."
}
