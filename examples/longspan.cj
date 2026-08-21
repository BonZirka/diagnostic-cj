package examples

import diagnostic.*
import std.env.*

// Demonstrates long-span windowing with the span starting at different
// positions in the line (near the start, in the middle, near the end) and
// with different span lengths (almost COLUMNS, exactly COLUMNS, exceeding
// COLUMNS). This exercises the deterministic window allocator — span in
// full first, passive right fill capped at RIGHT_FILL_MAX including its
// ellipsis under the LEFT_KEEP_MIN left floor, overflow trimming the left
// side only until SPAN_KEEP_MIN span columns remain — across different
// caret positions.
//
// The source line is 200 chars: "AAAAA..B..xxxx..MIDDLE..xxxx..ENDXX..xxx"
// with recognizable markers at known positions so we can see which part
// of the line the window captures.
func runLongSpan(): Unit {
    let out = getStdOut()

    // Build a 200-char line with recognizable markers at known positions:
    //   cols  0-4:  "AAAAA"   (start marker)
    //   col   7:    "B"       (span-start-near-beginning marker)
    //   cols 40-45: "MIDDLE"  (middle marker)
    //   cols 95-99: "ENDXX"   (near-end marker)
    //   rest: 'x' padding
    let pad = { n: Int64 => var s = ""; for (_ in 0..n) { s += "x" }; s }
    let src = "AAAAA" + pad(2) + "B" + pad(32) + "MIDDLE" + pad(49) + "ENDXX" + pad(100)
    // Total: 5 + 2 + 1 + 32 + 6 + 49 + 5 + 100 = 200

    let writeHeader = { s: String =>
        out.write(("\n" + s + "\n").toArray())
        out.flush()
    }

    let renderAt = { cols: Int64, startCol: Int64, endCol: Int64, severity: DiagnosticSeverity, code: String, msg: String =>
        let d = Diagnostic(
            range: None,
            filename: "longspan.cj",
            severity: severity,
            code: code,
            source: "example",
            message: msg,
            labels: [
                Label(
                    range: DiagnosticRange(
                        startLine: 1, startColumn: startCol,
                        endLine: 1, endColumn: endCol
                    ),
                    filename: "longspan.cj",
                    message: "span"
                )
            ]
        )
        let face = CLIDiagnosticFace(maxWidth: Some(cols), color: Some(true))
        render([d], face, Some(src), out)
        out.flush()
    }

    // --- Span starts near the BEGINNING (col 7) ---

    writeHeader("=== Start=7, span=33 (almost fits COLUMNS=40) — small left context ===")
    renderAt(40, 8, 41, DiagnosticSeverity.Error, "beg-almost", "span near start, almost fits")
    // cs=7 (0-based), cl=33. leftCtx=7 (small), postSpan=160. Budget=36.

    writeHeader("=== Start=7, span=50 (exceeds COLUMNS=40) — overflow, small left ===")
    renderAt(40, 8, 58, DiagnosticSeverity.Warning, "beg-exceeds", "span near start, exceeds")
    // cs=7, cl=50. cl > bg-3=33 -> span overflow. ws=7, no left context.

    // --- Span starts in the MIDDLE (col 40) ---

    writeHeader("=== Start=40, span=33 (almost fits COLUMNS=40) — large left context ===")
    renderAt(40, 41, 74, DiagnosticSeverity.Error, "mid-almost", "span in middle, almost fits")
    // cs=40, cl=33. leftCtx=40 (large), postSpan=127. Budget=36.

    writeHeader("=== Start=40, span=50 (exceeds COLUMNS=40) — overflow, large left ===")
    renderAt(40, 41, 91, DiagnosticSeverity.Information, "mid-exceeds", "span in middle, exceeds")
    // cs=40, cl=50. Overflow: left trims to leave SPAN_KEEP_MIN=10 visible
    // span columns (window starts 20 cols into the line), carets cover the
    // right "...".

    // --- Span starts near the END (col 95) ---

    writeHeader("=== Start=95, span=5 (small span near end) — large left context ===")
    renderAt(40, 96, 101, DiagnosticSeverity.Error, "end-small", "small span near end")
    // cs=95, cl=5. leftCtx=95 (huge), postSpan=100. Budget=36.

    // --- Same spans at wider COLUMNS=60 ---

    writeHeader("=== Start=7, span=33 at COLUMNS=60 — fits with room for context ===")
    renderAt(60, 8, 41, DiagnosticSeverity.Error, "beg-60", "span near start, wider terminal")

    writeHeader("=== Start=40, span=33 at COLUMNS=60 — fits with room for context ===")
    renderAt(60, 41, 74, DiagnosticSeverity.Error, "mid-60", "span in middle, wider terminal")

    writeHeader("=== Start=95, span=5 at COLUMNS=60 — fits with room for context ===")
    renderAt(60, 96, 101, DiagnosticSeverity.Error, "end-60", "span near end, wider terminal")

    // --- Very long span (100 cols) at different starts ---

    writeHeader("=== Start=7, span=100 (far exceeds COLUMNS=40) — overflow ===")
    renderAt(40, 8, 108, DiagnosticSeverity.Error, "beg-huge", "huge span near start")

    writeHeader("=== Start=60, span=100 (far exceeds COLUMNS=40) — overflow ===")
    renderAt(40, 61, 161, DiagnosticSeverity.Error, "mid-huge", "huge span in middle")
}
