package examples

import std.env.*

let EXAMPLE_NAMES = ["showcase", "basic_cli", "jsonrpc", "labels", "joining", "related_info", "configuration", "cjk", "longline", "neighbors", "longspan"]

// Everything is written through the same stdout sink and flushed, so output
// order stays correct whether stdout is a terminal or a pipe.
func writeOut(s: String): Unit {
    let out = getStdOut()
    out.write(s.toArray())
    out.flush()
}

func runByName(name: String): Bool {
    if (name == "showcase") {
        runShowcase()
        true
    } else if (name == "basic_cli") {
        runBasicCli()
        true
    } else if (name == "jsonrpc") {
        runJsonRpc()
        true
    } else if (name == "labels") {
        runLabels()
        true
    } else if (name == "joining") {
        runJoining()
        true
    } else if (name == "related_info") {
        runRelatedInfo()
        true
    } else if (name == "configuration") {
        runConfiguration()
        true
    } else if (name == "cjk") {
        runCjk()
        true
    } else if (name == "longline") {
        runLongLine()
        true
    } else if (name == "neighbors") {
        runNeighbors()
        true
    } else if (name == "longspan") {
        runLongSpan()
        true
    } else {
        false
    }
}

func runAll(): Unit {
    for (name in EXAMPLE_NAMES) {
        writeOut("=== ${name} ===\n")
        runByName(name)
        writeOut("\n")
    }
}

main(): Unit {
    let args = getCommandLine()
    let userArgs = args[1..args.size]
    if (userArgs.size >= 2 && userArgs[0] == "--example") {
        if (!runByName(userArgs[1])) {
            writeOut("unknown example: ${userArgs[1]}\n")
            writeOut("available: ${String.join(EXAMPLE_NAMES, delimiter: ", ")}\n")
        }
    } else {
        writeOut("Run all examples (default), or one with:\n")
        writeOut("  cjpm run -- --example <name>\n")
        writeOut("\n")
        writeOut("available: ${String.join(EXAMPLE_NAMES, delimiter: ", ")}\n")
        writeOut("\n")
        runAll()
    }
}
