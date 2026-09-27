import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import WingmanCore

/// `Wingman --dump [--full]`: print what Wingman reads from Slack right now, then exit.
/// Text is redacted to its first two characters unless `--full` is given.
enum Dump {
    static func run(full: Bool, trace: Bool, wait: Bool) -> Int32 {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to the process running this command.")
            return 1
        }
        guard let slack = Slack.running else {
            print("Slack is not running.")
            return 1
        }
        AXSnapshot.enableWebAccessibility(pid: slack.processIdentifier)
        if wait {
            print("5 秒後讀取，請切到 Slack…")
            Thread.sleep(forTimeInterval: 5)
        }
        Thread.sleep(forTimeInterval: 0.5)
        let myName = Prefs.storedMyName
        let show = { (s: String) in full || s.count <= 2 ? s : "\(s.prefix(2))…(\(s.count))" }
        guard let (convo, snapshot) = Slack.read(pid: slack.processIdentifier, myName: myName) else {
            print("No Slack composer found. Windows Slack reports:")
            for window in AXSnapshot.windows(pid: slack.processIdentifier) {
                let root = AXSnapshot(window: window).root
                var nodes = 0, editors: [String] = []
                func visit(_ node: UINode) {
                    nodes += 1
                    if node.role == "AXTextArea" || node.role == "AXTextField" {
                        editors.append("\(node.role)[\(node.classes.prefix(2).joined(separator: "."))]")
                    }
                    node.children.forEach(visit)
                }
                visit(root)
                print("  \(show(root.title)) \(Int(root.frame.width))x\(Int(root.frame.height)) · \(nodes) nodes · "
                      + "text inputs: \(editors.isEmpty ? "none" : editors.joined(separator: ", "))")
            }
            return 1
        }
        print("nodes \(snapshot.elements.count) · me \(myName.map(show) ?? "(not set)")")
        print("title \(show(convo.title)) · \(convo.isThread ? "thread" : "channel") · draft \(convo.draft.count) chars")
        print("composer \(Int(convo.composerFrame.minX)),\(Int(convo.composerFrame.minY)) \(Int(convo.composerFrame.width))x\(Int(convo.composerFrame.height))")
        for m in convo.messages {
            let who = m.isMe ? "me" : (m.sender.map(show) ?? "?")
            let lines = m.text.split(separator: "\n").map { show(String($0)) }.joined(separator: " ⏎ ")
            print("  [\(who)] \(m.time.map(show) ?? "-") · \(lines)")
        }
        print("awaiting reply: \(convo.awaitingReply)")
        if trace { printTrace(snapshot.root, composer: convo.composerFrame, show: show) }
        return 0
    }

    /// `--probe <bundle id> [--wait]`: role, DOM classes and redacted text of every labelled node in
    /// an app's window, to learn where a new app keeps its messages before writing its reader.
    static func probe(bundleID: String, wait: Bool) -> Int32 {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { print("Not trusted, or \(bundleID) is not running."); return 1 }
        AXSnapshot.enableWebAccessibility(pid: app.processIdentifier)
        if wait {
            print("5 秒後讀取，請切到 \(app.localizedName ?? bundleID)…")
            Thread.sleep(forTimeInterval: 5)
        }
        // Electron builds its tree a few seconds after accessibility is switched on.
        var root: UINode?, counts: [Int] = []
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 1)
            guard let window = AXSnapshot.windows(pid: app.processIdentifier).first else { counts.append(0); continue }
            let snapshot = AXSnapshot(window: window)
            root = snapshot.root
            counts.append(snapshot.elements.count)
            if counts.count >= 2, counts.last! > 100, counts.last! == counts[counts.count - 2] { break }
        }
        print("front app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") · nodes over time: "
              + counts.map(String.init).joined(separator: " → "))
        guard let root else { print("No window."); return 1 }
        print("window \(Int(root.frame.width))x\(Int(root.frame.height)) “\(root.title.prefix(2))…”")
        let show = { (s: String) in s.count <= 2 ? s : "\(s.prefix(2))…(\(s.count))" }
        var printed = 0
        func visit(_ node: UINode, _ depth: Int) {
            guard printed < 260 else { return }
            let f = node.frame
            let x = (f.minX - root.frame.minX) / max(root.frame.width, 1), y = (f.minY - root.frame.minY) / max(root.frame.height, 1)
            if (!node.classes.isEmpty || !node.text.isEmpty) && x > 0.2 && f.height > 1 {
                print(String(repeating: " ", count: min(depth, 24))
                      + String(format: "%@ x=%.2f y=%.2f %@ %@", node.role, x, y,
                               node.text.isEmpty ? "" : "“\(show(node.text))”", node.classes.prefix(3).joined(separator: ".")))
                printed += 1
            }
            node.children.forEach { visit($0, depth + 1) }
        }
        visit(root, 0)
        print("printed \(printed)")
        return 0
    }

    /// Every text node in the conversation pane with the classes of its nearest ancestors, to find
    /// which Slack element a stray line in a message came from.
    private static func printTrace(_ root: UINode, composer: CGRect, show: (String) -> String) {
        print("--- text nodes in the pane, with ancestor classes")
        func visit(_ node: UINode, _ path: [String]) {
            let path = node.classes.isEmpty ? path : path + [node.classes.prefix(2).joined(separator: ".")]
            let f = node.frame
            if node.role == "AXStaticText", !node.value.isEmpty, f.height > 1, f.maxY <= composer.minY,
               f.minX >= composer.minX - 8, f.minX < composer.maxX {
                print("  \(show(node.value))  ←  \(path.suffix(3).joined(separator: " › "))")
            }
            node.children.forEach { visit($0, path) }
        }
        visit(root, [])
    }
}
