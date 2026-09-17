# No business code should be parsed until setup/sync selects its runtime.
# Utilities and installed terminals still need correct legacy command selection.
const NU_PARTS = ((version).version | split row ".")
# Keep the complete, finite set of pre-0.114 minor versions as literal strings.
# List membership is sufficient here: do not use regex, numeric conversion or
# runtime commands in this parse-time selector. This also covers old seed Nu
# versions (such as 0.108); classifying a version is not a support guarantee.
const LEGACY_MINORS = [
    "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
    "10" "11" "12" "13" "14" "15" "16" "17" "18" "19"
    "20" "21" "22" "23" "24" "25" "26" "27" "28" "29"
    "30" "31" "32" "33" "34" "35" "36" "37" "38" "39"
    "40" "41" "42" "43" "44" "45" "46" "47" "48" "49"
    "50" "51" "52" "53" "54" "55" "56" "57" "58" "59"
    "60" "61" "62" "63" "64" "65" "66" "67" "68" "69"
    "70" "71" "72" "73" "74" "75" "76" "77" "78" "79"
    "80" "81" "82" "83" "84" "85" "86" "87" "88" "89"
    "90" "91" "92" "93" "94" "95" "96" "97" "98" "99"
    "100" "101" "102" "103" "104" "105" "106" "107" "108" "109"
    "110" "111" "112" "113"
]
const MODERN_CASE = ($NU_PARTS.0 != "0" or $NU_PARTS.1 not-in $LEGACY_MINORS)
const LEGACY_FILE = path self ./compat/case-legacy.nu
const MODERN_FILE = path self ./compat/case-modern.nu
const CASE_FILE = if $MODERN_CASE { $MODERN_FILE } else { $LEGACY_FILE }
export use $CASE_FILE [text-lower text-upper]

export def case-backend [] {
    if $MODERN_CASE { "modern" } else { "legacy" }
}
