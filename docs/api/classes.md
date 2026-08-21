# Classes

## CLIDiagnosticFace

Human-readable terminal output with source context, carets, and ANSI colors.

Color follows the [termstandard/colors](https://github.com/termstandard/colors)
conventions: `CLICOLOR_FORCE` (non-empty, not `"0"`) forces color on;
`NO_COLOR` / `TERM=dumb` always disable it. Width is the tightest of
`maxWidth`, the terminal width, and `COLUMNS`.

```cangjie
public class CLIDiagnosticFace <: DiagnosticFace {
    public init(maxWidth!: ?Int64 = None, color!: ?Bool = None)
}
```

### Column semantics

`DiagnosticRange` columns are **1-based byte offsets** within the line
(LSP-compatible). Rendering converts them to display columns, where
full-width characters (CJK, Hangul, fullwidth forms — same width table as
`std.unittest`) occupy 2 cells, ambiguous-width characters occupy 1, and
tabs advance to the next multiple of 8. Windowing slices on character
boundaries, so multi-byte characters are never split at window edges.

## LogDiagnosticFace

One line per diagnostic for logging pipelines; never emits ANSI codes.

```cangjie
public class LogDiagnosticFace <: DiagnosticFace {
    public init()
}
```

## JsonRpcDiagnosticFace

LSP-compatible `textDocument/publishDiagnostics` JSON-RPC output.

```cangjie
public class JsonRpcDiagnosticFace <: DiagnosticFace {
    public init()
}
```