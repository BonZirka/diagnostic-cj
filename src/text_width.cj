package diagnostic

// ============ Display-width measurement ============
//
// All rendering math here works in DISPLAY COLUMNS, not bytes:
//   - full-width characters (CJK, Hangul, fullwidth forms) occupy 2 columns
//   - '\t' advances to the next multiple of 8
//   - malformed UTF-8 degrades to width-1 singletons (never throws)
//
// The width model mirrors std.unittest's common/unicode.cj (Markus Kuhn's
// wcwidth subset; ambiguous-width characters count as 1), so diagnostics
// align with the rest of the Cangjie ecosystem.

// A byte that may begin a UTF-8 encoded character (not a continuation byte).
internal func isCharStart(b: Byte): Bool {
    !(b >= 0x80u8 && b <= 0xBFu8)
}

internal func isContByte(b: Byte): Bool {
    b >= 0x80u8 && b <= 0xBFu8
}

// Decodes the UTF-8 sequence starting at bytes[i]. Returns (codepoint,
// length in bytes). Truncated or malformed sequences decode defensively:
// only the leading contiguous run of valid bytes is consumed.
internal func decodeCp(bytes: Array<Byte>, i: Int64): (UInt32, Int64) {
    let size = bytes.size
    let b0 = UInt32(bytes[i])
    if (b0 < 0xC0) { return (b0, 1) }
    var cp = UInt32(0)
    var len = Int64(1)
    if (b0 < 0xE0) {
        cp = b0 & 0x1F
        len = 2
    } else if (b0 < 0xF0) {
        cp = b0 & 0x0F
        len = 3
    } else if (b0 < 0xF8) {
        cp = b0 & 0x07
        len = 4
    } else {
        return (b0, 1)
    }
    var j = 1
    while (j < len) {
        if (i + j >= size || !isContByte(bytes[i + j])) {
            return (cp, j)
        }
        cp = (cp << 6) | (UInt32(bytes[i + j]) & 0x3F)
        j += 1
    }
    (cp, len)
}

// Display width of a single rune's codepoint: 2 inside full-width ranges,
// 1 elsewhere.
internal func runeWidthCp(cp: UInt32): Int64 {
    let wide =
        (cp >= 0x1100 && cp <= 0x115F) ||
        cp == 0x2329 || cp == 0x232A ||
        (cp >= 0x2E80 && cp <= 0xA4CF && cp != 0x303F) ||
        (cp >= 0xAC00 && cp <= 0xD7A3) ||
        (cp >= 0xF900 && cp <= 0xFAFF) ||
        (cp >= 0xFE10 && cp <= 0xFE19) ||
        (cp >= 0xFE30 && cp <= 0xFE6F) ||
        (cp >= 0xFF00 && cp <= 0xFF60) ||
        (cp >= 0xFFE0 && cp <= 0xFFE6) ||
        (cp >= 0x20000 && cp <= 0x2FFFD) ||
        (cp >= 0x30000 && cp <= 0x3FFFD)
    if (wide) { 2 } else { 1 }
}

// Display width of a whole line, in columns.
internal func displayWidth(s: String): Int64 {
    displayColAtByte(s, s.size)
}

// Display columns and byte length of the character starting at `bytes[i]`:
// tabs advance to the next multiple of 8; full-width runes are 2 columns;
// a stray continuation byte counts as one column, one byte. Shared by all
// column walkers so the tricky per-char rules live in exactly one place.
internal func charWidthStep(bytes: Array<Byte>, i: Int64, curCol: Int64): (Int64, Int64) {
    let b = bytes[i]
    if (b == 0x09u8) {
        (8 - (curCol % 8), 1)
    } else if (isCharStart(b)) {
        let (cp, len) = decodeCp(bytes, i)
        (runeWidthCp(cp), len)
    } else {
        (1, 1)
    }
}

