# Shared terminal presentation helpers.
# Respect NO_COLOR so CI/log capture remains plain text when requested.

# Keep this module dependency-free so it can be used from setup, subprocess,
# and low-level modules without creating import cycles.
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
        "prompt" => (ansi yellow)
        "choice" => (ansi cyan)
        "command" => (ansi cyan)
        "label" => (ansi cyan)
        "diff-add" => (ansi green)
        "diff-del" => (ansi red)
        "diff-hunk" => (ansi cyan)
        "diff-meta" => (ansi yellow)
        "heading" => (ansi magenta)
        _ => ""
    }
    if ($code | is-empty) { $text } else { $code + $text + (ansi reset) }
}


def emit [text: string --stderr] {
    if $stderr {
        print --stderr $text
    } else {
        print $text
    }
}

export def print-text [kind: string text: string --stderr] {
    emit (style $kind $text) --stderr=$stderr
}

export def print-status [kind: string tag: string message: string --stderr] {
    let rendered = ((style $kind ("[" + $tag + "]")) + " " + $message)
    emit $rendered --stderr=$stderr
}

export def print-info [message: string] {
    print-status "info" "info" $message
}

export def print-ok [message: string] {
    print-status "ok" "ok" $message
}

export def print-warn [message: string] {
    print-status "warn" "warn" $message --stderr
}

export def print-error [message: string] {
    print-status "error" "error" $message --stderr
}

export def print-heading [message: string --stderr] {
    print-text "heading" $message --stderr=$stderr
}

# Color only the field label. Keep values unmodified so paths/IDs remain easy
# to copy from a terminal and structured-looking values are not over-styled.
export def print-key-value [label: string value: any --stderr] {
    let rendered = ((style "label" $label) + ($value | into string))
    emit $rendered --stderr=$stderr
}

export def print-choice [key: string message: string --stderr] {
    let rendered = ("  " + (style "choice" ("[" + $key + "]")) + " " + $message)
    emit $rendered --stderr=$stderr
}

export def print-list-item [message: string --stderr] {
    let rendered = ("  " + (style "info" "-") + " " + $message)
    emit $rendered --stderr=$stderr
}

export def print-command [command: string --stderr] {
    emit ("  " + (style "command" $command)) --stderr=$stderr
}

# Color common tagged output produced by child scripts without changing the
# underlying text. Unknown/plain lines are intentionally emitted unchanged.
export def print-output-text [text: string --stderr] {
    for line in ($text | lines) {
        let trimmed = ($line | str trim --left)
        let kind = if (
            ($trimmed | str starts-with "[ok]") or
            ($trimmed | str starts-with "[pass]") or
            ($trimmed | str starts-with "[save]") or
            ($trimmed | str starts-with "[create]") or
            ($trimmed | str starts-with "[update]") or
            ($trimmed | str starts-with "[restored]") or
            ($trimmed | str starts-with "[validated]") or
            ($trimmed | str starts-with "[encrypted]")
        ) {
            "ok"
        } else if (
            ($trimmed | str starts-with "[warn]") or
            ($trimmed | str starts-with "[WARN]") or
            ($trimmed | str starts-with "[skip]") or
            ($trimmed | str starts-with "[inactive]") or
            ($trimmed | str starts-with "[cancelled]") or
            ($trimmed | str starts-with "[kept]")
        ) {
            "warn"
        } else if (
            ($trimmed | str starts-with "[error]") or
            ($trimmed | str starts-with "[FAIL]") or
            ($trimmed | str starts-with "[fail]")
        ) {
            "error"
        } else if (
            ($trimmed | str starts-with "[run]") or
            ($trimmed | str starts-with "[info]") or
            ($trimmed | str starts-with "[test]") or
            ($trimmed | str starts-with "[report]") or
            ($trimmed | str starts-with "[sync]") or
            ($trimmed | str starts-with "[backup]") or
            ($trimmed | str starts-with "[recovery]") or
            ($trimmed | str starts-with "[setup]") or
            ($trimmed | str starts-with "[provider]") or
            ($trimmed | str starts-with "[rpool]") or
            ($trimmed | str starts-with "[preview]") or
            ($trimmed | str starts-with "[safe-update]") or
            ($trimmed | str starts-with "[vault]") or
            ($trimmed | str starts-with "[vault:init]") or
            ($trimmed | str starts-with "[rclone]") or
            ($trimmed | str starts-with "[restore]") or
            ($trimmed | str starts-with "[push]") or
            ($trimmed | str starts-with "[pull]")
        ) {
            "info"
        } else {
            ""
        }
        let rendered = if ($kind | is-empty) { $line } else { style $kind $line }
        emit $rendered --stderr=$stderr
    }
}

# Preserve the original unified diff text exactly apart from ANSI decoration.
# Header/metadata lines are yellow, hunks cyan, additions green, deletions red.
export def print-diff-text [text: string --stderr] {
    for line in ($text | lines) {
        let rendered = if ($line | str starts-with "@@") {
            style "diff-hunk" $line
        } else if (
            ($line | str starts-with "+++") or
            ($line | str starts-with "---") or
            ($line | str starts-with "diff ") or
            ($line | str starts-with "index ") or
            ($line | str starts-with "\\ No newline at end of file")
        ) {
            style "diff-meta" $line
        } else if ($line | str starts-with "+") {
            style "diff-add" $line
        } else if ($line | str starts-with "-") {
            style "diff-del" $line
        } else {
            $line
        }
        emit $rendered --stderr=$stderr
    }
}
