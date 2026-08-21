package diagnostic

import std.collection.*
import std.convert.*
import std.env.*
import std.sort.*
import std.fs.*
import std.io.*

// ANSI escape sequences (no external dependency).
private let ESC = "\u{1B}"
private let ANSI_RESET = "${ESC}[0m"
private let ANSI_RED = "${ESC}[31m"
private let ANSI_YELLOW = "${ESC}[33m"
private let ANSI_BLUE = "${ESC}[34m"
private let ANSI_CYAN = "${ESC}[36m"

// Minimum bytes read per source line regardless of display width, so the
// labeled columns of realistic source lines always load even at degenerate
// terminal sizes (a line truncated before its own span would render a
// window that lies about the code).
internal let READ_CAP_FLOOR: Int64 = 4096

// Command-line/terminal level (NO_COLOR, CLICOLOR_FORCE, CLICOLOR, TERM=dumb)
// overrides the source setting, per the termstandard/colors conventions
// (https://github.com/termstandard/colors): empty values count as unset;
// NO_COLOR (non-empty) disables; else CLICOLOR_FORCE (non-empty, not "0")
// forces on; else CLICOLOR=0 disables; TERM=dumb disables.
// Pure and injectable so it is unit-testable without env access.
func resolveColor(colorMode: ?Bool, noColorEnv: ?String, termEnv: ?String,
    forceEnv: ?String, clicolorEnv: ?String): Bool {
    let noColor = noColorEnv ?? ""
    if (!noColor.isEmpty()) { return false }
    let force = forceEnv ?? ""
    if (!force.isEmpty() && force != "0") { return true }
    let clicolor = clicolorEnv ?? ""
    if (!clicolor.isEmpty() && clicolor == "0") { return false }
    if (termEnv == "dumb") { return false }
    colorMode ?? true
}

// Native terminal width (ioctl TIOCGWINSZ on Linux, GetConsoleScreenBufferInfo
// on Windows); 0 means unavailable (non-tty or failure), matching std.unittest.
// See native/terminal_size.c.
foreign func CJDiagnosticGetTerminalWidth(): UInt64

private func ttyWidth(): ?Int64 {
    let w = unsafe { CJDiagnosticGetTerminalWidth() }
    if (w == 0u64) { None } else { Some(Int64(w)) }
}

// Width is the tightest of every available constraint: source maxWidth,
// measured terminal width, and COLUMNS env. No source takes priority over
// another; non-positive values are ignored. 80 only when nothing is known.
// Pure and injectable so it is unit-testable without env/ioctl access (this
// SDK's std has no env setter).
func resolveWidth(maxWidth: ?Int64, ttyWidth: ?Int64, columnsEnv: ?String): Int64 {
    var best: ?Int64 = None
    let cands = [maxWidth, ttyWidth, parsePositiveInt(columnsEnv ?? "")]
    for (cand in cands) {
        match (cand) {
            case Some(n) =>
                if (n > 0) {
                    match (best) {
                        case Some(b) => if (n < b) { best = Some(n) }
                        case None => best = Some(n)
                    }
                }
            case None => ()
        }
    }
    best ?? 80
}

private func parsePositiveInt(s: String): ?Int64 {
    try {
        let n = Int64.parse(s)
        if (n > 0) { Some(n) } else { None }
    } catch (e: Exception) {
        None
    }
}

// Reads one line from a BufferedInputStream, up to maxBytes.
// Returns the line content (stripped \n, kept \r), or None at EOF.
// Largest prefix length of `arr` that ends on a UTF-8 character boundary:
// walks back over continuation bytes so byte-capped truncation never splits
// a character (which would make later String ops throw).
private func utf8FloorLen(arr: Array<Byte>, n: Int64): Int64 {
    var cut = n
    if (cut > arr.size) { cut = arr.size }
    while (cut > 0 && isContByte(arr[cut])) { cut -= 1 }
    cut
}

// Longest prefix of `line` within maxBytes bytes that ends on a UTF-8
// character boundary, so byte-capped truncation never splits a character
// (which would make later String ops throw).
private func truncateUtf8(line: String, maxBytes: Int64): String {
    if (line.size <= maxBytes) { return line }
    let lb = line.toArray()
    line[0..utf8FloorLen(lb, maxBytes)]
}

