package examples

import diagnostic.*
import std.env.*

// Repro for the "caret lands on the right ellipsis" suspicion: a 1000-col
// line with a label deep inside (col 256) at width 80. Prints the raw frame
// so we can see where the caret ends up.
func runLongLine(): Unit {
    let sb = StringBuilder()
    for (_ in 0..1000) { sb.append("a") }
    let line = sb.toString()
    let d = Diagnostic(
        range: None,
        filename: "long.cj",
        severity: DiagnosticSeverity.Error,
        code: "long-line",
        source: "example",
        message: "error here",
        labels: [
            Label(
                range: DiagnosticRange(startLine: 1, startColumn: 256, endLine: 1, endColumn: 260),
                filename: "long.cj",
                message: "this is the spot"
            )
        ]
    )
    let face = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false))
    let out = getStdOut()
    render([d], face, Some(line), out)
    out.flush()
}
