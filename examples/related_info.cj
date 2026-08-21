package examples

import diagnostic.*
import std.env.*

func runRelatedInfo(): Unit {
    let src = "let z = 42\nlet x = z\n"
    let diag = Diagnostic(
        range: Some(DiagnosticRange(startLine: 2, startColumn: 9, endLine: 2, endColumn: 10)),
        filename: "main.cj",
        severity: DiagnosticSeverity.Error,
        code: "undefined-variable",
        source: "example",
        message: "undefined variable 'z'",
        relatedInfo: [
            RelatedInfo(
                range: Some(DiagnosticRange(startLine: 1, startColumn: 5, endLine: 1, endColumn: 6)),
                filename: "main.cj",
                message: "defined here"
            ),
            RelatedInfo(
                range: None,
                filename: "docs/api/index.md",
                message: "see the API reference"
            )
        ]
    )
    let face = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
    let out = getStdOut()
    render([diag], face, Some(src), out)
    out.flush()
}