import CoreGraphics
import Testing
@testable import WingmanCore

// AppKit coordinates: origin at the bottom left of the primary screen. These are visible frames, without the
// menu bar and the Dock.
private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
private let leftMonitor = CGRect(x: -1920, y: -200, width: 1920, height: 1055)
private let panel = CGSize(width: 480, height: 460)

@Test func thePanelSitsAboveTheMessageBoxWhenThereIsRoom() {
    let composer = CGRect(x: 300, y: 80, width: 560, height: 40)
    #expect(Placement.above(composer, size: panel, gap: 8, screens: [laptop])
        == CGRect(x: 300, y: 128, width: 480, height: 460))
}

@Test func aMessageBoxHighOnTheScreenKeepsThePanelBelowTheTop() {
    // A short chat window near the top of the screen: the panel would rise past the menu bar.
    let composer = CGRect(x: 300, y: 700, width: 560, height: 40)
    let frame = Placement.above(composer, size: panel, gap: 8, screens: [laptop])
    #expect(frame.maxY == laptop.maxY)
    #expect(frame.minX == 300)
}

@Test func aMessageBoxAtTheRightEdgeKeepsThePanelOnScreen() {
    let composer = CGRect(x: 1300, y: 80, width: 200, height: 40)
    #expect(Placement.above(composer, size: panel, gap: 8, screens: [laptop]).maxX == laptop.maxX)
}

@Test func thePanelStaysOnTheScreenOfItsMessageBox() {
    // A chat on a second monitor to the left, lower than the laptop: it is clamped to that monitor.
    let composer = CGRect(x: -1500, y: 700, width: 560, height: 40)
    let frame = Placement.above(composer, size: panel, gap: 8, screens: [laptop, leftMonitor])
    #expect(frame.maxY == leftMonitor.maxY)
    #expect(frame.minX == -1500)
}

@Test func thePillSitsAtTheMessageBoxsTopRight() {
    let composer = CGRect(x: 300, y: 80, width: 560, height: 40)
    #expect(Placement.pill(CGSize(width: 120, height: 24), over: composer, screens: [laptop])
        == CGRect(x: 730, y: 126, width: 120, height: 24))
}
