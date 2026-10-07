import CoreGraphics

/// Where the pill and the panel go, in AppKit coordinates (origin at the bottom left of the primary screen).
/// `screens` are visible frames, without the menu bar and the Dock. Each stays on the screen its message box is on.
public enum Placement {
    /// Above the message box with their left edges lined up; pushed down and in when that would leave the screen.
    public static func above(_ composer: CGRect, size: CGSize, gap: CGFloat, screens: [CGRect]) -> CGRect {
        inside(CGRect(x: composer.minX, y: composer.maxY + gap, width: size.width, height: size.height),
               screen(of: composer, in: screens))
    }

    /// Just above the message box's top right corner.
    public static func pill(_ size: CGSize, over composer: CGRect, screens: [CGRect]) -> CGRect {
        inside(CGRect(x: composer.maxX - size.width - 10, y: composer.maxY + 6, width: size.width, height: size.height),
               screen(of: composer, in: screens))
    }

    /// The screen holding the box's top edge, or the nearest one when the edge is in none (behind the Dock).
    static func screen(of composer: CGRect, in screens: [CGRect]) -> CGRect? {
        let top = CGPoint(x: composer.midX, y: composer.maxY - 1)
        func distance(_ screen: CGRect) -> CGFloat {
            let dx = max(screen.minX - top.x, 0, top.x - screen.maxX), dy = max(screen.minY - top.y, 0, top.y - screen.maxY)
            return dx * dx + dy * dy
        }
        return screens.min { distance($0) < distance($1) }
    }

    static func inside(_ frame: CGRect, _ screen: CGRect?) -> CGRect {
        guard let screen else { return frame }
        var frame = frame
        frame.origin.x = max(screen.minX, min(frame.minX, screen.maxX - frame.width))
        frame.origin.y = max(screen.minY, min(frame.minY, screen.maxY - frame.height))
        return frame
    }
}
