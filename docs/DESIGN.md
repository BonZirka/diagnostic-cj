# Design notes

This file records *why* the library behaves the way it does. The API
reference says what a thing does; this document keeps the reasoning so
decisions do not have to be re-litigated and README stays lean. It is a
living draft — new decisions get a section, reversed decisions get theirs
rewritten.

## One value, three faces

A `Diagnostic` is plain data: range, filename, severity, code, message,
labels, related info. Rendering is delegated to faces — `CLIDiagnosticFace`
for humans, `LogDiagnosticFace` for one-line machine logs,
`JsonRpcDiagnosticFace` for LSP clients. Faces share no state and never
mutate diagnostics, so the same list can go to a terminal and an editor in
one pass without the two outputs disagreeing.

## Column semantics: byte ranges, display rendering

Range columns are 1-based byte offsets within a line (LSP-compatible).
Producers never need to know about terminal cells; conversion to display
columns happens at render time via `src/text_width.cj`. This keeps the
data format stable while all width policy lives in one module.

## Display-width model

Full-width characters count as 2 cells; combining marks will count as 0
(see TODO). The table mirrors the Cangjie standard library's
`std.unittest` module (`common/unicode.cj`), which is itself based on
[Markus Kuhn's wcwidth implementation](https://www.cl.cam.ac.uk/~mgk25/ucs/wcwidth.c).
Mirroring std.unittest rather than inventing a table means every Cangjie
tool agrees on how wide a character is; ambiguous-width characters count
as 1 because guessing wrong by one cell beats jittering between 1 and 2.

## Tab stops are convention, not data

Tabs advance to the next multiple of 8 — what a real terminal does.
Content-based inference of tab width was considered and rejected: tab
stops are a display convention with no ground truth in the file bytes, a
deterministic constant beats a heuristic that varies with which lines a
diagnostic happens to touch, and caret math stays correct under any width
because output is self-contained. An `.editorconfig` override may be
honored later as explicit user configuration.

## Color follows termstandard/colors

Environment handling follows the
[termstandard/colors](https://github.com/termstandard/colors) conventions,
audited against the spec text (see `ColorResolveTest`):

- Empty values count as unset for every variable ("empty variables are
  treated as though they were unset");
- precedence ladder, highest first:
  1. `NO_COLOR` (non-empty) disables — the spec's enable rule for
     `CLICOLOR_FORCE` is conditioned on "`CLICOLOR_FORCE` set, **but
     `NO_COLOR` unset**", so NO_COLOR always wins;
  2. else `CLICOLOR_FORCE` (non-empty, not `"0"`) forces on;
  3. else `CLICOLOR=0` disables (GNU convention; matches GCC and Rust's
     anstyle-query — note the spec page's sample code would treat `"0"`
     as truthy, we side with ecosystem practice);
  4. else `TERM=dumb` disables (conventional extension, not in the spec);
  5. else the source setting wins, defaulting to on.
- `CLICOLOR`'s affirmative form means "use color when writing to a
  terminal"; we cannot sense tty-ness on the color path, so it collapses
  into our default-on. Pinned by test so a future tty hook is a conscious
  change.

Deviations from the spec page are deliberate and listed above (`"0"`
handling for `CLICOLOR_FORCE`, `CLICOLOR=0`). The page's deprecation note
suggests treating `FORCE_COLOR` as a `CLICOLOR_FORCE` alias — tracked in
TODO.md, not implemented.

Width is resolved independently: the effective width is the tightest of
source `maxWidth`, terminal size, and `COLUMNS`; 80 only when none is
known. Caps compose instead of overriding each other because a diagnostic
that wraps in any of them is broken in that channel.

## Word codes, not numbers

Diagnostic codes are lowercase kebab-case words naming the error class
(`type-mismatch`, `line-too-long`, `undefined-variable`). Numeric codes
(`E0001`) force readers through a lookup table and are useless in grep;
a word code is self-documenting in the rendered frame and searchable in
source, docs, and issue trackers alike.

## Stable output ordering

`render` sorts diagnostics by `(filename, startLine, startColumn)`.
Producers should not need to care about emission order to get readable
output, and identical input must produce byte-identical output (goldens
depend on it).

## Window allocation: the span owns the budget

A rendered line is one contiguous slice of source. Left context, the span,
and right context are never placed independently — showing more of one is
always taking from another — so the allocator is a single priority ladder
over display columns, driven by named constants in `src/text_width.cj`
(`ELLIPSIS_COLS`, `LEFT_KEEP_MIN`, `RIGHT_FILL_MAX`, `SPAN_KEEP_MIN`).
Every limit counts its own ellipsis: a side that shows `"..."` spends part
of its budget on those three columns.

Priorities, highest first:

1. **The span is shown in full** whenever the window can hold it. Users
   act on the highlighted code; context is secondary by definition.
2. **Right context fills passively** into genuinely spare room, up to
   `RIGHT_FILL_MAX` including its `"..."`, but never pushes the left side
   below `LEFT_KEEP_MIN`. Passive means filling the right can never shrink
   anything else; when the left side is exhausted it stops competing and
   right may run past its cap rather than leave a hole.
3. **On overflow** (the span alone exceeds the window), right context is
   reclaimed first; then left caps at its ellipsis-inclusive share of
   `LEFT_KEEP_MIN` while the span takes everything else. Carets extend
   across the right `"..."` so the reader sees the highlight continues
   off-screen.

The right-fill rule exists because pure left bias wasted the window: an
over-long line handed every spare column to the left even when the span
fit with room to spare, so readers saw what led to the error but never a
peek at what follows it (`examples/longspan.cj`). The left bias survives
as floors and caps instead of greed — small left contexts stay fully
visible, huge ones yield.

Determinism: ellipsis flags are derived, never guessed. The allocator
evaluates the four `(needLeft, needRight)` margin combinations in fixed
priority order and takes the first whose derived flags match the assumed
margins; `(true, true)` accepts unconditionally, bounding work. This
replaced an earlier fixed-point loop whose flag flips produced a 2-column
"saturation snap" at ellipsis boundaries. Straight-line arithmetic means
identical inputs produce byte-identical frames.

## Bounded work per render

Sources are read line-by-line through a buffered stream up to the highest
line any label or range needs — never slurped whole. Windowing slices on
character boundaries so multi-byte characters survive truncation intact.

## Testability without a terminal

Environment-dependent decisions live in pure, injectable functions
(`resolveColor`, `resolveWidth`) taking env values as parameters, so the
precedence rules are unit-tested without touching process environment or
TTY state. Rendering is locked by golden files; `UPDATE_GOLDEN=1 cjpm test`
regenerates them after deliberate changes.
