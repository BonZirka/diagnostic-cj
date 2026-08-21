package diagnostic

import std.io.*

/**
 * One line per diagnostic, input order preserved, for logging pipelines:
 *   [error] CJMP-002: missing return (src/main.cj:12:3)
 * Multi-line messages collapse \n to " | "; related info is appended inline.
 * Never emits ANSI codes.
 */
public class LogDiagnosticFace <: DiagnosticFace {
    public func renderOne(d: Diagnostic, _: ?String, sink: OutputStream): Unit {
        let sb = StringBuilder()
        sb.append("[${levelName(d.severity)}]")
        if (!d.code.isEmpty()) {
            sb.append(" ${d.code}:")
        }
        sb.append(" ${collapse(d.message)}")
        match (d.range) {
            case Some(r) => sb.append(" (${d.filename}:${r.startLine}:${r.startColumn})")
            case None => ()
        }
        for ((i, rel) in d.relatedInfo.iterator().enumerate()) {
            if (i == 0) { sb.append(" ; ") } else { sb.append(" | ") }
            sb.append("note: ${collapse(rel.message)} (${relLoc(rel)})")
        }
        sink.write(sb.toString().toArray())
    }

    private func levelName(s: DiagnosticSeverity): String {
        match (s.toLogLevel()) {
            case LogLevel.Error => "error"
            case LogLevel.Warning => "warning"
            case LogLevel.Info => "info"
            case LogLevel.Debug => "debug"
        }
    }

    private func relLoc(rel: RelatedInfo): String {
        match (rel.range) {
            case Some(r) => "${rel.filename}:${r.startLine}:${r.startColumn}"
            case None => rel.filename
        }
    }

    private func collapse(s: String): String {
        s.replace("\n", " | ")
    }
}
