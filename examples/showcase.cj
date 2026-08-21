package examples

import diagnostic.*
import std.env.*

// Hero demo for README/demo.png: a type mismatch whose labels sit one line
// apart, so the renderer JOINS them into a single sub-frame — secondary label
// on the signature row, primary caret at the call site below — followed by an
// unreachable-code warning. Color is forced on so screenshots always have ANSI.
func runShowcase(): Unit {
    let src = """
func `折扣价`(`原价`: Float64, `折扣`: Float64): Float64 {
    let `结算`: Int64 = `折扣价`(100.0, 0.8)
    return `结算`
    let `过期日` = `日期`(2024, 12, 31)
}
"""
    let d1 = Diagnostic(
        range: Some(DiagnosticRange(startLine: 2, startColumn: 27, endLine: 2, endColumn: 50)),
        filename: "报表.cj",
        severity: DiagnosticSeverity.Error,
        code: "type-mismatch",
        source: "example",
        message: "mismatched types",
        labels: [
            Label(
                range: DiagnosticRange(startLine: 2, startColumn: 27, endLine: 2, endColumn: 50),
                filename: "报表.cj",
                message: "expected Int64, found Float64"
            ),
            Label(
                range: DiagnosticRange(startLine: 1, startColumn: 47, endLine: 1, endColumn: 54),
                filename: "报表.cj",
                message: "returns Float64",
                style: Some(LabelStyle.Secondary)
            )
        ],
        relatedInfo: [
            RelatedInfo(range: None, filename: "docs/numbers.md", message: "numeric conversions in Cangjie")
        ]
    )
    let d2 = Diagnostic(
        range: Some(DiagnosticRange(startLine: 4, startColumn: 5, endLine: 4, endColumn: 45)),
        filename: "报表.cj",
        severity: DiagnosticSeverity.Warning,
        code: "unreachable-code",
        source: "example",
        message: "statement is never reached"
    )
    let face = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
    let out = getStdOut()
    render([d1, d2], face, Some(src), out)
    out.flush()
}
