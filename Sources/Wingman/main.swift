import AppKit

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--probe"), index + 1 < arguments.count {
    exit(Dump.probe(bundleID: arguments[index + 1], wait: arguments.contains("--wait")))
}
if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
    exit(MainActor.assumeIsolated { Render.run(to: arguments[index + 1]) })
}
if arguments.contains("--dump") {
    exit(Dump.run(full: arguments.contains("--full"), trace: arguments.contains("--trace"),
              wait: arguments.contains("--wait")))
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }   // NSApplication holds its delegate weakly
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
