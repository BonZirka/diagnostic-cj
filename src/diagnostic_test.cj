package diagnostic

import std.unittest.*
import std.unittest.testmacro.*
import std.fs.*
import std.env.*
import std.collection.*
import std.io.*

@Test
public class SeverityTest {
    @TestCase
    public func lspNumbers(): Unit {
        @Assert(DiagnosticSeverity.Error.toLspNumber() == 1)
        @Assert(DiagnosticSeverity.Warning.toLspNumber() == 2)
        @Assert(DiagnosticSeverity.Information.toLspNumber() == 3)
        @Assert(DiagnosticSeverity.Hint.toLspNumber() == 4)
    }

    @TestCase
    public func displayNames(): Unit {
        @Assert(DiagnosticSeverity.Error.toString() == "error")
        @Assert(DiagnosticSeverity.Warning.toString() == "warning")
        @Assert(DiagnosticSeverity.Information.toString() == "note")
        @Assert(DiagnosticSeverity.Hint.toString() == "hint")
    }
}

struct StubError {
    let message: String
    init(message!: String) {
        this.message = message
    }
}

extend Diagnostic {
    public static func from(e: StubError): Diagnostic {
        Diagnostic(
            range: None,
            filename: "stub.toml",
            severity: DiagnosticSeverity.Error,
            code: "stub-error",
            source: "stub",
            message: e.message
        )
    }
}

@Test
public class ConversionTest {
    @TestCase
    public func diagnosticFromRoundTrip(): Unit {
        let d = Diagnostic.from(StubError(message: "boom"))
        @Assert(d.message == "boom")
        @Assert(d.code == "stub-error")
        @Assert(d.filename == "stub.toml")
        @Assert(match (d.severity) {
            case DiagnosticSeverity.Error => true
            case _ => false
        })
    }
}

class StubFace <: DiagnosticFace {
    public func renderOne(d: Diagnostic, source: ?String, sink: OutputStream): Unit {
        sink.write("rendered:1".toArray())
    }

    public func render(diagnostics: Array<Diagnostic>, source: ?String, sink: OutputStream): Unit {
        sink.write("rendered:${diagnostics.size}".toArray())
    }
}

@Test
public class FaceTest {
    @TestCase
    public func stubFaceIsImplementableAndDispatchable(): Unit {
        let out = StubFace().renderToString(Array<Diagnostic>(), None)
        @Assert(out == "rendered:0")
    }
}

@Test
public class CliFaceTest {
    @TestCase
    public func sortsByFilenameThenLineColumn(): Unit {
        let d1 = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 5, endLine: 2, endColumn: 6)),
            filename: "b.toml", severity: DiagnosticSeverity.Error, code: "c1", source: "cjpm",
            message: "second")
        let d2 = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 9, endLine: 1, endColumn: 10)),
            filename: "a.toml", severity: DiagnosticSeverity.Warning, code: "c2", source: "cjpm",
            message: "first")
        let out = renderToString([d1, d2], CLIDiagnosticFace(color: Some(false)), None)
        @Assert((out.indexOf("first") ?? -1) < (out.indexOf("second") ?? -1))
        @Assert((out.indexOf("a.toml:1:9") ?? -1) < (out.indexOf("b.toml:2:5") ?? -1))
    }

    @TestCase
    public func headerLineFormat(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 2, endLine: 1, endColumn: 3)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c", source: "cjpm",
            message: "boom")
        let out = renderToString([d], CLIDiagnosticFace(color: Some(false)), None)
        @Assert(out.contains("boom"))
        @Assert(out.contains("a.toml:1:2"))
        @Assert(out.contains("error"))
    }

    @TestCase
    public func codeBlockWithCaretFromInlineSource(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 3, endLine: 2, endColumn: 5)),
            filename: "a.toml", severity: DiagnosticSeverity.Warning, code: "c", source: "cjpm",
            message: "m")
        let out = renderToString([d], CLIDiagnosticFace(color: Some(false)), Some("one\ntwo three\nfour"))
        @Assert(out.contains("two three"))
        @Assert(out.contains("^"))
    }

    @TestCase
    public func caretClampedToLineEnd(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 3, endLine: 2, endColumn: 99)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c", source: "cjpm",
            message: "m")
        let out = renderToString([d], CLIDiagnosticFace(color: Some(false)), Some("one\ntwo three\nfour"))
        @Assert(out.contains("two three"))
        @Assert(out.contains("^"))
    }

    @TestCase
    public func relatedInfoNote(): Unit {
        let rel = RelatedInfo(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2)),
            filename: "orig.toml", message: "previously declared here")
        let d = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m", relatedInfo: [rel])
        let out = renderToString([d], CLIDiagnosticFace(color: Some(false)), None)
        @Assert(out.contains("previously declared here"))
        @Assert(out.contains("orig.toml:1:1"))
    }

    @TestCase
    public func noCodeBlockWithoutRange(): Unit {
        let d = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = renderToString([d], CLIDiagnosticFace(color: Some(false)), Some("one\ntwo\nthree"))
        @Assert(!out.contains("^"))
    }

    @TestCase
    public func sortsByLineWithinSameFile(): Unit {
        let d1 = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 5, endLine: 2, endColumn: 6)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c1", source: "cjpm",
            message: "line two")
        let d2 = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 9, endLine: 1, endColumn: 10)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c2", source: "cjpm",
            message: "line one")
        let out = renderToString([d1, d2], CLIDiagnosticFace(color: Some(false)), None)
        @Assert((out.indexOf("line one") ?? -1) < (out.indexOf("line two") ?? -1))
    }

    @TestCase
    public func codeBlockReadFromDiskFallback(): Unit {
        let tmpDir = "/tmp/opencode/diag-test-files"
        if (!exists(tmpDir)) {
            Directory.create(tmpDir, recursive: true)
        }
        let tmpFile = "${tmpDir}/diag-file-fallback.toml"
        let f = File(tmpFile, Write)
        f.write("alpha\nbeta gamma\ndelta".toArray())
        f.close()
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 11)),
            filename: tmpFile, severity: DiagnosticSeverity.Error, code: "c", source: "cjpm",
            message: "m")
        let out = renderToString([d], CLIDiagnosticFace(color: Some(false)), None)   // no inline source: must read from disk
        @Assert(out.contains("beta gamma"))
        @Assert(out.contains("^"))
    }

    @TestCase
    public func caretCountIsClamped(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 3, endLine: 2, endColumn: 99)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c", source: "cjpm",
            message: "m")
        let out = renderToString([d], CLIDiagnosticFace(color: Some(false)), Some("one\ntwo three\nfour"))
        // clampedEnd = min(99, "two three".size + 1 = 10) = 10; count = 10 - 3 = 7
        let caretCount = out.split("^").size - 1
        @Assert(caretCount == 7)
    }

    @TestCase
    public func headerIncludesCode(): Unit {
        let d = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Error, code: "boom",
            source: "cjpm", message: "boom")
        let out = CLIDiagnosticFace(color: Some(false)).renderToString([d], None)
        @Assert(out.startsWith("error[boom]: boom"))
        @Assert(out.contains("\n  ==> a.toml\n"))
    }

    @TestCase
    public func emptyCodeLeavesBareHeader(): Unit {
        let d = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Warning, code: "",
            source: "cjpm", message: "m")
        let out = CLIDiagnosticFace(color: Some(false)).renderToString([d], None)
        @Assert(out.startsWith("warning: m"))
    }

    @TestCase
    public func multilineMessageContinuationAligned(): Unit {
        let d = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Error, code: "multiline-message",
            source: "cjpm", message: "first line\nsecond line\nthird line")
        let out = CLIDiagnosticFace(color: Some(false)).renderToString([d], None)
        // prefix "error[multiline-message]: " is 26 chars
        @Assert(out == "error[multiline-message]: first line\n                          second line\n                          third line\n  ==> a.toml\n")
    }

    @TestCase
    public func multilineNoteAligned(): Unit {
        let rel = RelatedInfo(range: None, filename: "o.toml", message: "p1\np2")
        let d = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m", relatedInfo: [rel])
        let out = CLIDiagnosticFace(color: Some(false)).renderToString([d], None)
        // "  = note: " is 9 chars
        @Assert(out == "error[c]: m\n  ==> a.toml\n  = note: p1: o.toml\n         p2\n")
    }

    @TestCase
    public func blankContextLinesRenderEmpty(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 2)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = CLIDiagnosticFace(color: Some(false)).renderToString([d], Some("\nERR\n"))
        @Assert(out == "error[c]: m\n ==> a.toml:2:1\n  | \n2 | ERR\n  | ^\n  | \n")
    }

    @TestCase
    public func tabsExpandedForAlignment(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 3, endLine: 1, endColumn: 4)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = CLIDiagnosticFace(color: Some(false)).renderToString([d], Some("a\tb"))
        // "a\tb" expands to "a       b" (tab at column 1 advances to the
        // next stop of 8); caret at byte col 3 → display col 8, under 'b'.
        @Assert(out == "error[c]: m\n ==> a.toml:1:3\n1 | a       b\n  |         ^\n")
    }

    @TestCase
    public func longLineTruncatedWithEllipsis(): Unit {
        // 60-char line; maxWidth 40 → budget 36 (line number width 1)
        let long = "012345678901234567890123456789012345678901234567890123456789"
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 3, endLine: 1, endColumn: 4)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = CLIDiagnosticFace(maxWidth: Some(40), color: Some(false)).renderToString([d], Some(long))
        // caret at display col 2 → no shift; keep = 36-3 = 33 chars + "..."
        @Assert(out == "error[c]: m\n ==> a.toml:1:3\n1 | 012345678901234567890123456789012...\n  |   ^\n")
    }

    @TestCase
    public func caretBeyondWindowShiftsLeft(): Unit {
        let long = "012345678901234567890123456789012345678901234567890123456789"
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 60, endLine: 1, endColumn: 61)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = CLIDiagnosticFace(maxWidth: Some(40), color: Some(false)).renderToString([d], Some(long))
        // Caret at col 59 (near the end of a 60-col line) at budget 36:
        // left context outranks right — the window fills with as much
        // prefix as fits ("..." + 33 digits), span in full at the end,
        // no right ellipsis (nothing follows), exactly one caret.
        println(out)
        @Assert(out.contains("1 | ..."))
        @Assert(out.contains("012345678901234567890123456789"))
        @Assert(out.split("^").size - 1 == 1)
    }

    @TestCase
    public func degenerateNarrowWidthRenders(): Unit {
        let long = "012345678901234567890123456789012345678901234567890123456789"
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 2, endLine: 1, endColumn: 3)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = CLIDiagnosticFace(maxWidth: Some(5), color: Some(false)).renderToString([d], Some(long))
        @Assert(out.contains(" ==> a.toml:1:2"))   // header/locator never truncated
        @Assert(out.contains("1 |"))                 // frame still rendered (degenerate floor)
    }

    @TestCase
    public func multiTabCaretAlignment(): Unit {
        // "a\tb\tc" → tab-stop expansion "a       b       c"; caret covers
        // 'b' (byte cols 2..3 → display col 8), sitting under 'b'.
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 3, endLine: 1, endColumn: 4)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = CLIDiagnosticFace(color: Some(false)).renderToString([d], Some("a\tb\tc"))
        @Assert(out == "error[c]: m\n ==> a.toml:1:3\n1 | a       b       c\n  |         ^\n")
    }
}