// Display column of byte offset `byteIdx` in `line`. Tabs advance to the
// next multiple of 8; full-width runes add 2. Bounds-clamped so absurd
// offsets can never cause huge allocations.
internal func displayColAtByte(line: String, byteIdx: Int64): Int64 {
    let bytes = line.toArray()
    var limit = byteIdx
    if (limit > bytes.size) { limit = bytes.size }
    if (limit < 0) { limit = 0 }
    var col = 0
    var i = 0
    while (i < limit) {
        let (w, step) = charWidthStep(bytes, i, col)
        col += w
        i += step
    }
    col
}

// Byte offset of display column `col` in `line`, floored to a character
// boundary: starts the character whose first cell is at or before `col`.
// Columns past the end clamp to `line.size`.
internal func byteAtDisplayCol(line: String, col: Int64): Int64 {
    if (col <= 0) { return 0 }
    let bytes = line.toArray()
    var cur = 0
    var i = 0
    while (i < bytes.size) {
        let (w, step) = charWidthStep(bytes, i, cur)
        if (cur + w > col) {
            // col falls within this character's cells: floor to its start
            return i
        }
        cur += w
        i += step
    }
    bytes.size
}

// Byte offset ending the longest prefix whose display width is at most
// `cols`. Unlike byteAtDisplayCol this excludes a character straddling the
// limit, so slices taken with this offset never split a character nor
// exceed the column budget.
internal func byteAtDisplayColFit(line: String, cols: Int64): Int64 {
    if (cols <= 0) { return 0 }
    let bytes = line.toArray()
    var cur = 0
    var i = 0
    while (i < bytes.size) {
        let (w, step) = charWidthStep(bytes, i, cur)
        if (cur + w > cols) { return i }
        cur += w
        i += step
    }
    bytes.size
}

// Windowing policy knobs, in display columns. Tuning them reshapes every
// rendered frame deterministically. The allocation contract they implement:
//   1. The span is shown IN FULL whenever the window can hold it.
//   2. Right context fills passively up to a total footprint of
//      RIGHT_FILL_MAX INCLUDING its "..." when one is needed, but never
//      pushes the left side below LEFT_KEEP_MIN (and never below what
//      exists).
//   3. When the span alone cannot fit, right context is reclaimed first;
//      the left side caps at its ellipsis-inclusive share of LEFT_KEEP_MIN
//      while the span fills the rest of the window, and carets cover the
//      right "..." to signal overflow.
internal let ELLIPSIS_COLS: Int64 = 3
internal let LEFT_KEEP_MIN: Int64 = 10   // left floor on fill; hard cap on overflow
internal let RIGHT_FILL_MAX: Int64 = 10  // right side total, ellipsis included
internal let SPAN_KEEP_MIN: Int64 = 10   // min visible span when budget too tight for both

// Windows the line text to `budget` display columns.
//
// Slicing happens on character boundaries via byteAtDisplayColFit, so
// multi-byte characters are never split. The window start (ws) is recomputed
// from the actual byte offset after slicing, so carets always land under the
// correct source character even when a CJK char straddles the left boundary.
//
// Algorithm — closed-form priority ladder (no iteration):
//   Case 1: whole line fits -> show it, no ellipses.
//   Case 2: span fits after margins -> span full; right context fills
//           passively up to RIGHT_FILL_MAX subject to the LEFT_KEEP_MIN
//           left floor; leftover space goes to the left side.
//   Case 3: span does not fit -> right context reclaims first; left trims
//           just enough to restore SPAN_KEEP_MIN visible span columns;
//           carets cover the right "..." (rule 2 above).
//
// Ellipsis flags are DERIVED from the final allocation, never guessed: the
// allocator evaluates the four (needLeft, needRight) margin combinations in
// fixed priority order [(F,F), (T,F), (F,T), (T,T)] — fewer ellipses first,
// left outranks right — and takes the first whose derived flags match the
// assumed margins. This makes output deterministic and monotone under
// budget changes; the (T,T) combination always accepts, bounding work.
//
// windowLineGeom returns the displayed slice plus where it sits: ws = window
// Repeats `s` n times.
internal func repeatStr(s: String, n: Int64): String {
    let sb = StringBuilder()
    for (_ in 0..n) { sb.append(s) }
    sb.toString()
}

