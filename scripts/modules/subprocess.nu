const PROCESS_OUTPUT = path self ./process-output.nu
use $PROCESS_OUTPUT [output-text]
const CONSOLE = path self ./console.nu
use $CONSOLE [print-status print-output-text]

# Shared external-command execution contract.
# Every caller receives launch state, exit code, stdout and stderr together.
export def run-command [
    program: string
    args: list = []
    --sensitive
    --live
    --interactive # Attach the child to the real terminal (no capture). Required
                  # for full-screen TUIs such as editors: capturing their output
                  # (even via --live tee) leaves them without a usable console
                  # and they hang, especially on Windows.
] {
    if $interactive {
        # No pipe, no `complete`: the child inherits this process's stdin/stdout/
        # stderr (the terminal). A non-zero exit raises, which we catch. stdout/
        # stderr are not captured because they go straight to the terminal.
        let ran = (try { ^$program ...$args; {launched: true exit_code: 0} } catch {|err| {launched: true exit_code: 1 launch_error: ($err.msg? | default ($err | into string))}})
        let ok = ($ran.exit_code == 0)
        return ($ran | merge {stdout: "" stderr: "" launch_error: ($ran.launch_error? | default "") ok: $ok diagnostic: (if $ok { "" } else { $ran.launch_error? | default "Interactive command failed." })})
    }
    let live_output = ($live and not $sensitive)
    let executed = (try {
        let result = if $live_output {
            do -i { ^$program ...$args }
            | tee { print --raw $in }
            | tee --stderr { print --stderr --raw $in }
            | complete
        } else {
            do -i { ^$program ...$args } | complete
        }
        {
            launched: true
            exit_code: ($result.exit_code? | default 1)
            stdout: ($result.stdout? | output-text)
            stderr: ($result.stderr? | output-text)
            launch_error: ""
        }
    } catch {|err|
        {
            launched: false
            exit_code: null
            stdout: ""
            stderr: ""
            launch_error: ($err.msg? | default ($err | into string))
        }
    })

    let ok = ($executed.launched and $executed.exit_code == 0)
    let diagnostic = if $sensitive {
        if $ok { "" } else { "Diagnostic output withheld because the command was marked sensitive." }
    } else if not $executed.launched {
        $executed.launch_error
    } else if not ($executed.stderr | str trim | is-empty) {
        $executed.stderr | str trim
    } else {
        $executed.stdout | str trim
    }

    $executed | merge {ok: $ok diagnostic: $diagnostic}
}

export def command-failure-message [label: string result: record --sensitive] {
    if $result.ok { return "" }
    let code = if $result.exit_code == null { "not launched" } else { "exit " + ($result.exit_code | into string) }
    let detail = if $sensitive {
        "Diagnostic output withheld because the command was marked sensitive."
    } else {
        $result.diagnostic? | default "" | str trim
    }
    if ($detail | is-empty) {
        $label + " failed (" + $code + ")."
    } else {
        $label + " failed (" + $code + ").\n" + $detail
    }
}

export def checked-command [label: string program: string args: list = [] --sensitive] {
    let result = (run-command $program $args --sensitive=$sensitive)
    if not $result.ok {
        error make {msg: (command-failure-message $label $result --sensitive=$sensitive)}
    }
    $result
}

export def print-result [label: string result: record] {
    if not ($result.stdout? | default "" | str trim | is-empty) {
        print-output-text ($result.stdout | str trim --right)
    }
    if not ($result.stderr? | default "" | str trim | is-empty) {
        print-output-text ($result.stderr | str trim --right) --stderr
    }
    if not $result.ok {
        print-status "warn" "warn" (command-failure-message $label $result) --stderr
    }
}
