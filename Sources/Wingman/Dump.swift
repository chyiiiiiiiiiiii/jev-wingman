import ApplicationServices
import Foundation
import WingmanCore

/// `Wingman --dump [--full]`: print what Wingman reads from Slack right now, then exit.
/// Text is redacted to its first two characters unless `--full` is given.
enum Dump {
    static func run(full: Bool) -> Int32 {
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
        return 0
    }
}
