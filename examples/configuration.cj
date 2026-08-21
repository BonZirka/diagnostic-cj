package examples

import diagnostic.*
import std.env.*

func runConfiguration(): Unit {
    let src = "let a = 1111111111111111111111111111111111111111111111111111111111111111111111111111111111\n"
    let diag = Diagnostic(
        range: Some(DiagnosticRange(startLine: 1, startColumn: 7, endLine: 1, endColumn: 8)),
        filename: "main.cj",
        severity: DiagnosticSeverity.Error,
        code: "line-too-long",
        source: "example",
        message: "long lines are truncated to the resolved width"
    )

    // Width is the tightest of all caps: source maxWidth, terminal width, and
    // COLUMNS env. 80 is only the fallback default when none of them are
    // known. In a terminal both renders below use the terminal width. When
    // stdout is a pipe there is no terminal, so the default face falls back
    // to 80 and the maxWidth face caps at 40.
    writeOut("=== default face (rerun example with different terminal width and $COLUMNS value) ===\n")
    let defaultFace = CLIDiagnosticFace(color: Some(true))
    let out = getStdOut()
    render([diag], defaultFace, Some(src), out)
    out.flush()

    writeOut("=== maxWidth = 40 (cap; never goes wider) ===\n")
    let narrow = CLIDiagnosticFace(maxWidth: Some(40), color: Some(true))
    let narrowOut = getStdOut()
    render([diag], narrow, Some(src), narrowOut)
    narrowOut.flush()
}