@Test
public class JsonRpcFaceTest {
    @TestCase
    public func singleFileNotification(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 3, startColumn: 2, endLine: 3, endColumn: 4)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "type-error", source: "cjpm",
            message: "bad")
        let out = JsonRpcDiagnosticFace().renderToString([diag], None)
        @Assert(out.contains("\"method\": \"textDocument/publishDiagnostics\""))
        @Assert(out.contains("\"severity\": 1"))
        @Assert(out.contains("\"line\": 2"))          // 0-based conversion of 3
        @Assert(out.contains("\"character\": 1"))     // 0-based conversion of 2
        @Assert(!out.startsWith("["))                 // single file: no array wrapper
    }

    @TestCase
    public func multipleFilesAreGroupedInArray(): Unit {
        let d1 = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Warning, code: "w",
            source: "cjpm", message: "m1")
        let d2 = Diagnostic(
            range: None, filename: "b.toml", severity: DiagnosticSeverity.Hint, code: "h",
            source: "cjpm", message: "m2")
        let out = JsonRpcDiagnosticFace().renderToString([d1, d2], None)
        @Assert(out.startsWith("["))
        @Assert(out.endsWith("]"))
        @Assert(out.contains("file:///"))
    }

    @TestCase
    public func relatedInformationEmitted(): Unit {
        let rel = RelatedInfo(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2)),
            filename: "b.toml", message: "prev")
        let diag = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m", relatedInfo: [rel])
        let out = JsonRpcDiagnosticFace().renderToString([diag], None)
        @Assert(out.contains("relatedInformation"))
        @Assert(out.contains("prev"))
    }

    @TestCase
    public func zeroRangeWhenNoRange(): Unit {
        let diag = Diagnostic(
            range: None, filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = JsonRpcDiagnosticFace().renderToString([diag], None)
        @Assert(out.contains("\"line\": 0"))
        @Assert(out.contains("\"character\": 0"))
    }

    @TestCase
    public func testCanonicalPathExistingFile(): Unit {
        let tmpDir = "/tmp/opencode/diag-test-files-uri"
        if (!exists(tmpDir)) {
            Directory.create(tmpDir, recursive: true)
        }
        let tmpFile = "${tmpDir}/diag-file-uri.toml"
        let f = File(tmpFile, Write)
        f.write("alpha\nbeta gamma\ndelta".toArray())
        f.close()
        let d = Diagnostic(
            range: None, filename: tmpFile, severity: DiagnosticSeverity.Error, code: "c",
            source: "cjpm", message: "m")
        let out = JsonRpcDiagnosticFace().renderToString([d], None)
        let canonical = canonicalize(Path(tmpFile)).toString()
        @Assert(canonical != "")
        @Assert(out.contains("file://${canonical}"))
        @Assert(!out.contains("\"uri\": \"file:///\""))
    }
}

@Test
public class LogLevelTest {
    @TestCase
    public func severityToLogLevelMapping(): Unit {
        @Assert(match (DiagnosticSeverity.Error.toLogLevel()) { case LogLevel.Error => true case _ => false })
        @Assert(match (DiagnosticSeverity.Warning.toLogLevel()) { case LogLevel.Warning => true case _ => false })
        @Assert(match (DiagnosticSeverity.Information.toLogLevel()) { case LogLevel.Info => true case _ => false })
        @Assert(match (DiagnosticSeverity.Hint.toLogLevel()) { case LogLevel.Debug => true case _ => false })
    }

