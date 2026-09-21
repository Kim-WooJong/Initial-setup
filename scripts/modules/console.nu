# Shared terminal presentation helpers.
# Respect NO_COLOR so CI/log capture remains plain text when requested.

def color-enabled [] {
    (($env.NO_COLOR? | default "" | str trim) | is-empty)
}

export def style [kind: string text: string] {
    if not (color-enabled) { return $text }
    let code = match $kind {
        "info" => (ansi cyan)
        "ok" => (ansi green)
        "warn" => (ansi yellow)
        "error" => (ansi red)
        "diff-add" => (ansi green)
        "diff-del" => (ansi red)
        "diff-hunk" => (ansi cyan)
        "diff-meta" => (ansi yellow)
        "heading" => (ansi magenta)
        _ => ""
    }
    if ($code | is-empty) { $text } else { $code + $text + (ansi reset) }
}

export def print-info [message: string] {
    print ((style "info" "[info]") + " " + $message)
}

export def print-ok [message: string] {
    print ((style "ok" "[ok]") + " " + $message)
}

export def print-warn [message: string] {
    print --stderr ((style "warn" "[warn]") + " " + $message)
}

export def print-error [message: string] {
    print --stderr ((style "error" "[error]") + " " + $message)
}

export def print-heading [message: string] {
    print (style "heading" $message)
}

export def print-diff-text [text: string] {
    for line in ($text | lines) {
        let rendered = if ($line | str starts-with "@@") {
            style "diff-hunk" $line
        } else if ($line | str starts-with "+++") or ($line | str starts-with "---") or ($line | str starts-with "diff ") or ($line | str starts-with "index ") {
            style "diff-meta" $line
        } else if ($line | str starts-with "+") {
            style "diff-add" $line
        } else if ($line | str starts-with "-") {
            style "diff-del" $line
        } else {
            $line
        }
        print $rendered
    }
}
