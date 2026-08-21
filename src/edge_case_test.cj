// Edge case tests for diagnostic rendering
package diagnostic

import std.unittest.*
import std.fs.*

@Test
public class EdgeCaseTest {
    // Test 1: Related information with multiple locations
    @TestCase
    public func relatedInfoMultipleLocations(): Unit {
        let mainDiag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 10, startColumn: 5, endLine: 10, endColumn: 15)),
            filename: "main.cj",
            severity: DiagnosticSeverity.Error,
            code: "undefined-variable",
            source: "test",
            message: "undefined variable",
            relatedInfo: [
                RelatedInfo(
                    range: Some(DiagnosticRange(startLine: 5, startColumn: 1, endLine: 5, endColumn: 10)),
                    filename: "other.cj",
                    message: "variable declared here"
                ),
                RelatedInfo(
                    range: Some(DiagnosticRange(startLine: 20, startColumn: 3, endLine: 20, endColumn: 8)),
                    filename: "another.cj",
                    message: "also referenced here"
                )
            ]
        )
        
        let face = CLIDiagnosticFace()
        let output = face.renderToString([mainDiag], None)
        
        // Should contain main diagnostic
        assertContains(output, "undefined variable")
        assertContains(output, "main.cj:10:5")
        
        // Should contain related info notes
        assertContains(output, "variable declared here")
        assertContains(output, "other.cj:5:1")
        assertContains(output, "also referenced here")
        assertContains(output, "another.cj:20:3")
    }
    
    // Test 1b: Related information with source context (when file exists)
    @TestCase
    public func relatedInfoWithSourceContext(): Unit {
        // Create a temporary file for the related info
        let tempFile = "/tmp/diagnostic_test_related.cj"
        File.writeTo(tempFile, "line 1\nlet foo = 42\nline 3".toArray())
        
        let mainDiag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 10, startColumn: 5, endLine: 10, endColumn: 15)),
            filename: "main.cj",
            severity: DiagnosticSeverity.Error,
            code: "undefined-variable",
            source: "test",
            message: "undefined variable",
            relatedInfo: [
                RelatedInfo(
                    range: Some(DiagnosticRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 10)),
                    filename: tempFile,
                    message: "variable declared here"
                )
            ]
        )
        
        let face = CLIDiagnosticFace()
        let output = face.renderToString([mainDiag], None)
        
        // Should contain main diagnostic
        assertContains(output, "undefined variable")
        
        // Related info renders as a note only; ranged rels no longer emit
        // blue-caret source blocks (they looked like ::: sub-frames).
        assertContains(output, "variable declared here")
        @Assert(!output.contains("let foo = 42"))
        @Assert(!output.contains("^^^^^^^^^"))
    }
    
    // Test 2: Line at very start (line 1, column 1)
    @TestCase
    public func lineAtStart(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 5)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "error-at-start",
            source: "test",
            message: "error at start"
        )
        
        let source = "first line\nsecond line\nthird line"
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        // Should render without crashing
        assertContains(output, "error at start")
        assertContains(output, "test.cj:1:1")
        assertContains(output, "first line")
        assertContains(output, "^^^^")
    }
    
    // Test 3: Line at very end (last line)
    @TestCase
    public func lineAtEnd(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 3, startColumn: 1, endLine: 3, endColumn: 5)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "error-at-end",
            source: "test",
            message: "error at end"
        )
        
        let source = "first line\nsecond line\nthird line"
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        assertContains(output, "error at end")
        assertContains(output, "test.cj:3:1")
        assertContains(output, "third line")
    }
    
    // Test 4: Line beyond file end (out of bounds)
    @TestCase
    public func lineBeyondEnd(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 100, startColumn: 1, endLine: 100, endColumn: 5)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "line-beyond-end",
            source: "test",
            message: "error beyond end"
        )
        
        let source = "first line\nsecond line"
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        // Should degrade gracefully - show header but no code block
        assertContains(output, "error beyond end")
        assertContains(output, "test.cj:100:1")
        // Should NOT crash
    }
    
    // Test 5: Column beyond line end
    @TestCase
    public func columnBeyondLineEnd(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 100, endLine: 1, endColumn: 105)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "column-beyond-end",
            source: "test",
            message: "column beyond end"
        )
        
        let source = "short line"
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        // Should clamp caret to end of line
        assertContains(output, "column beyond end")
        assertContains(output, "test.cj:1:100")
        assertContains(output, "short line")
    }
    
    // Test 6: Missing newline at end of file
    @TestCase
    public func missingNewlineAtEnd(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 2, startColumn: 1, endLine: 2, endColumn: 5)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "no-trailing-newline",
            source: "test",
            message: "no trailing newline"
        )
        
        // Note: no trailing newline
        let source = "first line\nsecond line"
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        assertContains(output, "no trailing newline")
        assertContains(output, "second line")
    }
    
    // Test 7: Empty source file
    @TestCase
    public func emptySourceFile(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 5)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "empty-file",
            source: "test",
            message: "empty file"
        )
        
        let source = ""
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        // Should degrade gracefully
        assertContains(output, "empty file")
        assertContains(output, "test.cj:1:1")
    }
    
    // Test 8: Zero line number (invalid)
    @TestCase
    public func zeroLineNumber(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 0, startColumn: 1, endLine: 0, endColumn: 5)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "zero-line",
            source: "test",
            message: "zero line"
        )
        
        let source = "first line"
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        // Should handle gracefully (clamp to line 1 or show without code)
        assertContains(output, "zero line")
    }
    
    // Test 9: Negative column (invalid)
    @TestCase
    public func negativeColumn(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: -5, endLine: 1, endColumn: 5)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "negative-column",
            source: "test",
            message: "negative column"
        )
        
        let source = "first line"
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        // Should clamp to column 1
        assertContains(output, "negative column")
        assertContains(output, "first line")
    }
    
    // Test 10: Related info without range (just message)
    @TestCase
    public func relatedInfoWithoutRange(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 5, startColumn: 1, endLine: 5, endColumn: 5)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "related-no-range",
            source: "test",
            message: "main error",
            relatedInfo: [
                RelatedInfo(
                    range: None,
                    filename: "config.toml",
                    message: "see configuration"
                )
            ]
        )
        
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], None)
        
        assertContains(output, "main error")
        assertContains(output, "see configuration")
        assertContains(output, "config.toml")
        // Should not have line:col for related info without range
        assertContains(output, "config.toml\n")
    }
    
    // Test 11: Single line file with error
    @TestCase
    public func singleLineFile(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 3, endLine: 1, endColumn: 7)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "single-line",
            source: "test",
            message: "single line"
        )
        
        let source = "only one line"
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        assertContains(output, "single line")
        assertContains(output, "only one line")
        assertContains(output, "^^^^")
    }
    
    // Test 12: Column at exact line end
    @TestCase
    public func columnAtExactLineEnd(): Unit {
        let diag = Diagnostic(
            range: Some(DiagnosticRange(startLine: 1, startColumn: 10, endLine: 1, endColumn: 14)),
            filename: "test.cj",
            severity: DiagnosticSeverity.Error,
            code: "exact-end",
            source: "test",
            message: "at exact end"
        )
        
        let source = "exactly10c"  // 10 characters
        let face = CLIDiagnosticFace()
        let output = face.renderToString([diag], Some(source))
        
        assertContains(output, "at exact end")
        assertContains(output, "exactly10c")
    }
    
    private func assertContains(haystack: String, needle: String): Unit {
        if (!haystack.contains(needle)) {
            fail("Expected output to contain '${needle}' but got:\n${haystack}")
        }
    }
}
