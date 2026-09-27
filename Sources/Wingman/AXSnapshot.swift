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

    /// The focused window first, then the rest: a huddle or a pop-out can hold focus
    /// while the conversation sits in the main window.
    static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?, all: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused)
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &all)
        var windows: [AXUIElement] = []
        if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() { windows.append(focused as! AXUIElement) }
        for window in (all as? [AXUIElement]) ?? [] where !windows.contains(where: { CFEqual($0, window) }) {
            windows.append(window)
        }
        return windows
    }

    init(window: AXUIElement, maxNodes: Int = 5000) {
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

    /// Reads the conversation in the first Slack window that has a composer; nil when there is none.
    static func read(pid: pid_t, myName: String?) -> (Conversation, AXSnapshot)? {
        for window in AXSnapshot.windows(pid: pid) {
            let snapshot = AXSnapshot(window: window)
            if let conversation = SlackParser.parse(window: snapshot.root, myName: myName) {
                return (conversation, snapshot)
            }
        }
        return nil
    }
}
