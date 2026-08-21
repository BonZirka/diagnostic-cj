package diagnostic

import std.collection.*
import std.io.*

// ============ Diagnostic primitives ============

/**
 * The severity level of a diagnostic.
 */
public enum DiagnosticSeverity {
    | Error
    | Warning
    | Information
    | Hint

    /** LSP severity number (Error=1, Warning=2, Information=3, Hint=4). */
    public func toLspNumber(): Int64 {
        match (this) {
            case Error => 1
            case Warning => 2
            case Information => 3
            case Hint => 4
        }
    }

    /** Display name ("error", "warning", "note", "hint"). */
    public func toString(): String {
        match (this) {
            case Error => "error"
            case Warning => "warning"
            case Information => "note"
            case Hint => "hint"
        }
    }

    /** Maps to a log level for tooling: error, warning, info, debug. */
    public func toLogLevel(): LogLevel {
        match (this) {
            case Error => LogLevel.Error
            case Warning => LogLevel.Warning
            case Information => LogLevel.Info
            case Hint => LogLevel.Debug
        }
    }
}

/**
 * A source range with 1-based line and column numbers.
 */
public struct DiagnosticRange {
    public let startLine: Int64      // 1-based
    public let startColumn: Int64    // 1-based byte column
    public let endLine: Int64
    public let endColumn: Int64

    public init(startLine!: Int64, startColumn!: Int64, endLine!: Int64, endColumn!: Int64) {
        this.startLine = startLine
        this.startColumn = startColumn
        this.endLine = endLine
        this.endColumn = endColumn
    }
}

/**
 * Additional context attached to a diagnostic (e.g., "defined here", "see also").
 */
public struct RelatedInfo {
    public let range: ?DiagnosticRange
    public let filename: String
    public let message: String

    public init(range!: ?DiagnosticRange, filename!: String, message!: String) {
        this.range = range
        this.filename = filename
        this.message = message
    }
}

/**
 * Semantic role of a label within a diagnostic. Faces map this to visual
 * styling independently of the diagnostic's severity: the CLI face renders
 * Primary carets red and Secondary carets blue (rustc convention).
 */
public enum LabelStyle {
    | Primary
    | Secondary
}

/**
 * A labeled source region with an associated message, used for multi-location
 * diagnostics (e.g., "variable used before definition").
 */
public struct Label {
    public let range: DiagnosticRange
    public let filename: String
    public let message: String
    public let style: ?LabelStyle

    public init(
        range!: DiagnosticRange,
        filename!: String,
        message!: String,
        style!: ?LabelStyle = None
    ) {
        this.range = range
        this.filename = filename
        this.message = message
        this.style = style
    }
}

/**
 * A complete diagnostic with location, severity, code, message, and optional
 * related information and labels.
 */
public struct Diagnostic {
    public let range: ?DiagnosticRange
    public let filename: String
    public let severity: DiagnosticSeverity
    public let code: String
    public let source: String
    public let message: String
    public let relatedInfo: Array<RelatedInfo>
    public let labels: Array<Label>

    public init(
        range!: ?DiagnosticRange,
        filename!: String,
        severity!: DiagnosticSeverity,
        code!: String,
        source!: String,
        message!: String,
        relatedInfo!: Array<RelatedInfo> = Array<RelatedInfo>(),
        labels!: Array<Label> = Array<Label>()
    ) {
        this.range = range
        this.filename = filename
        this.severity = severity
        this.code = code
        this.source = source
        this.message = message
        this.relatedInfo = relatedInfo
        // Structural invariant: every locatable diagnostic carries labels.
        // A bare range becomes one implicit primary label (empty caret
        // message) so every face renders a single shape. `range` stays
        // stored for log locations, JSON output, and sorting, none of
        // which read labels.
        var ls = labels
        if (ls.size == 0) {
            match (range) {
                case Some(r) => ls = [Label(range: r, filename: filename, message: "")]
                case None => ()
            }
        }
        this.labels = ls
    }
}

// ============ Log levels and filtering ============

/**
 * A log level used for filtering diagnostics by severity.
 *
 * Rank order: Error < Warning < Info < Debug.
 */
public enum LogLevel {
    | Error
    | Warning
    | Info
    | Debug
}

// Ranks used for level comparisons (Cangjie enums have no ==).
private func logLevelRank(l: LogLevel): Int64 {
    match (l) {
        case LogLevel.Error => 0
        case LogLevel.Warning => 1
        case LogLevel.Info => 2
        case LogLevel.Debug => 3
    }
}

private func severityLevelRank(s: DiagnosticSeverity): Int64 {
    match (s) {
        case DiagnosticSeverity.Error => 0
        case DiagnosticSeverity.Warning => 1
        case DiagnosticSeverity.Information => 2
        case DiagnosticSeverity.Hint => 3
    }
}

/**
 * Keeps diagnostics whose severity maps to a log level at or above minLevel.
 * Pure and order-preserving; compose with any face:
 *   renderToString(filterDiagnostics(diags, LogLevel.Info), LogDiagnosticFace(), None)
 */
public func filterDiagnostics(
    diagnostics: Array<Diagnostic>,
    minLevel: LogLevel
): Array<Diagnostic> {
    let minRank = logLevelRank(minLevel)
    let out = ArrayList<Diagnostic>()
    for (d in diagnostics) {
        if (severityLevelRank(d.severity) >= minRank) {
            out.add(d)
        }
    }
    out.toArray()
}

// ============ Generic conversion API ============

// To convert your own error type into a Diagnostic, add a static extension from
// your own package (verified to work across packages):
//   extend Diagnostic {
//       public static func from(e: MyError): Diagnostic { ... }
//   }
// Call sites then use `Diagnostic.from(e)`.

// ============ DiagnosticFace interface ============

/**
 * Renders diagnostics for a specific output channel (terminal, log, JSON-RPC).
 * Not sealed: consumers may implement custom faces.
 */
public interface DiagnosticFace {
    /** Renders a single diagnostic to the sink, atomically. */
    func renderOne(d: Diagnostic, source: ?String, sink: OutputStream): Unit

    /** Default: streams each diagnostic to the sink, separated by newlines. */
    func render(diagnostics: Array<Diagnostic>, source: ?String, sink: OutputStream): Unit {
        for ((i, d) in diagnostics.iterator().enumerate()) {
            if (i > 0) { sink.write("\n".toArray()) }
            this.renderOne(d, source, sink)
        }
    }

    /** Convenience: renders to a String via ByteBuffer. */
    func renderToString(diagnostics: Array<Diagnostic>, source: ?String): String {
        let buf = ByteBuffer()
        this.render(diagnostics, source, buf)
        String.fromUtf8(buf.bytes())
    }
}

// ============ Top-level rendering entries ============

/**
 * Renders diagnostics to an OutputStream using the given face.
 */
public func render(
    diagnostics: Array<Diagnostic>,
    face: DiagnosticFace,
    source: ?String,
    sink: OutputStream
): Unit {
    face.render(diagnostics, source, sink)
}

/**
 * Renders diagnostics to a String using the given face.
 */
public func renderToString(
    diagnostics: Array<Diagnostic>,
    face: DiagnosticFace,
    source: ?String
): String {
    face.renderToString(diagnostics, source)
}