    @TestCase
    public func filterKeepsAtOrAboveLevel(): Unit {
        let e = Diagnostic(range: None, filename: "a.toml", severity: DiagnosticSeverity.Error,
            code: "e", source: "s", message: "e")
        let w = Diagnostic(range: None, filename: "a.toml", severity: DiagnosticSeverity.Warning,
            code: "w", source: "s", message: "w")
        let i = Diagnostic(range: None, filename: "a.toml", severity: DiagnosticSeverity.Information,
            code: "i", source: "s", message: "i")
        let h = Diagnostic(range: None, filename: "a.toml", severity: DiagnosticSeverity.Hint,
            code: "h", source: "s", message: "h")
        let all = [e, w, i, h]

        @Assert(filterDiagnostics(all, LogLevel.Error).size == 4)
        @Assert(filterDiagnostics(all, LogLevel.Warning).size == 3)
        @Assert(filterDiagnostics(all, LogLevel.Info).size == 2)
        @Assert(filterDiagnostics(all, LogLevel.Debug).size == 1)
    }

    @TestCase
    public func filterPreservesOrder(): Unit {
        let w = Diagnostic(range: None, filename: "a.toml", severity: DiagnosticSeverity.Warning,
            code: "w1", source: "s", message: "w1")
        let h = Diagnostic(range: None, filename: "a.toml", severity: DiagnosticSeverity.Hint,
            code: "h1", source: "s", message: "h1")
        let e = Diagnostic(range: None, filename: "a.toml", severity: DiagnosticSeverity.Error,
            code: "e1", source: "s", message: "e1")
        let filtered = filterDiagnostics([w, h, e], LogLevel.Warning)
        @Assert(filtered.size == 2)
        @Assert(filtered[0].code == "w1")
        @Assert(filtered[1].code == "h1")
    }
}

@Test
public class LogFaceTest {
    @TestCase
    public func singleLineFormat(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 12, startColumn: 3, endLine: 12, endColumn: 5)),
            filename: "src/main.cj", severity: DiagnosticSeverity.Error, code: "missing-return",
            source: "cjpm", message: "missing return")
        @Assert(LogDiagnosticFace().renderToString([d], None) == "[error] missing-return: missing return (src/main.cj:12:3)")
    }

    @TestCase
    public func emptyCodeOmitted(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2)),
            filename: "f", severity: DiagnosticSeverity.Warning, code: "", source: "s", message: "m")
        @Assert(LogDiagnosticFace().renderToString([d], None) == "[warning] m (f:1:1)")
    }

    @TestCase
    public func noRangeOmitsLocation(): Unit {
        let d = Diagnostic(
            range: None, filename: "f", severity: DiagnosticSeverity.Information, code: "x",
            source: "s", message: "m")
        @Assert(LogDiagnosticFace().renderToString([d], None) == "[info] x: m")
    }

    @TestCase
    public func multilineMessageCollapsed(): Unit {
        let d = Diagnostic(
            range: None, filename: "f", severity: DiagnosticSeverity.Error, code: "c",
            source: "s", message: "line1\nline2\nline3")
        @Assert(LogDiagnosticFace().renderToString([d], None) == "[error] c: line1 | line2 | line3")
    }

    @TestCase
    public func relatedInfoAppendedInline(): Unit {
        let rel = RelatedInfo(
            range: Some(DiagnosticRange(startLine: 3, startColumn: 1, endLine: 3, endColumn: 2)),
            filename: "other.cj", message: "prev")
        let d = Diagnostic(
            range: None, filename: "f", severity: DiagnosticSeverity.Warning, code: "w",
            source: "s", message: "m", relatedInfo: [rel])
        @Assert(LogDiagnosticFace().renderToString([d], None) == "[warning] w: m ; note: prev (other.cj:3:1)")
    }

    @TestCase
    public func multipleNotesJoinedWithPipe(): Unit {
        let rel1 = RelatedInfo(range: None, filename: "a.cj", message: "n1")
        let rel2 = RelatedInfo(range: None, filename: "b.cj", message: "n2")
        let d = Diagnostic(
            range: None, filename: "f", severity: DiagnosticSeverity.Error, code: "e",
            source: "s", message: "m", relatedInfo: [rel1, rel2])
        @Assert(LogDiagnosticFace().renderToString([d], None) == "[error] e: m ; note: n1 (a.cj) | note: n2 (b.cj)")
    }

    @TestCase
    public func inputOrderPreserved(): Unit {
        let d2 = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 2)),
            filename: "f", severity: DiagnosticSeverity.Warning, code: "w", source: "s", message: "second")
        let d1 = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2)),
            filename: "f", severity: DiagnosticSeverity.Error, code: "e", source: "s", message: "first")
        let out = LogDiagnosticFace().renderToString([d2, d1], None)
        @Assert((out.indexOf("second") ?? -1) < (out.indexOf("first") ?? -1))
    }
}

@Test
public class WidthResolveTest {
    @TestCase
    public func fairMinOfAllConstraints(): Unit {
        @Assert(resolveWidth(Some(40), Some(100), Some("50")) == 40)
        @Assert(resolveWidth(Some(100), Some(60), Some("50")) == 50)
        @Assert(resolveWidth(Some(100), Some(40), Some("50")) == 40)
        @Assert(resolveWidth(Some(100), Some(60), None) == 60)
        @Assert(resolveWidth(Some(100), None, Some("40")) == 40)
    }

    @TestCase
    public func noPriorityBetweenTtyAndColumns(): Unit {
        @Assert(resolveWidth(None, Some(100), Some("50")) == 50)
        @Assert(resolveWidth(None, Some(40), Some("100")) == 40)
        @Assert(resolveWidth(None, Some(0), Some("50")) == 50)
        @Assert(resolveWidth(None, Some(100), Some("0")) == 100)
    }

    @TestCase
    public func explicitUsedWhenNoEnv(): Unit {
        @Assert(resolveWidth(Some(40), None, None) == 40)
        @Assert(resolveWidth(Some(0), None, None) == 80)
        @Assert(resolveWidth(Some(-5), None, None) == 80)
    }

    @TestCase
    public func invalidConstraintsIgnored(): Unit {
        @Assert(resolveWidth(None, None, Some("not-a-number")) == 80)
        @Assert(resolveWidth(None, None, Some("0")) == 80)
        @Assert(resolveWidth(None, None, Some("-3")) == 80)
        @Assert(resolveWidth(None, None, None) == 80)
        @Assert(resolveWidth(Some(40), None, Some("not-a-number")) == 40)
    }
}

@Test
public class ColorResolveTest {
    @TestCase
    public func defaultsOn(): Unit {
        @Assert(resolveColor(None, None, None, None, None))
    }

    @TestCase
    public func envDisables(): Unit {
        @Assert(!resolveColor(None, Some("1"), None, None, None))
        @Assert(!resolveColor(None, Some("1"), Some("dumb"), None, None))
        @Assert(!resolveColor(None, None, Some("dumb"), None, None))
    }

    @TestCase
    public func envEmptyMeansUnset(): Unit {
        // "Empty variables are treated as though they were unset."
        @Assert(resolveColor(None, Some(""), None, None, None))
        @Assert(resolveColor(None, None, None, Some(""), None))
        @Assert(resolveColor(None, None, None, None, Some("")))
    }

    @TestCase
    public func envBeatsSource(): Unit {
        @Assert(!resolveColor(Some(true), Some("1"), None, None, None))
        @Assert(!resolveColor(Some(true), Some("1"), Some("dumb"), None, None))
    }

    @TestCase
    public func sourceUsedWhenNoEnv(): Unit {
        @Assert(resolveColor(Some(true), None, None, None, None))
        @Assert(!resolveColor(Some(false), None, None, None, None))
    }

    @TestCase
    public func nocolorBeatsForce(): Unit {
        // Spec order: "CLICOLOR_FORCE set, BUT NO_COLOR UNSET". NO_COLOR wins.
        @Assert(!resolveColor(None, Some("1"), None, Some("1"), None))
        @Assert(!resolveColor(Some(false), Some("1"), Some("dumb"), Some("yes"), None))
    }

