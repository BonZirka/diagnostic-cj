package examples

import diagnostic.*
import std.env.*

// Probe: labels on neighboring lines (gap <= 2, so they render in ONE frame
// with no "..." between them) but far apart horizontally. With per-line
// windowing, each line windows to its own caret, so the frame shows a
// different column range per line — confusing. 12 lines of 300 cols each.
func runNeighbors(): Unit {
    let sb = StringBuilder()
    for (ln in 1..=12) {
        for (_ in 0..300) { sb.append("a") }
        sb.append("\n")
    }
    let src = sb.toString()
    let d = Diagnostic(
        range: None,
        filename: "neighbors.cj",
        severity: DiagnosticSeverity.Error,
        code: "neighbor-spread",
        source: "example",
        message: "labels far apart on neighboring lines",
        labels: [
            Label(range: DiagnosticRange(startLine: 2, startColumn: 10, endLine: 2, endColumn: 11),
                filename: "neighbors.cj", message: "left"),
            Label(range: DiagnosticRange(startLine: 3, startColumn: 250, endLine: 3, endColumn: 251),
                filename: "neighbors.cj", message: "right"),
            Label(range: DiagnosticRange(startLine: 4, startColumn: 10, endLine: 4, endColumn: 11),
                filename: "neighbors.cj", message: "left"),
            Label(range: DiagnosticRange(startLine: 5, startColumn: 250, endLine: 5, endColumn: 251),
                filename: "neighbors.cj", message: "right"),
            Label(range: DiagnosticRange(startLine: 6, startColumn: 10, endLine: 6, endColumn: 11),
                filename: "neighbors.cj", message: "left"),
            Label(range: DiagnosticRange(startLine: 7, startColumn: 250, endLine: 7, endColumn: 251),
                filename: "neighbors.cj", message: "right")
        ]
    )
    let face = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false))
    let out = getStdOut()
    render([d], face, Some(src), out)
    out.flush()
}
