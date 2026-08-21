# CLI LOC Collapse — Refactor Design

Date: 2026-08-22
Goal: shrink `src/` production LOC via targeted collapse; structure and public API unchanged. Output must stay **byte-identical**.

## Hunks

1. **`resolveWidth`**: iterate candidate array `[maxWidth, ttyWidth, parsePositiveInt(columnsEnv ?? "")]`, keeping the lowest positive value; delete the `narrower` helper. Signature, purity, and injectability unchanged.
2. **`lineOf` / `colOf`**: delegate to one shared `posOf(d, getter)` accessor; sort comparator unchanged.
3. **Fetch list**: drop the copy into `fetchList`; extend `lineNumsList` in place with the ±1 neighbor candidates (it has no other readers).
4. **Gutter emitters**: two private helpers on the face — `gutterRow(sb, width, body)` (blank gutter) and `numRow(sb, numStr, body)` (numbered). They emit `"␣…␣| body\n"` exactly as today; call sites pass pre-colored pieces. Replaces five near-identical `sb.append` templates (context, mid, labeled, caret-note-demotion, caret rows).
5. **`spanAnchor`**: single match inside the accumulation loop plus one tail expression for clamped length (`cl ≥ 1`). Semantics identical.
6. **`isBlank`**: inline at its only call site (`trimAscii().isEmpty()`); fix `useColor()` indentation.
7. **`repeatStr`**: move to text_width.cj as `internal`, rebuilt on StringBuilder (same output); `contextWindow`'s hand-rolled pad loop becomes `repeatStr(" ", pad)`.

## Constraints

- No behavior change: rendering byte-identical everywhere.
- Keep the insertion sort in `sortLabels`; keep the `windowLineGeom` ladder untouched.
- Public surface (`CLIDiagnosticFace.init/render/renderOne`) unchanged.

## Verification

- Per hunk: build + test suite green.
- Final: full suite green with goldens untouched (no regolden); example binary rebuilt; before/after output diff across all 11 examples × widths {3,10,23,24,40,80,200} × `CLICOLOR_FORCE=0/1` — all 154 captures byte-equal against `/tmp/opencode/refactor-base/`.