    @TestCase
    public func forceBeatsOtherDisablers(): Unit {
        @Assert(resolveColor(Some(false), None, Some("dumb"), Some("1"), None))
        @Assert(resolveColor(Some(false), None, None, Some("yes"), None))
        @Assert(resolveColor(Some(false), None, None, Some("1"), Some("0")))
    }

    @TestCase
    public func clicolorZeroDisables(): Unit {
        // GNU convention (matches GCC / anstyle-query): CLICOLOR=0 is off.
        @Assert(!resolveColor(Some(true), None, None, None, Some("0")))
        @Assert(!resolveColor(None, None, None, None, Some("0")))
    }

    @TestCase
    public func clicolorAffirmativeCollapsesToDefault(): Unit {
        // Without tty sensing, the tty-gated enable form equals our
        // default-on; pinned so a future tty hook lands consciously.
        // It does not resurrect color on TERM=dumb.
        @Assert(resolveColor(None, None, None, None, Some("1")))
        @Assert(!resolveColor(None, None, Some("dumb"), None, Some("1")))
    }

    @TestCase
    public func forceOnlyNonEmptyNonZero(): Unit {
        // Empty and "0" do not count as set; old rules apply.
        @Assert(!resolveColor(Some(false), None, None, Some(""), None))
        @Assert(!resolveColor(Some(false), None, None, Some("0"), None))
        @Assert(!resolveColor(None, Some("1"), None, Some(""), None))
    }
}

// ---- Display width / text measurement ----

@Test
public class TextWidthTest {
    private func runeOf(s: String): Rune {
        match (s.runes().next()) {
            case Some(r) => r
            case None => throw Exception("empty string")
        }
    }

    private func runeWidth(r: Rune): Int64 {
        runeWidthCp(UInt32(r))
    }

    @TestCase
    public func asciiIsOneColumn(): Unit {
        @Assert(runeWidth(runeOf("a")) == 1)
        @Assert(runeWidth(runeOf(" ")) == 1)
    }

    @TestCase
    public func fullWidthIsTwoColumns(): Unit {
        @Assert(runeWidth(runeOf("中")) == 2)
        @Assert(runeWidth(runeOf("文")) == 2)
        @Assert(runeWidth(runeOf("가")) == 2)
        @Assert(runeWidth(runeOf("Ａ")) == 2)
    }

    @TestCase
    public func ambiguousIsHalf(): Unit {
        @Assert(runeWidth(runeOf("±")) == 1)
    }

    @TestCase
    public func displayWidthSumsRunes(): Unit {
        @Assert(displayWidth("") == 0)
        @Assert(displayWidth("ab") == 2)
        @Assert(displayWidth("中文") == 4)
        @Assert(displayWidth("a中b") == 4)
    }

    @TestCase
    public func displayColAtByteMapsWideChars(): Unit {
        @Assert(displayColAtByte("中文", 0) == 0)
        @Assert(displayColAtByte("中文", 3) == 2)
        @Assert(displayColAtByte("中文", 6) == 4)
    }

    @TestCase
    public func displayColClampsOutOfRange(): Unit {
        @Assert(displayColAtByte("ab", 99) == 2)
        @Assert(displayColAtByte("ab", -5) == 0)
    }

    @TestCase
    public func tabAdvancesToNextStop(): Unit {
        @Assert(displayColAtByte("\t", 1) == 8)
        @Assert(displayColAtByte("ab\tc", 3) == 8)
    }

    @TestCase
    public func byteAtDisplayColRoundTrip(): Unit {
        @Assert(byteAtDisplayCol("abc", 0) == 0)
        @Assert(byteAtDisplayCol("abc", 2) == 2)
        @Assert(byteAtDisplayCol("中文", 2) == 3)
        @Assert(byteAtDisplayCol("abc", 99) == 3)
    }

    @TestCase
    public func byteAtDisplayColFloorsInsideWideChar(): Unit {
        @Assert(byteAtDisplayCol("中文", 3) == 3)
    }
}

@Test
public class WindowLineTest {
    private func repeated(s: String, n: Int64): String {
        var out = ""
        for (_ in 0..n) { out += s }
        out
    }

    private func cjkLine(n: Int64): String {
        repeated("中", n)
    }

    @TestCase
    public func shortLineUnchanged(): Unit {
        let (t, s, l) = windowLine("abc", 10, Some(2), 1)
        @Assert(t == "abc")
        @Assert(s == 2)
        @Assert(l == 1)
    }

    @TestCase
    public func noCaretTruncatesWithEllipsis(): Unit {
        let (t, _, _) = windowLine(repeated("a", 50), 20, None, 0)
        @Assert(t.endsWith("..."))
        @Assert(t.size == 20)
    }

    @TestCase
    public func wideCharsNeverSplitOnTruncate(): Unit {
        let line = cjkLine(30)
        let (t, _, _) = windowLine(line, 20, None, 0)
        @Assert(String.fromUtf8(t.toArray()) == t)
        @Assert(displayWidth(t) <= 20)
    }

    @TestCase
    public func wideCharsNeverSplitOnShift(): Unit {
        // caret deep inside a CJK line forces the window to shift
        let line = cjkLine(30)
        let (t, s, l) = windowLine(line, 20, Some(40), 2)
        @Assert(String.fromUtf8(t.toArray()) == t)
        @Assert(s >= 0)
        @Assert(l >= 1)
    }

    @TestCase
    public func caretStaysVisibleAfterFold(): Unit {
        let line = repeated("ab", 10)
        let (t, s, l) = windowLine(line, 10, Some(18), 2)
        // Degenerate max-shift clamp: a caret in the final columns of an
        // over-long line lands at the end of the visible text (pre-existing
        // behavior). Invariant: it is never rendered beyond the text area.
        @Assert(s <= displayWidth(t))
        @Assert(l >= 1)
    }
}

// Pins the deterministic window allocator (see docs/superpowers/specs/
// 2026-08-21-window-right-fill-design.md): span full first, passive right
// fill up to RIGHT_FILL_MAX bounded by the LEFT_KEEP_MIN left floor,
// overflow trims left only down to SPAN_KEEP_MIN visible span columns.
@Test
public class WindowRightFillTest {
    private func repeated(s: String, n: Int64): String {
        var out = ""
        for (_ in 0..n) { out += s }
        out
    }

    // 200-col line: 95 pad, SPAN!, 100 pad. bg=56 -> both ellipses; the
    // right side totals RIGHT_FILL_MAX including its "..." (7 cols + ...).
    @TestCase
    public func rightContextAppearsWhenSpanFits(): Unit {
        let line = repeated("x", 95) + "SPAN!" + repeated("x", 100)
        let (disp, ws, left, right, keep) = windowLineGeom(line, 56, Some(95), 5)
        @Assert(left)
        @Assert(right)
        @Assert(ws == 57)
        @Assert(keep == 50)
        @Assert(disp == "..." + repeated("x", 38) + "SPAN!" + repeated("x", 7) + "...")
    }

    // 200-col line: 40 pad, 33-col span, 127 pad. Filling right to the cap
    // would drop left below LEFT_KEEP_MIN, so right settles for the rest.
    @TestCase
    public func leftFloorLimitsRightFill(): Unit {
        let line = repeated("x", 40) + repeated("M", 33) + repeated("x", 127)
        let (disp, ws, left, right, keep) = windowLineGeom(line, 56, Some(40), 33)
        @Assert(left)
        @Assert(right)
        @Assert(ws == 30)
        @Assert(keep == 50)
        @Assert(disp == "..." + repeated("x", 10) + repeated("M", 33) + repeated("x", 7) + "...")
    }

