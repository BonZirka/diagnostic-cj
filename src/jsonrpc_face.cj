package diagnostic

import std.collection.*
import std.env.*
import std.fs.*
import std.io.*

import stdx.serialization.serialization.*
import stdx.encoding.json.*

// Resolves a path to its canonical absolute form; "" when the path does not
// exist on disk.
private func canonicalPath(path: String): String {
    if (!exists(path)) {
        return ""
    }
    canonicalize(Path(path)).toString()
}

/**
 * LSP-compatible `textDocument/publishDiagnostics` JSON-RPC output.
 */
public class JsonRpcDiagnosticFace <: DiagnosticFace {
    public func render(diagnostics: Array<Diagnostic>, _: ?String, sink: OutputStream): Unit {
        // Group by filename, emit one NotificationMessage per file.
        let byFile = HashMap<String, ArrayList<Diagnostic>>()
        for (d in diagnostics) {
            if (!byFile.contains(d.filename)) {
                byFile.add(d.filename, ArrayList<Diagnostic>())
            }
            byFile[d.filename].add(d)
        }

        if (byFile.size > 1) {
            sink.write("[".toArray())
        }
        var first = true
        for ((filename, fileDiags) in byFile) {
            if (!first) { sink.write(",".toArray()) }
            first = false
            sink.write(renderNotification(filename, fileDiags.toArray()).toArray())
        }
        if (byFile.size > 1) {
            sink.write("]".toArray())
        }
    }

    public func renderOne(d: Diagnostic, _: ?String, sink: OutputStream): Unit {
        // Render a single diagnostic as a single-file notification.
        sink.write(renderNotification(d.filename, [d]).toArray())
    }

    private func renderNotification(filename: String, diags: Array<Diagnostic>): String {
        let uri = uriFromFilename(filename)
        let dm = buildDataModel(uri, diags)
        let jsonValue = dm.toJson()
        let jsonObj = match (jsonValue as JsonObject) {
            case Some(obj) => obj
            case None => JsonObject()
        }
        jsonObj.toJsonString(0, indent: "  ")
    }

    private func uriFromFilename(filename: String): String {
        // canonicalPath resolves to an absolute path; if the file doesn't exist,
        // construct an absolute path using CWD.
        var absPath = canonicalPath(filename)
        if (absPath.isEmpty()) {
            let cwd = try { getWorkingDirectory().toString() } catch (e: Exception) { "" }
            absPath = if (filename.startsWith("/")) { filename } else { "${cwd}/${filename}" }
        }
        if (absPath.startsWith("/")) {
            "file://${absPath}"
        } else {
            "file:///${absPath}"
        }
    }

    private func buildDataModel(uri: String, diags: Array<Diagnostic>): DataModelStruct {
        let diagArray = DataModelSeq(diags.iterator().map { it => buildDiagnosticDataModel(it) } |> collectArrayList)
        DataModelStruct()
            .add(field<String>("jsonrpc", "2.0"))
            .add(field<String>("method", "textDocument/publishDiagnostics"))
            .add(Field("params", DataModelStruct()
                .add(field<String>("uri", uri))
                .add(Field("diagnostics", diagArray))
            ))
    }

    private func buildDiagnosticDataModel(d: Diagnostic): DataModel {
        let rangeDm = match (d.range) {
            case Some(r) => buildRangeDataModel(r)
            case None => buildZeroRangeDataModel()
        }
        var `struct` = DataModelStruct()
            .add(Field("range", rangeDm))
            .add(field<Int64>("severity", d.severity.toLspNumber()))
            .add(field<String>("code", d.code))
            .add(field<String>("source", d.source))
            .add(field<String>("message", d.message))
        if (d.relatedInfo.size > 0) {
            let relArray = d.relatedInfo.iterator().map { it => buildRelatedInfoDataModel(it) } |> collectArrayList
            `struct` = `struct`.add(Field("relatedInformation", DataModelSeq(relArray)))
        }
        `struct`
    }

    // LSP range is 0-based; DiagnosticRange is 1-based. Convert.
    private func buildRangeDataModel(r: DiagnosticRange): DataModel {
        DataModelStruct()
            .add(Field("start", DataModelStruct()
                .add(field<Int64>("line", r.startLine - 1))
                .add(field<Int64>("character", r.startColumn - 1))))
            .add(Field("end", DataModelStruct()
                .add(field<Int64>("line", r.endLine - 1))
                .add(field<Int64>("character", r.endColumn - 1))))
    }

    private func buildZeroRangeDataModel(): DataModel {
        buildRangeDataModel(DiagnosticRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1))
    }

    private func buildRelatedInfoDataModel(rel: RelatedInfo): DataModel {
        let rangeDm = match (rel.range) {
            case Some(r) => buildRangeDataModel(r)
            case None => buildZeroRangeDataModel()
        }
        DataModelStruct()
            .add(Field("location", DataModelStruct()
                .add(field<String>("uri", uriFromFilename(rel.filename)))
                .add(Field("range", rangeDm))))
            .add(field<String>("message", rel.message))
    }
}