private func readOneLine(bis: BufferedInputStream<File>, maxBytes: Int64): ?String {
    let buf = ArrayList<Byte>()
    while (buf.size < maxBytes) {
        match (bis.readByte()) {
            case None =>
                return if (buf.size == 0) { None } else { Some(String.fromUtf8(buf.toArray())) }
            case Some(b) =>
                if (b == 0x0Au8) {
                    return Some(String.fromUtf8(buf.toArray()))
                }
                buf.add(b)
        }
    }
    Some(truncateUtf8(String.fromUtf8(buf.toArray()), maxBytes))
}

// Reads specific lines from a file (or inline source), bounded by maxBytes per line.
// Returns a map of line number (1-based) to line content.
// Missing lines (out of range) are omitted from the result.
private func readLines(
    filename: String,
    lineNos: Array<Int64>,
    maxBytes: Int64,
    source: ?String,
    allowInline: Bool
): HashMap<Int64, String> {
    let result = HashMap<Int64, String>()
    if (lineNos.size == 0) { return result }
    
    // Inline source path
    if (allowInline) {
        match (source) {
            case Some(text) =>
                let lines = text.split("\n")
                for (lineNum in lineNos) {
                    if (lineNum >= 1 && lineNum <= lines.size) {
                        result.add(lineNum, truncateUtf8(lines[lineNum - 1], maxBytes))
                    }
                }
                return result
            case None => ()
        }
    }
    
    // Disk path
    try (f = File(filename, Read)) {
        let bis = BufferedInputStream<File>(f)
        let sorted = ArrayList<Int64>(lineNos)
        sort(sorted, by: { a: Int64, b: Int64 => a.compare(b) })
        var currentLine = 1
        for (target in sorted) {
            while (currentLine <= target) {
                match (readOneLine(bis, maxBytes)) {
                    case Some(line) =>
                        if (currentLine == target) { result.add(target, line) }
                        currentLine += 1
                    case None => return result  // EOF
                }
            }
        }
    } catch (e: Exception) {
        // Missing file or read error - return empty map
    }
    result
}

// Line number left-padded to `width` columns.
private func numPad(n: Int64, width: Int64): String {
    let s = n.toString()
    repeatStr(" ", width - s.size) + s
}

// Groups labels by start line, preserving encounter order within a line.
private func groupByLine(labels: ArrayList<Label>): HashMap<Int64, ArrayList<Label>> {
    let byLine = HashMap<Int64, ArrayList<Label>>()
    for (label in labels) {
        let ln = label.range.startLine
        if (!byLine.contains(ln)) { byLine.add(ln, ArrayList<Label>()) }
        byLine[ln].add(label)
    }
    byLine
}

// Display-column span (caret start, caret end) of a label on its source line.
private func labelSpanCols(content: String, label: Label): (Int64, Int64) {
    let cp = displayColAtByte(content, label.range.startColumn - 1)
    let ce = if (label.range.endColumn > label.range.startColumn) {
        displayColAtByte(content, label.range.endColumn - 1)
    } else {
        cp + 1
    }
    (cp, ce)
}

/**
 * Human-readable terminal output with source context, carets, and ANSI colors.
 *
 * Width is the tightest of maxWidth, terminal width, and COLUMNS. Color
 * follows the termstandard/colors conventions: NO_COLOR disables; else
 * CLICOLOR_FORCE (non-empty, not "0") forces on; CLICOLOR=0 or TERM=dumb
 * disable; empty values count as unset.
 */
public class CLIDiagnosticFace <: DiagnosticFace {
    private let maxWidth: Int64
    private let colorMode: ?Bool

    // maxWidth, terminal width, and COLUMNS are all caps; the effective width is
    // the tightest of them. color follows the source setting unless
    // CLICOLOR_FORCE forces it on or NO_COLOR/TERM=dumb disables it.
    public init(maxWidth!: ?Int64 = None, color!: ?Bool = None) {
        this.maxWidth = resolveWidth(maxWidth, ttyWidth(), getVariable("COLUMNS"))
        this.colorMode = color
    }

    private func useColor(): Bool {
        resolveColor(this.colorMode, getVariable("NO_COLOR"), getVariable("TERM"),
            getVariable("CLICOLOR_FORCE"), getVariable("CLICOLOR"))
    }

    private func color(s: String, ansi: String): String {
        if (this.useColor()) { "${ansi}${s}${ANSI_RESET}" } else { s }
    }

    public func render(diagnostics: Array<Diagnostic>, source: ?String, sink: OutputStream): Unit {
        // Sort by (filename, startLine, startColumn) for stable output.
        let sorted = sortDiagnostics(diagnostics)

        for ((i, diag) in sorted.iterator().enumerate()) {
            if (i > 0) { sink.write("\n".toArray()) }
            this.renderOne(diag, source, sink)
        }
    }