    // Left context smaller than the cap is shown in full; right then fills
    // past the cap because nothing else can consume the space.
    @TestCase
    public func smallLeftShownFullyAndRightContinues(): Unit {
        let line = repeated("x", 7) + repeated("S", 33) + repeated("x", 160)
        let (disp, _, left, right, keep) = windowLineGeom(line, 56, Some(7), 33)
        @Assert(!left)
        @Assert(right)
        @Assert(keep == 53)
        @Assert(disp == repeated("x", 7) + repeated("S", 33) + repeated("x", 13) + "...")
    }

    // Span alone exceeds the window: right reclaims first, then left caps
    // at its ellipsis-inclusive share of LEFT_KEEP_MIN while the span takes
    // everything else.
    @TestCase
    public func overflowCapsLeftAndMaximizesSpan(): Unit {
        let line = repeated("x", 60) + repeated("H", 100) + repeated("x", 40)
        let (disp, ws, left, right, _) = windowLineGeom(line, 36, Some(60), 100)
        @Assert(left)
        @Assert(right)
        @Assert(ws == 53)
        @Assert(disp == "..." + repeated("x", 7) + repeated("H", 23) + "...")
        let (_, s, l) = windowLine(line, 36, Some(60), 100)
        @Assert(s == 10)
        @Assert(l == 26)
    }

    // Left context smaller than the overflow cap survives intact.
    @TestCase
    public func overflowKeepsSmallLeftIntact(): Unit {
        let line = repeated("x", 7) + repeated("H", 100) + repeated("x", 93)
        let (disp, _, left, right, _) = windowLineGeom(line, 36, Some(7), 100)
        @Assert(!left)
        @Assert(right)
        @Assert(disp == repeated("x", 7) + repeated("H", 26) + "...")
    }

    // No content after the span: right fill has nothing to show, no right
    // ellipsis beyond the line-end cut.
    @TestCase
    public func noPostSpanShowsNoRightEllipsis(): Unit {
        let line = repeated("x", 170) + repeated("E", 30)
        let (disp, _, left, right, _) = windowLineGeom(line, 56, Some(170), 30)
        @Assert(left)
        @Assert(!right)
        @Assert(disp == "..." + repeated("x", 23) + repeated("E", 30))
    }

    // Post-span exactly equal to the cap: shown whole, no right ellipsis.
    @TestCase
    public func rightFillExactlyAtCapOmitsEllipsis(): Unit {
        let line = repeated("x", 95) + repeated("S", 5) + repeated("x", 10)
        let (disp, _, left, right, _) = windowLineGeom(line, 56, Some(95), 5)
        @Assert(left)
        @Assert(!right)
        @Assert(disp == "..." + repeated("x", 38) + repeated("S", 5) + repeated("x", 10))
    }

    // Extreme budget: a span anchored past end-of-line must not throw and
    // must still produce a valid, non-empty window (showcase d2 at
    // COLUMNS=5 degraded to the safety fallback before).
    @TestCase
    public func spanBeyondLineEndTinyBudgetDoesNotThrow(): Unit {
        let line = repeated("x", 30)
        let (disp, ws, left, right, keep) = windowLineGeom(line, 1, Some(76), 9)
        @Assert(ws >= 0 && keep >= 0)
        @Assert(disp != "")
        let (_, s, l) = windowLine(line, 1, Some(76), 9)
        @Assert(s >= 0)
        @Assert(l >= 1)
    }

    // Extreme budget: an anchored window landing on a wide CJK character
    // must never slice through UTF-8 continuation bytes.
    @TestCase
    public func cjkWindowTinyBudgetStaysOnCharBoundaries(): Unit {
        let line = "中文中文中文中文"
        let (disp, _, _, _, _) = windowLineGeom(line, 1, Some(3), 2)
        var i: Int64 = 0
        var chars: Int64 = 0
        while (i < disp.size) {
            let (_, len) = decodeCp(disp.toArray(), i)
            i += len
            chars += 1
        }
        @Assert(i == disp.size)
        @Assert(chars >= 1)
    }

    // Regression: showcase d2 (span past EOL on a CJK-heavy line) degraded
    // to the bare "warning: message" fallback at maxWidth=5, meaning
    // rendering threw internally. A real frame must still be produced.
    @TestCase
    public func extremeTinyWidthLegacyFrameStillRenders(): Unit {
        let src = "func 查找用户(id: Int64): ?String {\n" +
            "    if (id <= 0) { return None }\n" +
            "    return Some(\"用户-\" + id.toString())\n" +
            "}\n" +
            "println(\"欢迎, \" + 查找用户(42))\n" +
            "// TODO: 迁移完成后删除这段兼容代码 remove this shim after the migration completes 测试测试测试测试\n"
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 6, startColumn: 77, endLine: 6, endColumn: 86)),
            filename: "报表.cj",
            severity: DiagnosticSeverity.Warning,
            code: "line-too-long",
            source: "example",
            message: "line exceeds the display budget"
        )
        let out = CLIDiagnosticFace(maxWidth: Some(5), color: Some(false)).renderToString([d], Some(src))
        @Assert(out.contains("line-too-long"))
        @Assert(out.contains("==>"))
        @Assert(out.contains("^"))
    }

    // Regression: at maxWidth=3 the per-line byte cap (maxWidth*20 = 60)
    // chopped the source line BEFORE the labeled column, so the window
    // degraded to bare "..." with a stray caret. The cap must keep whole
    // spans of realistic sources loadable.
    @TestCase
    public func extremeTinyWidthReadCapKeepsSpanRegion(): Unit {
        let src = "func 查找用户(id: Int64): ?String {\n" +
            "    if (id <= 0) { return None }\n" +
            "    return Some(\"用户-\" + id.toString())\n" +
            "}\n" +
            "println(\"欢迎, \" + 查找用户(42))\n" +
            "// TODO: 迁移完成后删除这段兼容代码 remove this shim after the migration completes 测试测试测试测试\n"
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 6, startColumn: 77, endLine: 6, endColumn: 86)),
            filename: "报表.cj",
            severity: DiagnosticSeverity.Warning,
            code: "line-too-long",
            source: "example",
            message: "line exceeds the display budget"
        )
        let out = CLIDiagnosticFace(maxWidth: Some(3), color: Some(false)).renderToString([d], Some(src))
        @Assert(out.contains("m..."))
        @Assert(out.contains("^^^^"))
    }
}

@Test
public class ExpandTabsTest {
    @TestCase
    public func noTabsUnchanged(): Unit {
        @Assert(expandTabs("abc") == "abc")
    }

    @TestCase
    public func tabAtStartGoesToFirstStop(): Unit {
        @Assert(expandTabs("\ta") == "        a")
    }

    @TestCase
    public func tabAdvancesToNextMultipleOfEight(): Unit {
        @Assert(expandTabs("ab\tc") == "ab      c")
    }

    @TestCase
    public func tabsPreserveDisplayColumns(): Unit {
        let raw = "ab\t中\tc"
        let exp = expandTabs(raw)
        @Assert(displayWidth(exp) == displayColAtByte(raw, raw.size))
    }
}

// ---- Label styling ----

