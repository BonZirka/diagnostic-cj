//
// cjpm build script: compiles the native terminal-width helper (native/terminal_size.c)
// into build/native/libterminal_size.a before the library is compiled, and removes
// it on clean. The archive is referenced from cjpm.toml via "-L build/native".

import std.process.{Process, executeWithOutput}

let NATIVE_DIR = "native/out"
let NATIVE_SRC = "native/terminal_size.c"
let NATIVE_OBJ = "${NATIVE_DIR}/terminal_size.o"
let NATIVE_LIB = "${NATIVE_DIR}/libterminal_size.a"

// Runs a command, forwarding its output; returns success.
func run(cmd: String, args: Array<String>): Bool {
    let (code, out, err) = executeWithOutput(cmd, args)
    let outStr = String.fromUtf8(out)
    let errStr = String.fromUtf8(err)
    if (!outStr.isEmpty()) { println(outStr) }
    if (!errStr.isEmpty()) { eprintln(errStr) }
    code == 0
}

// Builds the native static library before the package is compiled.
func stagePreBuild(): Int64 {
    if (!run("mkdir", ["-p", NATIVE_DIR])) { return 1 }
    if (!run("cc", ["-c", NATIVE_SRC, "-o", NATIVE_OBJ])) { return 1 }
    if (!run("ar", ["rcs", NATIVE_LIB, NATIVE_OBJ])) { return 1 }
    0
}

// Removes the native build artifacts on clean.
func stagePreClean(): Int64 {
    if (!run("rm", ["-rf", NATIVE_DIR])) { return 1 }
    0
}

main(): Int64 {
    match (Process.current.arguments[0]) {
        case "pre-build" => stagePreBuild()
        case "pre-clean" => stagePreClean()
        case _ => 0
    }
}
