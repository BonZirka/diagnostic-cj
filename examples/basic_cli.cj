package examples

import diagnostic.*
import std.env.*

func runBasicCli(): Unit {
    let src = "let x = 1\nlet y = x + z\n"
    let diag = Diagnostic(
        range: Some(DiagnosticRange(startLine: 2, startColumn: 13, endLine: 2, endColumn: 14)),
        filename: "main.cj",
        severity: DiagnosticSeverity.Error,
        code: "undefined-variable",
        source: "example",
        message: "undefined variable 'z'"
    )
    let face = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
    let out = getStdOut()
    render([diag], face, Some(src), out)
    out.flush()
}