@Test
public class LabelStyleTest {
    private func twoLabelDiag(): Diagnostic {
        Diagnostic(
            range: None,
            filename: "f.cj",
            severity: DiagnosticSeverity.Error,
            code: "demo",
            source: "t",
            message: "m",
            labels: [
                Label(
                    range: DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2),
                    filename: "f.cj",
                    message: "primary here"
                ),
                Label(
                    range: DiagnosticRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 2),
                    filename: "f.cj",
                    message: "secondary here",
                    style: Some(LabelStyle.Secondary)
                )
            ]
        )
    }

    @TestCase
    public func primaryStaysRed(): Unit {
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
            .renderToString([twoLabelDiag()], Some("aaaa\nbbbb\n"))
        @Assert(out.contains("\u{1B}[31m^ primary here"))
    }

    @TestCase
    public func secondaryRendersBlue(): Unit {
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
            .renderToString([twoLabelDiag()], Some("aaaa\nbbbb\n"))
        @Assert(out.contains("\u{1B}[34m^ secondary here"))
    }

    @TestCase
    public func labelMessageSharesCaretColor(): Unit {
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
            .renderToString([twoLabelDiag()], Some("aaaa\nbbbb\n"))
        // The whole label run — carets AND message — carries the label color.
        @Assert(out.contains("\u{1B}[31m^ primary here\u{1B}[0m"))
        @Assert(out.contains("\u{1B}[34m^ secondary here\u{1B}[0m"))
    }

    @TestCase
    public func unstyledLabelsKeepLegacyRed(): Unit {
        let d = Diagnostic(
            range: None,
            filename: "f.cj",
            severity: DiagnosticSeverity.Error,
            code: "demo",
            source: "t",
            message: "m",
            labels: [
                Label(
                    range: DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2),
                    filename: "f.cj",
                    message: "plain"
                )
            ]
        )
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
            .renderToString([d], Some("aaaa\n"))
        @Assert(out.contains("\u{1B}[31m^ plain"))
        @Assert(!out.contains("\u{1B}[34m^"))
    }
}

// ---- Golden test harness ----
private func goldenPath(name: String): String {
    let dir = "testdata"
    if (!exists(dir)) {
        Directory.create(dir, recursive: true)
    }
    "${dir}/${name}.golden"
}

// Compares actual output against <name>.golden; rewrites the golden file when
// UPDATE_GOLDEN=1 (used once to generate, then re-run without it).
private func assertGolden(actual: String, name: String): Unit {
    let path = goldenPath(name)
    let updating = match (getVariable("UPDATE_GOLDEN")) {
        case Some(v) => v == "1"
        case None => false
    }
    if (updating) {
        let f = File(path, Write)
        f.write(actual.toArray())
        f.close()
        return
    }
    let expected = String.fromUtf8(File.readFrom(path))
    if (expected != actual) {
        // Render a compact diff by line for debuggability.
        let es = expected.split("\n")
        let as_ = actual.split("\n")
        let maxLen = if (es.size > as_.size) { es.size } else { as_.size }
        for (i in 0..maxLen) {
            let e = if (i < es.size) { es[i] } else { "<eof>" }
            let a = if (i < as_.size) { as_[i] } else { "<eof>" }
            if (e != a) {
                println("golden line ${i}: expected=[${e}] actual=[${a}]")
            }
        }
        println("GOLDEN MISMATCH: ${name}")
        @Assert(false)
    }
}

private func goldenDiag(
    severity: DiagnosticSeverity,
    code: String,
    message: String
): Diagnostic {
    Diagnostic(range: None, filename: "golden.toml", severity: severity, code: code,
        source: "cjpm", message: message)
}

private func goldenDiag(
    severity: DiagnosticSeverity,
    code: String,
    message: String,
    range: ?DiagnosticRange
): Diagnostic {
    Diagnostic(range: range, filename: "golden.toml", severity: severity, code: code,
        source: "cjpm", message: message)
}

private func goldenDiag(
    severity: DiagnosticSeverity,
    code: String,
    message: String,
    range: ?DiagnosticRange,
    related: Array<RelatedInfo>
): Diagnostic {
    Diagnostic(range: range, filename: "golden.toml", severity: severity, code: code,
        source: "cjpm", message: message, relatedInfo: related)
}

@Test
public class GoldenTest {
    @TestCase
    public func cliBasic(): Unit {
        let d = goldenDiag(DiagnosticSeverity.Error, "boom", "boom",
            Some(DiagnosticRange(startLine: 3, startColumn: 2, endLine: 3, endColumn: 6)))
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false))
            .renderToString([d], Some("one\ntwo three\nfour five"))
        assertGolden(out, "cli_basic")
    }

    @TestCase
    public func cliMultiline(): Unit {
        let d = goldenDiag(DiagnosticSeverity.Error, "multiline-message", "first line\nsecond line",
            Some(DiagnosticRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 4)))
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false))
            .renderToString([d], Some("one\ntwo three\nfour"))
        assertGolden(out, "cli_multiline")
    }

    @TestCase
    public func cliNoRange(): Unit {
        let d = goldenDiag(DiagnosticSeverity.Warning, "no-location", "no location")
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false)).renderToString([d], None)
        assertGolden(out, "cli_norange")
    }

    @TestCase
    public func cliMissingFile(): Unit {
        // both point at a file that never exists → no code frame
        let d = goldenDiag(DiagnosticSeverity.Error, "missing-source", "missing src",
            Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2)))
        let d2 = goldenDiag(DiagnosticSeverity.Error, "missing-source", "missing src 2",
            Some(DiagnosticRange(startLine: 7, startColumn: 2, endLine: 7, endColumn: 3)))
        let arr = ArrayList<Diagnostic>()
        arr.add(Diagnostic(range: d.range, filename: "no_such_file_xyz.toml",
            severity: d.severity, code: d.code, source: d.source, message: d.message))
        arr.add(Diagnostic(range: d2.range, filename: "no_such_file_xyz.toml",
            severity: d2.severity, code: d2.code, source: d2.source, message: d2.message))
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false)).renderToString(arr.toArray(), None)
        assertGolden(out, "cli_missing_file")
    }

    @TestCase
    public func cliRelated(): Unit {
        let rel = RelatedInfo(range: None, filename: "other.toml", message: "see here")
        let d = goldenDiag(DiagnosticSeverity.Error, "conflict", "conflict",
            Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2)),
            [rel])
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false))
            .renderToString([d], Some("alpha\nbeta"))
        assertGolden(out, "cli_related")
    }

    @TestCase
    public func cliTabs(): Unit {
        let d = goldenDiag(DiagnosticSeverity.Warning, "tab-alignment", "tab alignment",
            Some(DiagnosticRange(startLine: 1, startColumn: 3, endLine: 1, endColumn: 4)))
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false))
            .renderToString([d], Some("a\tb\nc\td\nef"))
        assertGolden(out, "cli_tabs")
    }

    @TestCase
    public func cliCjkCaret(): Unit {
        // Caret spans a full-width character: 2 carets under 中, aligned
        // with its 2 display columns (3 bytes → 2 cells).
        let d = goldenDiag(DiagnosticSeverity.Error, "wide-char", "wide char",
            Some(DiagnosticRange(startLine: 1, startColumn: 4, endLine: 1, endColumn: 7)))
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false))
            .renderToString([d], Some("ab中文cd\nplain"))
        assertGolden(out, "cli_cjk_caret")
    }

    @TestCase
    public func cliCjkWindowShift(): Unit {
        // 30 CJK chars = 60 display columns; caret deep inside forces the
        // window to shift. Slicing must land on character boundaries — the
        // output stays valid UTF-8 with no mojibake.
        let line = "中中中中中中中中中中中中中中中中中中中中中中中中中中中中中中"
        let d = goldenDiag(DiagnosticSeverity.Error, "shifted-window", "shifted window",
            Some(DiagnosticRange(startLine: 1, startColumn: 40, endLine: 1, endColumn: 43)))
        let out = CLIDiagnosticFace(maxWidth: Some(40), color: Some(false))
            .renderToString([d], Some(line))
        assertGolden(out, "cli_cjk_shift")
    }

    @TestCase
    public func cliMultiLabelNarrowWindow(): Unit {
        // Multi-label rendering must window long lines to the budget (matching
        // the legacy single-range path) and keep the label message in full
        // even when it runs past the right edge.
        let line = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
        let d = Diagnostic(
            range: None, filename: "golden.toml", severity: DiagnosticSeverity.Error,
            code: "narrow-multi-label", source: "cjpm", message: "mismatch",
            labels: [
                Label(
                    range: DiagnosticRange(startLine: 1, startColumn: 40, endLine: 1, endColumn: 45),
                    filename: "golden.toml",
                    message: "expected String, found ?String"
                )
            ]
        )
        let out = CLIDiagnosticFace(maxWidth: Some(30), color: Some(false))
            .renderToString([d], Some(line))
        assertGolden(out, "cli_multi_label_narrow")
    }

    @TestCase
    public func cliWide40(): Unit {
        let long = "012345678901234567890123456789012345678901234567890123456789"
        let d = goldenDiag(DiagnosticSeverity.Error, "wide-line", "wide",
            Some(DiagnosticRange(startLine: 1, startColumn: 60, endLine: 1, endColumn: 61)))
        let out = CLIDiagnosticFace(maxWidth: Some(40), color: Some(false))
            .renderToString([d], Some(long))
        assertGolden(out, "cli_wide40")
    }

    @TestCase
    public func cliShifted(): Unit {
        let long = "012345678901234567890123456789012345678901234567890123456789"
        let d = goldenDiag(DiagnosticSeverity.Error, "shifted-caret", "shifted caret",
            Some(DiagnosticRange(startLine: 1, startColumn: 3, endLine: 1, endColumn: 4)))
        let out = CLIDiagnosticFace(maxWidth: Some(40), color: Some(false))
            .renderToString([d], Some(long))
        assertGolden(out, "cli_shifted")
    }

    @TestCase
    public func cliPlainAndColor(): Unit {
        let d = goldenDiag(DiagnosticSeverity.Hint, "colored-hint", "colored",
            Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 3)))
        let d2 = goldenDiag(DiagnosticSeverity.Information, "", "plain info")
        let plain = CLIDiagnosticFace(maxWidth: Some(80), color: Some(false)).renderToString([d, d2], Some("abc"))
        assertGolden(plain, "cli_plain")
        let colored = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true)).renderToString([d, d2], Some("abc"))
        assertGolden(colored, "cli_color")
    }

    @TestCase
    public func logFaceMixed(): Unit {
        let rel = RelatedInfo(range: None, filename: "other.toml", message: "hint here")
        let d1 = goldenDiag(DiagnosticSeverity.Error, "boom", "boom",
            Some(DiagnosticRange(startLine: 12, startColumn: 3, endLine: 12, endColumn: 5)))
        let d2 = goldenDiag(DiagnosticSeverity.Warning, "", "no code\nsecond line",
            Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 2)))
        let d3 = goldenDiag(DiagnosticSeverity.Hint, "colored-hint", "hint", None, [rel])
        let out = LogDiagnosticFace().renderToString([d2, d1, d3], None)   // input order preserved
        assertGolden(out, "logface_mixed")
    }

    @TestCase
    public func jsonBasic(): Unit {
        let d = goldenDiag(DiagnosticSeverity.Error, "boom", "boom",
            Some(DiagnosticRange(startLine: 3, startColumn: 2, endLine: 3, endColumn: 6)))
        let out = JsonRpcDiagnosticFace().renderToString([d], None)
        // The URI embeds the absolute CWD, so normalize it to keep the golden
        // machine-independent.
        let cwd = getWorkingDirectory().toString()
        let normalized = out.replace("file://${cwd}/golden.toml", "file:///golden.toml")
        assertGolden(normalized, "json_basic")
    }
}

