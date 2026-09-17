# Case conversion across the documented Nushell 0.109.1+ baseline.
# A runtime `if` around two command calls would still parse BOTH branches.
# Select an import at parse time instead; do not suppress parser warnings and
# do not spawn a subprocess or build command strings from user data.
const NU_PARTS = ((version).version | split row ".")
# The supported legacy window is finite: 0.109.1 through 0.113.x.
# Equality, list membership and boolean operators need no conversion command.
# Do NOT call `into int` here: it is not const across the supported baseline.
# The minimum-version check still owns rejection of unsupported older Nu.
const MODERN_CASE = ($NU_PARTS.0 != "0" or $NU_PARTS.1 not-in ["109" "110" "111" "112" "113"])
const LEGACY_FILE = path self ./compat/case-legacy.nu
const MODERN_FILE = path self ./compat/case-modern.nu
const CASE_FILE = if $MODERN_CASE { $MODERN_FILE } else { $LEGACY_FILE }
export use $CASE_FILE [text-lower text-upper]

export def case-backend [] {
    if $MODERN_CASE { "modern" } else { "legacy" }
}
