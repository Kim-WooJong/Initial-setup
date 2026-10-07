const SUBPROCESS = path self ./subprocess.nu
const INSTALL_UTILS = path self ./install-utils.nu
const CONSOLE = path self ./console.nu
use $SUBPROCESS [run-command command-failure-message]
use $INSTALL_UTILS [probe-tool]
use $CONSOLE [style print-text]

# Shared diagnostic result format used by doctor/audit/preflight/verification.
# Severity describes policy; status describes the observed result.
export def diagnostic-check [
    id: string
    label: string
    severity: string
    ok: bool
    detail: string = ""
    remediation: string = ""
] {
    let status = if $ok {
        "pass"
    } else if $severity == "critical" {
        "fail"
    } else {
        "warn"
    }
    {
        id: $id
        label: $label
        severity: $severity
        status: $status
        ok: $ok
        detail: $detail
        remediation: $remediation
    }
}

export def tool-diagnostic [
    name: string
    args: list = ["--version"]
    severity: string = "warning"
    label: string = ""
    extra: list = []
] {
    let display = if ($label | is-empty) { $name } else { $label }
    let probe = (probe-tool $name $args $extra)
    let detail = if $probe.healthy {
        if ($probe.version | str trim | is-empty) {
            "Healthy executable: " + $probe.path
        } else {
            $probe.version + " | " + $probe.path
        }
    } else if not $probe.found {
        "Executable not found."
    } else {
        let reason = ($probe.result.diagnostic? | default "" | str trim)
        if ($reason | is-empty) {
            "Executable was found but the health probe failed: " + $probe.path
        } else {
            "Executable was found but the health probe failed: " + $probe.path + (char nl) + $reason
        }
    }
    (diagnostic-check ("tool:" + $name) $display $severity $probe.healthy $detail)
    | merge {probe: $probe}
}

export def command-diagnostic [
    id: string
    label: string
    severity: string
    program: string
    args: list = []
    --live
    --sensitive
] {
    let result = (run-command $program $args --live=$live --sensitive=$sensitive)
    let detail = if $result.ok {
        let output = ([$result.stdout $result.stderr] | where {|x| not ($x | str trim | is-empty) } | str join (char nl) | str trim)
        $output
    } else {
        command-failure-message $label $result --sensitive=$sensitive
    }
    (diagnostic-check $id $label $severity $result.ok $detail) | merge {result: $result}
}

export def print-diagnostic [row: record] {
    let presentation = match $row.status {
        "pass" => {kind: "ok" prefix: "[ok] "}
        "fail" => {kind: "error" prefix: "[FAIL] "}
        _ => {kind: "warn" prefix: "[WARN] "}
    }
    print-text $presentation.kind ($presentation.prefix + $row.label)
    let detail = ($row.detail? | default "" | str trim)
    if not ($detail | is-empty) {
        for line in ($detail | lines) {
            print ("       " + $line)
        }
    }
    let remediation = ($row.remediation? | default "" | str trim)
    if not ($remediation | is-empty) {
        print ((style "warn" "       fix:") + " " + $remediation)
    }
}

export def summarize-diagnostics [rows: list] {
    {
        passed: ($rows | where status == "pass" | length)
        failed: ($rows | where status == "fail" | length)
        warnings: ($rows | where status == "warn" | length)
        healthy: (($rows | where status == "fail" | is-empty))
    }
}
