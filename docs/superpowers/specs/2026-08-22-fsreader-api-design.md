# FSReader Public API Redesign

Date: 2026-08-22
Driver: ergonomics. Free to break source compatibility; all consumers live in-repo.
Reference: codespan's `Files` trait (opaque ids, whole-text access, typed error enum) — studied, then deliberately shrunk: our batch-lines shape expresses "missing" as absence, so no error taxonomy is needed.

## Problem

1. `source: ?String` threads through every render call. It conflates two meanings ("file text if you have it" vs `Diagnostic.source`, the emitter name like `"cjpm"`), covers only one file even though labels can span many, and forces every face signature to carry it while only the CLI face reads it.
2. `Diagnostic(...)` construction demands ~8 named args including nested `Some(DiagnosticRange(...))`; `code`/`source` are mandatory despite usually being empty.
3. Face names stutter: `CLIDiagnosticFace`, `JsonRpcDiagnosticFace`, `LogDiagnosticFace`.
4. Three doors to the same room: free functions `render()`/`renderToString()`, interface defaults, overrides.

## Design

### 1. `FSReader` (new file `src/fs_reader.cj`)

```cangjie
// Source-of-truth abstraction. Implementations decide HOW bytes are obtained
// (real descriptor streaming/seeking, memory slicing, ...); the batch shape
// lets a disk implementation open one descriptor and scan sequentially.
//
// Exception contract: LENIENT. Absent entries mean "unavailable"; missing or
// unreadable files must NOT throw. The renderer degrades gracefully
// (header-only frames, blank-gutter skips). Consumers wanting hard failures
// wrap FSReader above their own layer.
public interface FSReader {
    // Body-rendering gate (replaces fileReadable probe + inline special case).
    func readable(filename: String): Bool

    // Wanted lines absent from the result simply do not render. maxBytes
    // bounds per-line memory; implementations truncate at UTF-8 boundaries
    // (shared utf8FloorLen helper provided).
    func loadLines(filename: String, lineNos: Array<Int64>, maxBytes: Int64): HashMap<Int64, String>
}

public class DiskFsReader <: FSReader { ... }   // wraps today's readLines machinery
public class MemFsReader <: FSReader { ... }    // inits: map-of-files, or (filename, text)
```

`readLines`, `readOneLine`, `utf8FloorLen`, `truncateUtf8` move from cli_face.cj into fs_reader.cj (DiskFsReader/MemFsReader cores; MemFsReader slices via `split("\n")`).

### 1b. Memory discipline & line alignment (audit-driven contract clauses)

Audited disk path properties that DiskFsReader preserves, plus one fix:

1. Never materialize whole files; one descriptor per batch, sequential scan.
2. Retention ≤ (requested ∩ existing) lines × maxBytes (~20KiB per diagnosed file at width 80).
3. **Known defect carried over, not fixed here**: today's `readOneLine` truncates at maxBytes without consuming through `\n`, so files containing lines ≥ cap (~4096B) desync every subsequent fetched line number (empirically confirmed; see TODO.md "Hostile input hardening"). DiskFsReader must port current semantics VERBATIM — the owner has a preferred repair design and the fix lands separately.
4. Implementation hygiene during the move: drain skipped lines without building full buffers; avoid the ArrayList→Array→String triple copy; drop the duplicate readResult/linesToShow retention where possible.

Renderer-side granularity note: the renderer needs O(display window) around carets; maxBytes stays the honest upper bound, so retention remains O(window)-bounded regardless of source-line length.

### 2. Faces

- `CliFace(maxWidth!: ?Int64 = None, color!: ?Bool = None, files!: FSReader = DiskFsReader())`
  - renders via `this.files.loadLines(...)`; `showBody = readResult.size > 0 || files.readable(filename)`
  - `readCap()` stays internal renderer policy (budget-derived cap passed as maxBytes)
- Renames: `CLIDiagnosticFace`→`CliFace`, `JsonRpcDiagnosticFace`→`JsonRpcFace`, `LogDiagnosticFace`→`LogFace`
- JsonRpc/Log never consumed source; signatures slim automatically

### 3. `DiagnosticFace` slimming (diagnostic.cj)

```cangjie
public interface DiagnosticFace {
    func renderOne(d: Diagnostic, sink: OutputStream): Unit          // only abstract method
    func render(diagnostics: Array<Diagnostic>, sink: OutputStream): Unit { ... }        // default
    func renderToString(diagnostics: Array<Diagnostic>): String { ... }                  // default
}
```

Top-level free functions `render()` / `renderToString()` deleted.

### 4. `Diagnostic` changes

- Field rename: `source` → `emitter` (it is the tool name; JSON wire key stays `"source"` for LSP compatibility)
- Init defaults: `code = ""`, `emitter = ""`
- Fluent builders (struct copies; normalization invariant preserved by routing through full construction):

```cangjie
Diagnostic.error("undefined variable")     // severity presets: error/warning/note/hint
    .at("main.cj", 12, 5)                  // .at(file, line, col) point range; (file,l,c,endL,endC) overload
    .withCode("E042")
    .label("lib.cj", 3, 1, 3, 10, "defined here")
    .related("see docs", "docs.md")
```

Full-control init remains unchanged otherwise.

## Call-site updates

examples/ (12 runners), diagnostic_test.cj (107 cases), edge_case_test.cj (13), faces themselves — mechanical renames/signature drops/builder rewrites where convenient.

## Verification

Pure API reshape — zero output change expected:
- suite green after updates; goldens untouched (no regolden)
- rebuilt example binary byte-diff vs `/tmp/opencode/refactor-base/` captures (154 files, widths × CLICOLOR_FORCE) — all identical
