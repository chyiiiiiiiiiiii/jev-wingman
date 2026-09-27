import AppKit

/// Where Wingman's menu bar icon sits. On a Mac with a notch, a crowded menu bar puts the newest icons under
/// the notch, where they can be neither seen nor clicked, and macOS gives no sign of it.
enum MenuBarIcon {
    static let name = "Wingman"
    /// macOS keeps each icon's place as its distance from the screen's right edge.
    static let positionKey = "NSStatusItem Preferred Position \(name)"
    /// Just left of the Mac's own icons (clock 121 … Now Playing 468 on macOS 26): the visible side of any notch.
    static let visiblePosition = 470.0

    /// Whether the icon is under the notch or off the screen.
    @MainActor
    static func isHidden(_ item: NSStatusItem) -> Bool {
        guard let window = item.button?.window, let screen = window.screen ?? NSScreen.screens.first else { return false }
        let frame = window.frame
        if frame.width < 1 || frame.maxX <= screen.frame.minX || frame.minX >= screen.frame.maxX { return true }
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        // The two areas either side of the notch, in global coordinates whichever way the screen reports them.
        let shift = abs(left.minX - screen.frame.minX) < 1 ? 0 : screen.frame.minX
        func within(_ area: NSRect) -> Bool { frame.minX >= area.minX + shift - 1 && frame.maxX <= area.maxX + shift + 1 }
        return !within(left) && !within(right)
    }
}
