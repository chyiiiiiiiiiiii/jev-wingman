import AppKit
import ApplicationServices
import WingmanCore

/// A detached copy of an app's focused window, plus the live element behind every node
/// (`UINode.handle` indexes `elements`) so the app can act on what the parser found.
struct AXSnapshot {
    let root: UINode
    let elements: [AXUIElement]

    private static let attributes = [
        kAXRoleAttribute, "AXDOMClassList", kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXFocusedAttribute, kAXChildrenAttribute,
    ] as CFArray

    /// Chromium and Electron build their accessibility tree only once a client asks for it.
    static func enableWebAccessibility(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    init?(pid: pid_t, maxNodes: Int = 5000) {
        guard let window = Self.focusedWindow(pid: pid) else { return nil }
        var elements: [AXUIElement] = []
        func build(_ element: AXUIElement) -> UINode {
            let handle = elements.count
            elements.append(element)
            var values: CFArray?
            AXUIElementCopyMultipleAttributeValues(element, Self.attributes, [], &values)
            let v = (values as? [AnyObject]) ?? []
            func at(_ i: Int) -> AnyObject? { i < v.count ? v[i] : nil }
            var node = UINode(role: Self.string(at(0)), classes: (at(1) as? [String]) ?? [],
                              title: Self.string(at(2)), value: Self.string(at(3)), desc: Self.string(at(4)),
                              frame: Self.frame(at(5), at(6)), focused: (at(7) as? Bool) ?? false, handle: handle)
            for child in (at(8) as? [AXUIElement]) ?? [] where elements.count < maxNodes {
                node.children.append(build(child))
            }
            return node
        }
        root = build(window)
        self.elements = elements
    }

    private static func string(_ value: AnyObject?) -> String {
        if let s = value as? String { return s }
        if let a = value as? NSAttributedString { return a.string }
        return ""
    }

    private static func frame(_ position: AnyObject?, _ size: AnyObject?) -> CGRect {
        guard let position, let size, CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return .zero }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }
}

enum Slack {
    static let bundleID = "com.tinyspeck.slackmacgap"

    static var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// Reads the conversation in Slack's focused window; nil when Slack or its composer is not there.
    static func read(pid: pid_t, myName: String?) -> (Conversation, AXSnapshot)? {
        guard let snapshot = AXSnapshot(pid: pid),
              let conversation = SlackParser.parse(window: snapshot.root, myName: myName) else { return nil }
        return (conversation, snapshot)
    }
}
