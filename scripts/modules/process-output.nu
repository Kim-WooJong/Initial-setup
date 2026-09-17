# Human-readable subprocess diagnostics only. Never use this for configuration,
# secrets, manifest hashes, Git revisions, JSON payloads or other machine data.
# `complete` can return binary stdout/stderr when the stream is not valid UTF-8.
# No external command, filesystem access, imports or parse-time conversion here.

# Preserve ASCII diagnostic codes and UUID tokens even when decoding fails.
# Do NOT dump raw hex/base64: that can bypass a caller's textual token redaction.
# NULs are omitted so ASCII tokens in malformed UTF-16 remain redactable.
def ascii-diagnostic [value: binary] {
    $value | encode hex | split chars | chunks 2 | each {|pair|
        let hex = ($pair | str join "")
        if $hex == "00" { "" } else if $hex =~ '(?i)^(09|0a|0d|[2-6][0-9a-f]|7[0-9a-e])$' {
            $hex | decode hex | decode utf-8
        } else { "�" }
    } | str join ""
}

# Does not trim output or change exit codes. A missing stream is an empty string.
# UTF-8 and a UTF-16 BOM take precedence over the optional legacy encoding hint.
# An explicit hint (e.g. euc-kr) is ONLY for diagnostics; no code-page guessing.
export def output-text [--encoding: string]: any -> string {
    let value = $in
    let kind = ($value | describe)
    if $kind == "nothing" { return "" }
    if $kind == "string" { return $value }
    if $kind != "binary" { return ("[Non-text diagnostic omitted: " + $kind + "]") }
    if ($value | is-empty) { return "" }

    if ($value | bytes starts-with 0x[ff fe]) {
        let decoded = (try { $value | decode utf-16le } catch { null })
        if $decoded != null { return ($decoded | str trim --left --char (char --unicode feff)) }
    } else if ($value | bytes starts-with 0x[fe ff]) {
        let decoded = (try { $value | decode utf-16be } catch { null })
        if $decoded != null { return ($decoded | str trim --left --char (char --unicode feff)) }
    }
    # Strip a UTF-8 BOM explicitly; keep any subsequent bytes exactly as received.
    let payload = if ($value | bytes starts-with 0x[ef bb bf]) {
        if ($value | bytes length) == 3 { 0x[] } else { $value | bytes at 3.. }
    } else { $value }
    let utf8 = (try { $payload | decode utf-8 } catch { null })
    if $utf8 != null {
        # Some decoders replace malformed sequences rather than throwing. A
        # round-trip distinguishes valid UTF-8, including a genuine U+FFFD.
        if ($utf8 | encode utf-8) == $payload { return $utf8 }
    }
    let hint = if $encoding != null { $encoding } else { $env.INITIAL_SETUP_DIAGNOSTIC_ENCODING? | default "" }
    if ($hint | describe) == "string" and not ($hint | is-empty) {
        let decoded = (try { $payload | decode $hint } catch { null })
        if $decoded != null { return $decoded }
    }
    let fallback = (ascii-diagnostic $payload)
    [
        "[Non-UTF-8 diagnostic: non-ASCII bytes were replaced; ASCII error codes remain. Set INITIAL_SETUP_DIAGNOSTIC_ENCODING only when the helper's encoding is known.]"
        $fallback
    ] | str join (char nl)
}
