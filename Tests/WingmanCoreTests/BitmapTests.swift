import CoreGraphics
import Testing
@testable import WingmanCore

/// A 400×200 px capture: `background` everywhere, a `bubble` behind the text box, and the text itself
/// drawn as a block of `ink` pixels. Colours are from captures of Telegram on 2026-10-12.
private func capture(background: [CGFloat], bubble: [CGFloat]? = nil, ink: [CGFloat] = [235, 238, 242]) -> (Bitmap, CGRect) {
    let context = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    func fill(_ rgb: [CGFloat], _ rect: CGRect) {
        context.setFillColor(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: 1)
        context.fill(rect)
    }
    let text = CGRect(x: 100, y: 85, width: 160, height: 30)   // centred, so flipping rows changes nothing
    fill(background, CGRect(x: 0, y: 0, width: 400, height: 200))
    if let bubble { fill(bubble, text.insetBy(dx: -16, dy: -12)) }
    // Glyph strokes: every other 4 px column of the box.
    for x in stride(from: text.minX, to: text.maxX, by: 8) { fill(ink, CGRect(x: x, y: text.minY + 6, width: 4, height: 18)) }
    return (Bitmap(context.makeImage()!), text)
}

@Test func aDarkBlueChatBackgroundIsNotAColouredBubble() {
    // Telegram's night theme without bubbles: the background alone is (19, 26, 34).
    let (bitmap, text) = capture(background: [19, 26, 34])
    #expect(bitmap.tint(around: text) < 0.25)
}

@Test func aBlueBubbleOnAGreyBackgroundIsColoured() {
    let (bitmap, text) = capture(background: [33, 33, 33], bubble: [43, 82, 160])
    #expect(bitmap.tint(around: text) >= 0.25)
}
