package examples

import diagnostic.*
import std.env.*

func runLabels(): Unit {
    let src = "let x = 1\nlet y = x + z\nlet z = 42\n"
    let diag = Diagnostic(
        range: None,
        filename: "main.cj",
        severity: DiagnosticSeverity.Error,
        code: "use-before-def",
        source: "example",
        message: "variable 'z' used before definition",
        labels: [
            Label(
                range: DiagnosticRange(startLine: 2, startColumn: 13, endLine: 2, endColumn: 14),
                filename: "main.cj",
                message: "used here"
            ),
            Label(
                range: DiagnosticRange(startLine: 3, startColumn: 5, endLine: 3, endColumn: 6),
                filename: "main.cj",
                message: "defined here"
            )
        ]
    )
    let face = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
    let out = getStdOut()
    render([diag], face, Some(src), out)
    out.flush()
}