import AppKit

let arguments = CommandLine.arguments
if arguments.contains("--dump") {
    exit(Dump.run(full: arguments.contains("--full"), trace: arguments.contains("--trace")))
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }   // NSApplication holds its delegate weakly
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
