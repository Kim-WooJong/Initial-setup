# Fixed location of the private synchronized settings.

# Private synchronized settings always live in this checkout subdirectory.
# It is git-ignored and excluded from release inventories, syntax/project
# validation and junk cleanup (search for CHECKOUT_PRIVATE_DIR users).
export const CHECKOUT_PRIVATE_DIR = "private"

export def default-data-root [tools_root: path] {
    $tools_root | path expand | path join $CHECKOUT_PRIVATE_DIR
}