// start column (recomputed from byte boundary, so caret math stays accurate),
// left/right = whether an ellipsis was prepended/appended, keep = content
// columns in disp (excludes ellipses). A caret at raw display column c maps
// to content column c - ws; its position in disp is that plus (left ? 3 : 0).
// caretLen centralizes the length math so a future max caret length (~40)
// is one line.
internal func windowLineGeom(text: String, budget: Int64, cs0: ?Int64, cl0: Int64): (String, Int64, Bool, Bool, Int64) {
    let lw = displayWidth(text)
    match (cs0) {
        case None =>
            if (lw <= budget) { (text, 0, false, false, lw) }
            else {
                var keep = budget - ELLIPSIS_COLS
                if (keep < 1) { keep = 1 }
                (text[0..byteAtDisplayColFit(text, keep)] + "...", 0, false, true, keep)
            }
        case Some(cs) =>
            if (lw <= budget) { (text, 0, false, false, lw) }
            else {
                let leftCtx = cs
                var post = lw - cs - cl0
                post = max(post, 0)

                var resDisp = ""
                var resWs = Int64(0)
                var resLeft = false
                var resRight = false
                var resKeep = Int64(1)

                // Priority order: fewer ellipses first, left "..." outranks
                // right. (T,T) accepts unconditionally as the catch-all for
                // degenerate budgets, so the loop always settles.
                let candidates = [(false, false), (true, false), (false, true), (true, true)]
                for ((lf, rf) in candidates) {
                    let marginL = if (lf) { ELLIPSIS_COLS } else { 0 }
                    let marginR = if (rf) { ELLIPSIS_COLS } else { 0 }
                    let content = max(budget - marginL - marginR, 1)

                    var showLeft = Int64(0)
                    var spanTruncated = false
                    if (cl0 > content) {
                        // Rule 3: right already reclaimed; left caps at its
                        // ellipsis-inclusive share of LEFT_KEEP_MIN (the
                        // "..." counts toward the cap) while the span fills
                        // the rest of the window.
                        spanTruncated = true
                        let leftTotal = if (lf) { LEFT_KEEP_MIN - ELLIPSIS_COLS } else { LEFT_KEEP_MIN }
                        showLeft = min(leftCtx, min(max(content - SPAN_KEEP_MIN, 0), max(leftTotal, 0)))
                    } else {
                        // Rule 2: passive right fill under the left floor.
                        // The right cap counts the "..." when one will be
                        // drawn (rf), so the whole right side fits in
                        // RIGHT_FILL_MAX.
                        let leftover = content - cl0
                        let floorL = min(leftCtx, LEFT_KEEP_MIN)
                        let rightCap = if (rf) { RIGHT_FILL_MAX - ELLIPSIS_COLS } else { RIGHT_FILL_MAX }
                        let target = min(max(rightCap, 0), post)
                        showLeft = min(leftCtx, min(max(leftover - target, floorL), leftover))
                    }
                    let dLeft = showLeft < leftCtx
                    let dRight = spanTruncated || (content - cl0 - showLeft < post)

                    if (!(lf && rf) && (dLeft != lf || dRight != rf)) { continue }

                    // Character-boundary-safe slicing: ws floors back to the
                    // start of the character containing it, then the window
                    // end never splits nor exceeds the content budget.
                    let startByte = byteAtDisplayCol(text, max(cs - showLeft, 0))
                    let actualWs = displayColAtByte(text, startByte)
                    var endByte = byteAtDisplayColFit(text, actualWs + content)
                    if (endByte <= startByte && startByte < text.size) {
                        // Degenerate budget: take one WHOLE character even if
                        // it exceeds the column budget — never split UTF-8.
                        let wbytes = text.toArray()
                        let (_, clen) = decodeCp(wbytes, startByte)
                        endByte = min(startByte + clen, text.size)
                    }
                    var d = text[startByte..endByte]
                    if (lf) { d = "..." + d }
                    if (rf) { d = d + "..." }
                    resDisp = d
                    resWs = actualWs
                    resLeft = lf
                    resRight = rf
                    resKeep = max(displayColAtByte(text, endByte) - actualWs, 1)
                    break
                }
                (resDisp, resWs, resLeft, resRight, resKeep)
            }
    }
}

