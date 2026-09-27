import ApplicationServices
import CoreGraphics
import Foundation
import WingmanCore

/// `Wingman --dump [--full]`: print what Wingman reads from Slack right now, then exit.
/// Text is redacted to its first two characters unless `--full` is given.
enum Dump {
    static func run(full: Bool, trace: Bool) -> Int32 {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to the process running this command.")
            return 1
        }
        guard let slack = Slack.running else {
            print("Slack is not running.")
            return 1
        }
        AXSnapshot.enableWebAccessibility(pid: slack.processIdentifier)
        Thread.sleep(forTimeInterval: 0.5)
        let myName = Prefs.storedMyName
        guard let (convo, snapshot) = Slack.read(pid: slack.processIdentifier, myName: myName) else {
            print("No Slack composer found in the focused window.")
            return 1
        }
        let show = { (s: String) in full || s.count <= 2 ? s : "\(s.prefix(2))…(\(s.count))" }
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