    private func sortDiagnostics(arr: Array<Diagnostic>): Array<Diagnostic> {
        let list = ArrayList<Diagnostic>(arr)
        let comparator = { a: Diagnostic, b: Diagnostic =>
            if (a.filename != b.filename) { a.filename.compare(b.filename) }
            else {
                let la = lineOf(a)
                let lb = lineOf(b)
                if (la != lb) { la.compare(lb) }
                else { colOf(a).compare(colOf(b)) }
            }
        }
        sort(list, by: comparator)
        list.toArray()
    }

    private func posOf(d: Diagnostic, get: (DiagnosticRange) -> Int64): Int64 {
        match (d.range) {
            case Some(r) => get(r)
            case None => -1
        }
    }

    private func lineOf(d: Diagnostic): Int64 { posOf(d, { r: DiagnosticRange => r.startLine }) }

    private func colOf(d: Diagnostic): Int64 { posOf(d, { r: DiagnosticRange => r.startColumn }) }

    public func renderOne(diag: Diagnostic, source: ?String, sink: OutputStream): Unit {
        let out = try {
            let sb = StringBuilder()
            // Header: severity[code]: message (rustc-style); [code] omitted when empty.
            let severityStr = diag.severity.toString()
            let codePart = if (diag.code.isEmpty()) { "" } else { "[${diag.code}]" }
            let prefixLen = "${severityStr}${codePart}: ".size
            let coloredHead = color("${severityStr}${codePart}", severityAnsi(diag.severity))
            let msgLines = diag.message.split("\n")
            sb.append("${coloredHead}: ${msgLines[0]}\n")
            // Continuation lines align under the message's first character.
            for (i in 1..msgLines.size) {
                sb.append("${repeatStr(" ", prefixLen)}${msgLines[i]}\n")
            }

            // Multi-label rendering: every locatable diagnostic has labels
            // (Diagnostic.init synthesizes one from a bare range), so this
            // is the only source-frame path.
            sb.append(renderMultiLabel(diag, source))

            // Related-info notes (no source blocks; ranged rels would
            // duplicate what a ::: sub-frame already shows).
            for (rel in diag.relatedInfo) {
                this.appendRelNote(sb, rel)
            }

            sb.toString()
        } catch (e: Exception) {
            // Pipeline-safety fallback: a rendering bug must never crash a
            // build/log pipeline. Silently degrade to a minimal header.
            "${diag.severity.toString()}: ${diag.message}"
        }
        sink.write(out.toArray())
    }

    // Renders a diagnostic with multiple labels, grouped by file.
    // Labels within the same file are sorted by position and shown in one code frame.
    // Gaps > 2 lines are shown with "...".
    private func renderMultiLabel(diag: Diagnostic, source: ?String): String {
        let sb = StringBuilder()
        
        // Group labels by filename
        let byFile = HashMap<String, ArrayList<Label>>()
        for (label in diag.labels) {
            if (!byFile.contains(label.filename)) {
                byFile.add(label.filename, ArrayList<Label>())
            }
            byFile[label.filename].add(label)
        }
        
        // Render each file group
        let filenames = byFile.keys().iterator() |> collectArray
        sort(filenames)
        if (filenames.size == 0) {
            // Nothing locatable (range was None): still announce the file,
            // matching the old single-range header for location-less diags.
            sb.append("  ${color("==>", ANSI_CYAN)} ${diag.filename}\n")
        }
        for (filename in filenames) {
            let labels = byFile[filename]
            // Sort labels by (line, column)
            sortLabels(labels)
            
            // Render this file's labels
            sb.append(renderFileLabels(filename, labels, source, diag.severity))
        }
        
        sb.toString()
    }

    // Emits the "= note: message: file:line:col" line plus any continuation
    // lines, indented to align under the note text.
    private func appendRelNote(sb: StringBuilder, rel: RelatedInfo): Unit {
        let relLocStr = match (rel.range) {
            case Some(r) => "${rel.filename}:${r.startLine}:${r.startColumn}"
            case None => rel.filename
        }
        let relLines = rel.message.split("\n")
        sb.append("  ${color("= note", ANSI_CYAN)}: ${relLines[0]}: ${relLocStr}\n")
        for (i in 1..relLines.size) {
            sb.append("${repeatStr(" ", 9)}${relLines[i]}\n")
        }
    }

