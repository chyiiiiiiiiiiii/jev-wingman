import AppKit

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--probe"), index + 1 < arguments.count {
    // --region 0.3 0.8 keeps nodes whose left edge sits in that share of the window's width.
    let region = arguments.firstIndex(of: "--region").flatMap { i -> ClosedRange<Double>? in
        guard i + 2 < arguments.count, let low = Double(arguments[i + 1]), let high = Double(arguments[i + 2]) else { return nil }
        return low...high
    } ?? 0.2...1
    let limit = arguments.firstIndex(of: "--limit").flatMap { i in i + 1 < arguments.count ? Int(arguments[i + 1]) : nil } ?? 260
    let host = arguments.firstIndex(of: "--host").flatMap { i in i + 1 < arguments.count ? arguments[i + 1] : nil }
    exit(Dump.probe(bundleID: arguments[index + 1], wait: arguments.contains("--wait"), region: region, limit: limit,
                    host: host))
}
if let index = arguments.firstIndex(of: "--render-demo"), index + 1 < arguments.count {
    exit(MainActor.assumeIsolated { Render.demo(to: arguments[index + 1]) })
}
if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
    exit(MainActor.assumeIsolated { Render.run(to: arguments[index + 1]) })
}
if arguments.contains("--dump"), let index = arguments.firstIndex(of: "--app"), index + 1 < arguments.count,
   let app = ChatApp(rawValue: arguments[index + 1].lowercased()) {
    let wait = arguments.contains("--wait")
    let done = DispatchSemaphore(value: 0)
    var status: Int32 = 1
    Task.detached {
        status = await Dump.read(app: app, wait: wait)
        done.signal()
    }
    done.wait()
    exit(status)
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
