package examples

import diagnostic.*
import std.env.*

// Demo: many labels in one file exercising sub-frame joining. Labels whose
// line gaps are <= 2 share ONE frame (==> header), with unlabeled gap-mid
// rows between them; the next label 4+ lines below starts a ":::" sub-frame,
// which also picks up its non-blank neighbor lines as context rows.
//
// Source layout (1-based columns):
// 1  func process(items: ArrayList<String>): Int64 {
// 2      let total = 0                    total       9..14
// 3      let seen = HashSet<String>()     HashSet    15..22
// 4      for (item in items) {            item        9..13
// 5          if (item.isEmpty()) { continue }
// 6          total += item.size           total 9..14, item 18..22
// 7      }
// 8      return total                     total      12..17
// 9  }
// 11 func validate(name: String): Bool {
// 12     return !name.isEmpty()           name       13..17
// 13 }
// 15 func main() {
// 16     let xs = ArrayList<String>()     xs          9..11
// 17     println(process(xs))
// 18 }
func runJoining(): Unit {
    var src = ""
    src = src + "func process(items: ArrayList<String>): Int64 {\n"
    src = src + "    let total = 0\n"
    src = src + "    let seen = HashSet<String>()\n"
    src = src + "    for (item in items) {\n"
    src = src + "        if (item.isEmpty()) { continue }\n"
    src = src + "        total += item.size\n"
    src = src + "    }\n"
    src = src + "    return total\n"
    src = src + "}\n"
    src = src + "\n"
    src = src + "func validate(name: String): Bool {\n"
    src = src + "    return !name.isEmpty()\n"
    src = src + "}\n"
    src = src + "\n"
    src = src + "func main() {\n"
    src = src + "    let xs = ArrayList<String>()\n"
    src = src + "    println(process(xs))\n"
    src = src + "}\n"

    let d = Diagnostic(
        range: None,
        filename: "process.cj",
        severity: DiagnosticSeverity.Warning,
        code: "flow-analysis",
        source: "example",
        message: "several findings in this module",
        labels: [
            Label(range: DiagnosticRange(startLine: 2, startColumn: 9, endLine: 2, endColumn: 14),
                filename: "process.cj", message: "variable is never read"),
            Label(range: DiagnosticRange(startLine: 3, startColumn: 15, endLine: 3, endColumn: 22),
                filename: "process.cj", message: "element type inferred"),
            Label(range: DiagnosticRange(startLine: 4, startColumn: 9, endLine: 4, endColumn: 13),
                filename: "process.cj", message: "iteration order matters"),
            Label(range: DiagnosticRange(startLine: 6, startColumn: 9, endLine: 6, endColumn: 14),
                filename: "process.cj", message: "possible overflow"),
            Label(range: DiagnosticRange(startLine: 6, startColumn: 18, endLine: 6, endColumn: 22),
                filename: "process.cj", message: "right operand"),
            Label(range: DiagnosticRange(startLine: 8, startColumn: 12, endLine: 8, endColumn: 17),
                filename: "process.cj", message: "value consumed here"),
            Label(range: DiagnosticRange(startLine: 12, startColumn: 13, endLine: 12, endColumn: 17),
                filename: "process.cj", message: "condition is always true"),
            Label(range: DiagnosticRange(startLine: 16, startColumn: 9, endLine: 16, endColumn: 11),
                filename: "process.cj", message: "list is empty here")
        ]
    )
    let face = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false))
    let out = getStdOut()
    render([d], face, Some(src), out)
    out.flush()
}