@Test
public class MultiLabelTest {
    private func labelsDiag(message: String, labels: Array<Label>): Diagnostic {
        Diagnostic(
            range: None, filename: "x.cj", severity: DiagnosticSeverity.Error, code: "",
            source: "test", message: message, labels: labels)
    }

    private func plainRender(diag: Diagnostic, source: ?String): String {
        CLIDiagnosticFace(maxWidth: Some(80), color: Some(false)).renderToString([diag], source)
    }

    @TestCase
    public func multiLabelSortedBackwardOrder(): Unit {
        let src = "let y = x + 1\nlet z = 5\nlet a = 10\nlet b = 20\nlet x = 42\n"
        let d = labelsDiag("variable 'x' used before definition", [
            Label(range: DiagnosticRange(startLine: 5, startColumn: 5, endLine: 5, endColumn: 6),
                filename: "x.cj", message: "defined here"),
            Label(range: DiagnosticRange(startLine: 1, startColumn: 9, endLine: 1, endColumn: 10),
                filename: "x.cj", message: "used here")
        ])
        let out = plainRender(d, Some(src))
        @Assert((out.indexOf("used here") ?? -1) < (out.indexOf("defined here") ?? -1))
        @Assert(out.contains("x.cj:1:9"))
        @Assert(out.contains("let y = x + 1"))
        @Assert(out.contains("let x = 42"))
        // Gap > 2 splits into separate sub-frames: the second is introduced
        // by a ":::" header (rustc convention) carrying just the location.
        @Assert(out.contains("::: x.cj:5:5"))
    }

