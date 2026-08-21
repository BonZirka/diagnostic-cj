# Enums

## DiagnosticSeverity

The severity level of a diagnostic.

```cangjie
public enum DiagnosticSeverity {
    | Error
    | Warning
    | Information
    | Hint

    public func toLspNumber(): Int64
    public func toString(): String
    public func toLogLevel(): LogLevel
}
```

## LogLevel

A log level used for filtering diagnostics by severity.

```cangjie
public enum LogLevel {
    | Error
    | Warning
    | Info
    | Debug
}
```