    // Sorts labels by (startLine, startColumn); stable insertion sort keeps
    // equal-position labels in encounter order.
    private func sortLabels(labels: ArrayList<Label>): Unit {
        for (i in 1..labels.size) {
            let key = labels[i]
            var j = i - 1
            while (j >= 0 && compareLabels(labels[j], key) > 0) {
                labels[j + 1] = labels[j]
                j = j - 1
            }
            labels[j + 1] = key
        }
    }

    private func compareLabels(a: Label, b: Label): Int64 {
        if (a.range.startLine < b.range.startLine) { return -1 }
        if (a.range.startLine > b.range.startLine) { return 1 }
        if (a.range.startColumn < b.range.startColumn) { return -1 }
        if (a.range.startColumn > b.range.startColumn) { return 1 }
        0
    }

    // Renders all labels from a single file. Labels that are far apart — in
    // lines (gap > 2) or columns (their caret spans cannot share one window) —
    // are split into separate sub-frames. The first sub-frame uses a "==>"
    // header; each later one uses "::: file:line:col" (rustc convention), with
    // just the location. Within every sub-frame each label still renders its
    // carets and message normally.
    private func renderFileLabels(filename: String, labels: ArrayList<Label>, source: ?String, severity: DiagnosticSeverity): String {
        let sb = StringBuilder()
        sortLabels(labels)

        let labelLines = groupByLine(labels)
        let sortedLineNums = labelLines.keys().iterator() |> collectArray
        sort(sortedLineNums)

        // Labels are grouped per file, so at least one labeled line exists.
        let width = sortedLineNums[sortedLineNums.size - 1].toString().size
        let bg = this.budget(width)

        // Read every labeled line, every gap==2 mid-line, and both ±1
        // neighbors of each labeled line up front. Neighbors are candidates:
        // they become context rows only in single-labeled-line sub-frames.
        let lineNumsList = ArrayList<Int64>()
        var prev: Int64 = 0
        for (ln in sortedLineNums) {
            if (prev > 0 && ln - prev == 2) { lineNumsList.add(prev + 1) }
            lineNumsList.add(ln)
            prev = ln
        }
        for (ln in sortedLineNums) {
            if (ln - 1 >= 1 && !lineNumsList.contains(ln - 1)) { lineNumsList.add(ln - 1) }
            if (!lineNumsList.contains(ln + 1)) { lineNumsList.add(ln + 1) }
        }
        let readResult = readLines(filename, lineNumsList.toArray(), this.readCap(), source, true)
        let linesToShow = HashMap<Int64, String>()
        for (ln in lineNumsList) {
            linesToShow.add(ln, readResult.get(ln) ?? "")
        }

        // Partition into sub-frames. A new sub-frame starts when the next
        // label is far in lines (gap > 2) or far in columns (the union of
        // caret spans would not fit one content window of width bg - 6).
        let frames = ArrayList<ArrayList<Label>>()
        var cur = ArrayList<Label>()
        var cmin: Int64 = 0
        var cmax: Int64 = 0
        var lastLine: Int64 = 0
        for (label in labels) {
            let content = linesToShow.get(label.range.startLine) ?? ""
            let (cp, ce) = labelSpanCols(content, label)
            let nmin = if (cur.size > 0 && cp > cmin) { cmin } else { cp }
            let nmax = if (cur.size > 0 && ce < cmax) { cmax } else { ce }
            if (cur.size > 0 && (label.range.startLine - lastLine > 2 || nmax - nmin > bg - 6)) {
                frames.add(cur)
                cur = ArrayList<Label>()
                cmin = cp
                cmax = ce
            } else {
                cmin = nmin
                cmax = nmax
            }
            cur.add(label)
            lastLine = label.range.startLine
        }
        if (cur.size > 0) { frames.add(cur) }

        // Context rows: a sub-frame containing exactly ONE labeled line pulls
        // that line's fetched neighbors as blank-gutter rows. Blank neighbors
        // render as empty rows instead of being skipped, keeping the vertical
        // rhythm intact. Multi-line frames skip context entirely so it never
        // interacts with joining, union anchors, or gap-mids.
        let frameCtx = ArrayList<Array<Int64>>()
        var renderWidth = width
        for (frame in frames) {
            var ctx = Array<Int64>()
            if (groupByLine(frame).size == 1) {
                let ln = frame[0].range.startLine
                let cands = ArrayList<Int64>()
                if (ln - 1 >= 1 && readResult.contains(ln - 1)) { cands.add(ln - 1) }
                if (readResult.contains(ln + 1)) { cands.add(ln + 1) }
                ctx = cands.toArray()
            }
            frameCtx.add(ctx)
            for (cand in ctx) {
                let w = cand.toString().size
                if (w > renderWidth) { renderWidth = w }
            }
        }
        let renderBg = this.budget(renderWidth)

        // Sub-frame headers always print. Bodies need something readable:
        // fetched lines, inline source, or an openable file. A file whose
        // requested lines are past EOF still renders its labeled rows (empty
        // content, clamped carets); an unreadable file renders header-only.
        let showBody = readResult.size > 0 || source.isSome() || fileReadable(filename)
        // Gutter rows put the pipe at column width+1 (numPad field + " | ").
        // Indenting the marker by `width` lands its middle character on that
        // same column for every gutter size.
        let headerPad = repeatStr(" ", renderWidth)
        for ((i, frame) in frames.iterator().enumerate()) {
            let header = if (i == 0) { "==>" } else { ":::" }
            let first = frame[0]
            sb.append("${headerPad}${color(header, ANSI_CYAN)} ${filename}:${first.range.startLine}:${first.range.startColumn}\n")
            if (showBody) {
                renderOneFrame(sb, frame, linesToShow, renderWidth, renderBg, severity, frameCtx[i])
            }
        }

        sb.toString()
    }

