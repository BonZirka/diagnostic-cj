# Structs

## DiagnosticRange

A source range with 1-based line and column numbers.

```cangjie
public struct DiagnosticRange {
    public let startLine: Int64
    public let startColumn: Int64
    public let endLine: Int64
    public let endColumn: Int64

    public init(startLine!: Int64, startColumn!: Int64, endLine!: Int64, endColumn!: Int64)
}
```

## RelatedInfo

Additional context attached to a diagnostic (e.g., "defined here", "see also").

```cangjie
public struct RelatedInfo {
    public let range: ?DiagnosticRange
    public let filename: String
    public let message: String

    public init(range!: ?DiagnosticRange, filename!: String, message!: String)
}
```

## LabelStyle

Semantic role of a label within a diagnostic. Faces map this to visual
styling independently of the diagnostic's severity: the CLI face renders
`Primary` carets red and `Secondary` carets blue (rustc convention).

```cangjie
public enum LabelStyle {
    | Primary
    | Secondary
}
```

## Label

A labeled source region with an associated message, used for multi-location
diagnostics (e.g., "variable used before definition"). `style` is optional;
unstyled labels render like `Primary`.

```cangjie
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
    )
}
```

## Diagnostic

A complete diagnostic with location, severity, code, message, and optional
related information and labels.

```cangjie
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
    )
}
```