    @TestCase
    public func multiLabelGapTwoShowsMidLine(): Unit {
        let src = "one\ntwo\nthree\nfour\nfive\n"
        let d = labelsDiag("gap two", [
            Label(range: DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1),
                filename: "x.cj", message: "top"),
            Label(range: DiagnosticRange(startLine: 3, startColumn: 1, endLine: 3, endColumn: 1),
                filename: "x.cj", message: "bottom")
        ])
        let out = plainRender(d, Some(src))
        @Assert(out.contains("two"))            // mid line shown for gap == 2
        @Assert(out.contains("top"))
        @Assert(out.contains("bottom"))
        @Assert(!out.contains("..."))           // no ellipsis for gap == 2
    }

    @TestCase
    public func multiLabelSameLine(): Unit {
        let src = "let y = x + 1\n"
        let d = labelsDiag("same line", [
            Label(range: DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1),
                filename: "x.cj", message: "first"),
            Label(range: DiagnosticRange(startLine: 1, startColumn: 5, endLine: 1, endColumn: 6),
                filename: "x.cj", message: "second")
        ])
        let out = plainRender(d, Some(src))
        @Assert(out.contains("first"))
        @Assert(out.contains("second"))
        @Assert(out.split("^").size - 1 == 2)
    }

    @TestCase
    public func multiLabelLineNumbersShareGutterColor(): Unit {
        let src = "one\ntwo\n"
        let d = labelsDiag("colored gutter", [
            Label(range: DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1),
                filename: "x.cj", message: "top"),
            Label(range: DiagnosticRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 1),
                filename: "x.cj", message: "bottom")
        ])
        let out = CLIDiagnosticFace(maxWidth: Some(80), color: Some(true))
            .renderToString([d], Some(src))
        // Line numbers carry the same cyan as the gutter bars and gap marker.
        @Assert(out.contains("\u{1B}[36m1\u{1B}[0m \u{1B}[36m|\u{1B}[0m"))
        @Assert(out.contains("\u{1B}[36m2\u{1B}[0m \u{1B}[36m|\u{1B}[0m"))
    }

    @TestCase
    public func multiLabelGroupsByFileSorted(): Unit {        let src = "one\n"
        let d = labelsDiag("multi file", [
            Label(range: DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1),
                filename: "z.cj", message: "in z"),
            Label(range: DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1),
                filename: "a.cj", message: "in a")
        ])
        let out = plainRender(d, Some(src))
        @Assert((out.indexOf("a.cj:1:1") ?? -1) < (out.indexOf("z.cj:1:1") ?? -1))
        @Assert(out.contains("in a"))
        @Assert(out.contains("in z"))
    }

    @TestCase
    public func multiLabelOutOfBoundsLineShowsCaret(): Unit {
        let src = "one\n"
        let d = labelsDiag("out of bounds", [
            Label(range: DiagnosticRange(startLine: 99, startColumn: 5, endLine: 99, endColumn: 6),
                filename: "x.cj", message: "missing line")
        ])
        let out = plainRender(d, Some(src))
        @Assert(out.contains("missing line"))
        @Assert(out.contains("^"))   // caret clamped to >= 1 even on empty line
    }

    @TestCase
    public func multiLabelCaretPastLineEndClamped(): Unit {
        let src = "let y = x + 1\n"
        let d = labelsDiag("past end", [
            Label(range: DiagnosticRange(startLine: 1, startColumn: 999, endLine: 1, endColumn: 1000),
                filename: "x.cj", message: "way past")
        ])
        let out = plainRender(d, Some(src))
        @Assert(out.contains("way past"))
        @Assert(out.contains("^"))
    }

    @TestCase
    public func legacyRangeStillUsedWithoutLabels(): Unit {
        let d = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 3, endLine: 2, endColumn: 5)),
            filename: "a.toml", severity: DiagnosticSeverity.Error, code: "c", source: "cjpm",
            message: "m")
        let out = plainRender(d, Some("one\ntwo three\nfour"))
        @Assert(out.contains("a.toml:2:3"))
        @Assert(out.contains("two three"))
    }

    // Builds an N-line source where line i reads "line <i> content".
    private func linesSource(n: Int64): String {
        let sb = StringBuilder()
        for (i in 1..=n) { sb.append("line ${i} content\n") }
        sb.toString()
    }

    private func nChars(c: String, n: Int64): String {
        let sb = StringBuilder()
        for (_ in 0..n) { sb.append(c) }
        sb.toString()
    }

    // Every gutter row writes its pipe at column width+1; the ==>/:::
    // marker is indented so its middle character sits on that column.
    // Verifies the invariant across every rendered row of `out`.
    private func assertGutterAligned(out: String, width: Int64): Unit {
        let pipeCol = width + 1
        for (row in out.split("\n")) {
            if (row.contains("|")) {
                let idx = row.indexOf("|") ?? -1
                @Assert(idx == pipeCol)
            }
            if (row.contains("==>") || row.contains(":::")) {
                // The byte at the pipe column must be the marker's middle char.
                let bytes = row.toArray()
                @Assert(bytes[pipeCol] == 61 || bytes[pipeCol] == 58) // '=' | ':'
            }
        }
    }

    @TestCase
    public func wideGutterHundredLineFileJoinsAndAligns(): Unit {
        // Lines 98..100 give a 3-digit gutter; gap-2 pair joins with a mid
        // row, and the header indent must track the wider gutter.
        let d = labelsDiag("far down", [
            Label(range: DiagnosticRange(startLine: 100, startColumn: 6, endLine: 100, endColumn: 10),
                filename: "x.cj", message: "on the last line"),
            Label(range: DiagnosticRange(startLine: 98, startColumn: 6, endLine: 98, endColumn: 10),
                filename: "x.cj", message: "two above")
        ])
        let out = plainRender(d, Some(linesSource(100)))
        @Assert(out.contains("   ==> x.cj:98:6"))     // marker indented to the gutter
        @Assert(out.contains(" 98 | line 98 content"))
        @Assert(out.contains(" 99 | line 99 content")) // gap-mid row
        @Assert(out.contains("100 | line 100 content"))
        @Assert(out.contains("^^^^ two above"))
        @Assert(out.contains("^^^^ on the last line"))
        this.assertGutterAligned(out, 3)
    }

    @TestCase
    public func wideGutterThousandLineFileSplitsAndAligns(): Unit {
        // Labels 4+ lines apart split into ::: sub-frames under a 4-digit
        // gutter; each single-labeled-line frame gains context rows whose
        // blank gutters match the numbered ones.
        let d = labelsDiag("deep file", [
            Label(range: DiagnosticRange(startLine: 1000, startColumn: 6, endLine: 1000, endColumn: 10),
                filename: "x.cj", message: "at one thousand"),
            Label(range: DiagnosticRange(startLine: 500, startColumn: 6, endLine: 500, endColumn: 10),
                filename: "x.cj", message: "half way")
        ])
        let out = plainRender(d, Some(linesSource(1000)))
        @Assert(out.contains("    ==> x.cj:500:6"))   // 4-space pad before ==>
        @Assert(out.contains("     | line 499 content")) // context row, blank gutter
        @Assert(out.contains(" 500 | line 500 content"))
        @Assert(out.contains("     | line 501 content")) // context row
        @Assert(out.contains("    ::: x.cj:1000:6"))
        @Assert(out.contains("     | line 999 content")) // context row
        @Assert(out.contains("1000 | line 1000 content"))
        @Assert(out.contains("^^^^ half way"))
        @Assert(out.contains("^^^^ at one thousand"))
        this.assertGutterAligned(out, 4)
    }

    @TestCase
    public func contextRowsShareLabeledWindow(): Unit {
        // Label far right on line 2 forces a shifted window (ws=27, keep=33,
        // left ellipsis only, at maxWidth 40). The ±1 context rows must
        // render the SAME column range of their lines — not line beginnings.
        let src = "${this.nChars("A", 60)}\n${this.nChars("B", 60)}\n${this.nChars("C", 60)}\n"
        let d = labelsDiag("mid span", [
            Label(range: DiagnosticRange(startLine: 2, startColumn: 50, endLine: 2, endColumn: 54),
                filename: "x.cj", message: "far right")
        ])
        let out = CLIDiagnosticFace(maxWidth: Some(40), color: Some(false)).renderToString([d], Some(src))
        // Labeled row shows B columns 27..59; context rows mirror the window.
        @Assert(out.contains("...${this.nChars("B", 33)}"))
        @Assert(out.contains("...${this.nChars("A", 33)}"))
        @Assert(out.contains("...${this.nChars("C", 33)}"))
        // The old unanchored rendering showed the first 33 columns instead.
        @Assert(!out.contains("${this.nChars("A", 33)}..."))
        @Assert(!out.contains("${this.nChars("C", 33)}..."))
        this.assertGutterAligned(out, 1)
    }

    @TestCase
    public func cjkBoundaryContextStaysAligned(): Unit {
        // visStart=27 falls inside the wide char on line 1 (cells 26-27).
        // Ceiling semantics skip it and pad one space, so the y-run starts
        // in exactly the column where the labeled B-run sits — no drift.
        let src = "${this.nChars("x", 26)}汉${this.nChars("y", 33)}\n${this.nChars("B", 60)}\n${this.nChars("z", 10)}\n"
        let d = labelsDiag("mid span", [
            Label(range: DiagnosticRange(startLine: 2, startColumn: 50, endLine: 2, endColumn: 54),
                filename: "x.cj", message: "far right")
        ])
        let out = CLIDiagnosticFace(maxWidth: Some(40), color: Some(false)).renderToString([d], Some(src))
        // Labeled row: "..." + 33 B's. Context row: "..." + pad + y's.
        @Assert(out.contains("...${this.nChars("B", 33)}"))
        @Assert(out.contains("... ${this.nChars("y", 32)}"))
        @Assert(!out.contains("汉"))
        this.assertGutterAligned(out, 1)
    }
}