    // Gutter rows put the pipe at column width+1. `numStr` arrives
    // pre-padded (and pre-colored); `body` arrives pre-colored where needed.
    private func gutterRow(sb: StringBuilder, width: Int64, body: String): Unit {
        sb.append("${repeatStr(" ", width)} ${color("|", ANSI_CYAN)} ${body}\n")
    }

    private func numRow(sb: StringBuilder, numStr: String, body: String): Unit {
        sb.append("${numStr} ${color("|", ANSI_CYAN)} ${body}\n")
    }

    // Union of the labels' caret spans in display columns of `content`:
    // (anchorCs, anchorCl) for window anchoring — leftmost span start,
    // rightmost end, length clamped to >= 1.
    private func spanAnchor(content: String, labels: ArrayList<Label>): (?Int64, Int64) {
        var anchorCs: ?Int64 = None
        var anchorCe: Int64 = 0
        for (label in labels) {
            let (cp, ce) = labelSpanCols(content, label)
            match (anchorCs) {
                case None =>
                    anchorCs = Some(cp)
                    anchorCe = ce
                case Some(c) =>
                    if (cp < c) { anchorCs = Some(cp) }
                    if (ce > anchorCe) { anchorCe = ce }
            }
        }
        let anchorCl = match (anchorCs) {
            case Some(cs) => if (anchorCe - cs < 1) { 1 } else { anchorCe - cs }
            case None => 1
        }
        (anchorCs, anchorCl)
    }
    // Renders one sub-frame: its labeled lines in order (with a mid line when
    // the gap is exactly 2), each line windowed to the budget with its carets,
    // plus any context rows — unlabeled ±1 neighbors of a single-labeled-line
    // frame — rendered with a blank gutter and sharing the labeled line's
    // window so their columns line up with it. Gaps here are always <= 2
    // (a gap > 2 would have started a new sub-frame).
    private func renderOneFrame(sb: StringBuilder, frame: ArrayList<Label>, linesToShow: HashMap<Int64, String>, width: Int64, bg: Int64, severity: DiagnosticSeverity, ctxRows: Array<Int64>): Unit {
        let labelLines = groupByLine(frame)
        let frameLines = labelLines.keys().iterator() |> collectArray
        sort(frameLines)

        // Context rows exist only on single-labeled-line frames; they reuse
        // that line's window geometry instead of anchoring at column 0.
        var ctxKeep: Int64 = 0
        var ctxLeft = false
        var ctxRight = false
        var ctxVis: Int64 = 0
        if (ctxRows.size > 0 && frameLines.size > 0) {
            let ln0 = frameLines[0]
            let content0 = linesToShow.get(ln0) ?? ""
            let (acs, acl) = spanAnchor(content0, labelLines.get(ln0) ?? ArrayList<Label>())
            let exp0 = expandTabs(content0)
            let (_, wA, lA, rA, kA) = windowLineGeom(exp0, bg, acs, acl)
            var w = wA
            var l = lA
            var r = rA
            var k = kA
            if (k <= 0) {
                // Short or empty center line: no usable anchored window.
                // Fall back to an unanchored left-aligned slice so context
                // rows still show real content.
                w = 0
                l = false
                r = false
                k = bg
            }
            // The labeled row's content visually starts at the floored char
            // boundary of w on ITS grid; context rows must match that column.
            ctxVis = displayColAtByte(exp0, byteAtDisplayCol(exp0, w))
            ctxKeep = k
            ctxLeft = l
            ctxRight = r
        }

        let merged = ArrayList<Int64>()
        for (ln in frameLines) { merged.add(ln) }
        for (cn in ctxRows) { merged.add(cn) }
        let walk = merged.toArray()
        sort(walk)

        var prevLabeled: Int64 = 0
        var prevWalked: Int64 = -1
        for (num in walk) {
            if (prevWalked == num) { continue }
            prevWalked = num
            if (!labelLines.contains(num)) {
                // Context row: blank gutter, shared window. Blank neighbors
                // render as empty rows so the vertical rhythm stays intact.
                let rawCtx = expandTabs(linesToShow.get(num) ?? "")
                let ctxDisp = if (rawCtx.trimAscii().isEmpty()) {
                    ""
                } else {
                    contextWindow(rawCtx, ctxVis, ctxKeep, ctxLeft, ctxRight)
                }
                gutterRow(sb, width, ctxDisp)
                continue
            }
            if (prevLabeled > 0 && num - prevLabeled == 2) {
                let midContent = linesToShow.get(num - 1) ?? ""
                let (midDisp, _, _) = windowLine(expandTabs(midContent), bg, None, 0)
                numRow(sb, color(numPad(num - 1, width), ANSI_CYAN), midDisp)
            }
            let content = linesToShow.get(num) ?? ""
            let labelsOnLine = labelLines.get(num) ?? ArrayList<Label>()

            // Window the line to the budget. The window anchors on the
            // leftmost caret start (anchorCs) and spans to the rightmost
            // caret end (anchorCe), so all carets in the frame stay visible.
            let (anchorCs, anchorCl) = spanAnchor(content, labelsOnLine)
            let (disp, ws, left, right, keep) = windowLineGeom(expandTabs(content), bg, anchorCs, anchorCl)
            let leftMargin = if (left) { 3 } else { 0 }
            numRow(sb, color(numPad(num, width), ANSI_CYAN), disp)

            // A caret at raw display column cp maps to content column cp - ws.
            // If that falls outside [0, keep) while the line overflowed, the
            // caret is off-window and its message demotes to a note; otherwise
            // it renders at s1 = (cp - ws) + leftMargin, length clamped to
            // keep - s2 so it never runs into the right "...". Message is full.
            for (label in labelsOnLine) {
                let (cp, ce) = labelSpanCols(content, label)
                var clc = ce - cp
                if (clc < 1) { clc = 1 }
                let labelColor = match (label.style) {
                    case Some(LabelStyle.Secondary) => ANSI_BLUE
                    case _ => severityAnsi(severity)
                }
                let s2 = cp - ws
                if ((left || right) && (s2 < 0 || s2 >= keep)) {
                    gutterRow(sb, width, "${color("= note", ANSI_CYAN)}: ${label.message}")
                } else {
                    let caretsLen = caretLen(clc, s2, keep, right)
                    let s1 = s2 + leftMargin
                    let caretSpaces = repeatStr(" ", s1)
                    let carets = repeatStr("^", caretsLen)
                    var seg = carets
                    if (!label.message.isEmpty()) {
                        seg = carets + " " + label.message
                    }
                    gutterRow(sb, width, "${caretSpaces}${color(seg, labelColor)}")
                }
            }
            prevLabeled = num
        }
    }

    private func severityAnsi(s: DiagnosticSeverity): String {
        match (s) {
            case Error => ANSI_RED
            case Warning => ANSI_YELLOW
            case Information | Hint => ANSI_BLUE
        }
    }

    private func budget(lineNumWidth: Int64): Int64 {
        let b = this.maxWidth - lineNumWidth - 3
        if (b < 3) { 3 } else { b }
    }

    // Maximum bytes to read per source line. Tied to display budget to bound
    // memory for very long lines while covering tab expansion + windowing.
    // The absolute floor keeps labeled columns of realistic source lines
    // loadable even at degenerate widths — a line truncated before its own
    // span would render a window that lies about the code.
    private func readCap(): Int64 {
        let cap = this.maxWidth * 20
        if (cap < READ_CAP_FLOOR) { READ_CAP_FLOOR } else { cap }
    }

    private func fileReadable(filename: String): Bool {
        try {
            let f = File(filename, Read)
            f.close()
            true
        } catch (_) {
            false
        }
    }
}
