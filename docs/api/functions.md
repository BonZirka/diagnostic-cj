# Functions

## render

Renders diagnostics to an `OutputStream` using the given face.

```cangjie
public func render(
    diagnostics: Array<Diagnostic>,
    face: DiagnosticFace,
    source: ?String,
    sink: OutputStream
): Unit
```

## renderToString

Renders diagnostics to a `String` using the given face.

```cangjie
public func renderToString(
    diagnostics: Array<Diagnostic>,
    face: DiagnosticFace,
    source: ?String
): String
```

## filterDiagnostics

Keeps diagnostics whose severity maps to a log level at or above `minLevel`.
Pure and order-preserving.

```cangjie
public func filterDiagnostics(
    diagnostics: Array<Diagnostic>,
    minLevel: LogLevel
): Array<Diagnostic>
```