package examples

import diagnostic.*
import std.env.*

// Full-width characters occupy 2 terminal cells and tabs advance to tab
// stops; carets and windowing stay aligned because all rendering math runs
// in display columns, and windows are cut on character boundaries.
func runCjk(): Unit {
    let face = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))

    // The caret spans both cells of each full-width character.
    let src1 = "let 路径 = \"数据/报表.csv\"\n"
    let d1 = Diagnostic(
        range: Some(DiagnosticRange(startLine: 1, startColumn: 5, endLine: 1, endColumn: 11)),
        filename: "报表.cj",
        severity: DiagnosticSeverity.Error,
        code: "undefined-variable",
        source: "example",
        message: "undefined variable '路径'"
    )

    // 80 display columns of CJK in a 40-column face: the line truncates on
    // a character boundary and the caret stays under its character.
    let src2 = "测试测试测试测试测试测试测试测试测试测试测试测试测试测试测试测试测试测试测试测试\n"
    let d2 = Diagnostic(
        range: Some(DiagnosticRange(startLine: 1, startColumn: 40, endLine: 1, endColumn: 43)),
        filename: "wide.txt",
        severity: DiagnosticSeverity.Warning,
        code: "line-too-long",
        source: "example",
        message: "line exceeds the display budget"
    )

    let out = getStdOut()
    render([d1], face, Some(src1), out)
    writeOut("\n")
    let narrow = CLIDiagnosticFace(maxWidth: Some(40), color: Some(true))
    render([d2], narrow, Some(src2), out)
    out.flush()
}
