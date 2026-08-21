# diagnostic — API reference

A Cangjie package for representing, filtering, and rendering compiler/tool
diagnostics in multiple output formats.

- Package: `diagnostic`
- Version: 1.0.0
- Source: `src/`

## Items

### Enums

- [`DiagnosticSeverity`](enums.md#diagnosticseverity) — severity level of a diagnostic
- [`LogLevel`](enums.md#loglevel) — log level used for filtering

### Structs

- [`DiagnosticRange`](structs.md#diagnosticrange) — 1-based source range
- [`RelatedInfo`](structs.md#relatedinfo) — related context attached to a diagnostic
- [`Label`](structs.md#label) — labeled source region for multi-location diagnostics
- [`Diagnostic`](structs.md#diagnostic) — a complete diagnostic

### Interfaces

- [`DiagnosticFace`](interfaces.md#diagnosticface) — renders diagnostics to an output channel

### Classes

- [`CLIDiagnosticFace`](classes.md#clidiagnosticface) — human-readable terminal output
- [`LogDiagnosticFace`](classes.md#logdiagnosticface) — one-line log output
- [`JsonRpcDiagnosticFace`](classes.md#jsonrpcdiagnosticface) — LSP-compatible JSON-RPC output

### Functions

- [`render`](functions.md#render) — render diagnostics to a sink
- [`renderToString`](functions.md#rendertostring) — render diagnostics to a string
- [`filterDiagnostics`](functions.md#filterdiagnostics) — filter diagnostics by log level