// Caret length given the span length (spanLen), the caret's content column
// (s2), the content width (keep), and whether a right ellipsis is present.
// Fits -> full span, inside content. Overflows -> visible part plus the right
// "..." so the overflow is signalled. Centralized so a future cap (e.g.
// `if (l > 40) { l = 40 }`) is a single line.
internal func caretLen(spanLen: Int64, s2: Int64, keep: Int64, right: Bool): Int64 {
    let visible = keep - s2
    var l = if (spanLen > visible) { visible + (if (right) { Int64(3) } else { Int64(0) }) } else { spanLen }
    if (l < 1) { l = 1 }
    l
}

// Renders an unlabeled context line inside the SAME display-column window as
// its neighboring labeled row: the slice covers columns [visStart,
// visStart+keep) and the left/right ellipsis slots are mirrored
// unconditionally, so every row of the frame keeps its characters in the same
// screen columns even when the labeled row's window was shifted to keep its
// carets visible. A wide character straddling visStart is skipped (ceiling)
// and replaced by padding spaces, so lines with different character grids
// stay aligned column-for-column instead of drifting by one cell. A short
// line simply contributes nothing inside the range; the fold markers stay put.
internal func contextWindow(text: String, visStart: Int64, keep: Int64, left: Bool, right: Bool): String {
    var d = ""
    if (left) { d += "..." }
    let bytes = text.toArray()
    var cur = 0
    var i = 0
    var startByte = bytes.size
    var pad = 0
    while (i < bytes.size) {
        let (w, step) = charWidthStep(bytes, i, cur)
        if (cur >= visStart) {
            // First character starting at or after the window start. A gap
            // left by a skipped straddling wide char is padded with spaces.
            startByte = i
            pad = cur - visStart
            break
        }
        cur += w
        i += step
    }
    let endByte = byteAtDisplayColFit(text, visStart + keep)
    if (pad > 0) { d += repeatStr(" ", pad) }
    if (endByte > startByte) { d += text[startByte..endByte] }
    if (right) { d += "..." }
    d
}

internal func windowLine(text: String, budget: Int64, cs0: ?Int64, cl0: Int64): (String, Int64, Int64) {
    let (disp, ws, left, right, keep) = windowLineGeom(text, budget, cs0, cl0)
    match (cs0) {
        case None => (disp, 0, 0)
        case Some(cs) =>
            let s2 = min(max(cs - ws, 0), keep)
            let l2 = caretLen(cl0, s2, keep, right)
            (disp, s2 + (if (left) { Int64(3) } else { Int64(0) }), l2)
    }
}

// Expands tabs to spaces up to the next multiple of 8 (spec §7.3), keeping
// every other character verbatim. Column math matches displayColAtByte, so
// carets computed on the raw line stay under the expanded text.
internal func expandTabs(s: String): String {
    let bytes = s.toArray()
    var out = StringBuilder()
    var col = 0
    var i = 0
    var runStart = 0
    while (i < bytes.size) {
        if (bytes[i] == 0x09u8) {
            out.append(s[runStart..i])
            let n = 8 - (col % 8)
            for (_ in 0..n) { out.append(" ") }
            col += n
            i += 1
            runStart = i
        } else {
            let (w, step) = charWidthStep(bytes, i, col)
            col += w
            i += step
        }
    }
    out.append(s[runStart..bytes.size])
    out.toString()
}
