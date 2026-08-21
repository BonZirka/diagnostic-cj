# Interfaces

## DiagnosticFace

Renders diagnostics for a specific output channel (terminal, log, JSON-RPC).
Not sealed: consumers may implement custom faces.

```cangjie
public interface DiagnosticFace {
    func renderOne(d: Diagnostic, source: ?String, sink: OutputStream): Unit
    func render(diagnostics: Array<Diagnostic>, source: ?String, sink: OutputStream): Unit
    func renderToString(diagnostics: Array<Diagnostic>, source: ?String): String
}
```