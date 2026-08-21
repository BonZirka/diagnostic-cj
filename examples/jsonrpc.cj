package examples

import diagnostic.*
import std.env.*

func runJsonRpc(): Unit {
    let diag = Diagnostic(
        range: Some(DiagnosticRange(startLine: 3, startColumn: 2, endLine: 3, endColumn: 6)),
        filename: "src/main.cj",
        severity: DiagnosticSeverity.Warning,
        code: "unused-variable",
        source: "example",
        message: "unused variable"
    )
    let face = JsonRpcDiagnosticFace()
    let out = getStdOut()
    render([diag], face, None, out)
    out.flush()
}