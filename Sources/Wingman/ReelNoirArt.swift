import AppKit
import SwiftUI
import WingmanCore

/// The flat pictures 〈訊息偵探社〉 pastes into its 3D world (a laptop's chat, cards on the evidence board,
/// the case file with Wingman's real panel in it) and the type laid over its frames.
@MainActor
enum NoirArt {
    static let paper = Color(red: 0.95, green: 0.91, blue: 0.82)
    static let ink = Color(red: 0.13, green: 0.11, blue: 0.10)
    static let red = Color(red: 0.80, green: 0.12, blue: 0.14)
    static func serif(_ size: Double, _ weight: Font.Weight = .bold) -> Font { .custom("Songti TC", size: size).weight(weight) }
    static func sans(_ size: Double, _ weight: Font.Weight = .medium) -> Font { .custom("PingFang TC", size: size).weight(weight) }

    /// A view drawn into a bitmap of `pixels`, laid out at `points`.
    static func picture(_ view: some View, points: CGSize, pixels: CGSize, dark: Bool = true) -> NSImage {
        let host = NSHostingView(rootView: view.frame(width: points.width, height: points.height)
            .environment(\.colorScheme, dark ? .dark : .light))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame.size = points
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = points
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: pixels)
        image.addRepresentation(bitmap)
        return image
    }

    // MARK: - The laptop's screen

    /// An Instagram-like chat with Ivy, large enough to read up close. `circled` rings the words of her last
    /// message one by one as the detective finds them; `sent` and `reply` are the end of the story.
    static func chat(lines: [Reel.Line], circled: Int = 0, sent: String? = nil, reply: String? = nil) -> NSImage {
        let view = VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .bottomLeading, endPoint: .topTrailing))
                    .frame(width: 26, height: 26)
                Text(lines.first { !$0.isMe }?.from ?? "").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("Instagram").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Divider()
            Spacer(minLength: 0)
            // Once the reply is written there is no room for the start of the chat.
            let shown = sent == nil ? lines : Array(lines.suffix(2))
            ForEach(Array(shown.enumerated()), id: \.offset) { index, line in
                let last = index == shown.count - 1
                bubble(line.text, me: line.isMe, circled: last && !line.isMe ? circled : 0)
            }
            if let sent { bubble(sent, me: true, circled: 0) }
            if let reply { bubble(reply, me: false, circled: 0) }
        }
        // A phone-width column in the middle of the screen, so a tall shot can hold all of it.
        .padding(.horizontal, 18).padding(.vertical, 20)
        .frame(width: 330)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .frame(width: 640, height: 400)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
        return picture(view, points: CGSize(width: 640, height: 400), pixels: CGSize(width: 1280, height: 800))
    }

    private static func bubble(_ text: String, me: Bool, circled: Int) -> some View {
        HStack {
            if me { Spacer(minLength: 36) }
            Group {
                if circled > 0, text == "哈哈 好啦 你很忙齁" {
                    // The three words under the glass, each ringed in red as it is found.
                    HStack(spacing: 12) {
                        ForEach(Array(["哈哈", "好啦", "你很忙齁"].enumerated()), id: \.offset) { i, word in
                            Text(word).overlay(Ellipse().stroke(red, lineWidth: 3.5).padding(-8).opacity(i < circled ? 1 : 0))
                        }
                    }
                } else {
                    Text(text)
                }
            }
            .font(sans(19))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(me ? Color(red: 0.36, green: 0.30, blue: 0.95) : Color(white: 0.22), in: RoundedRectangle(cornerRadius: 22))
            .fixedSize(horizontal: false, vertical: true)
            if !me { Spacer(minLength: 36) }
        }
    }

    // MARK: - The evidence board

    /// An index card pinned to the board, typed in a serif.
    static func card(_ title: String, _ body: String, tint: Color = Color(red: 0.95, green: 0.91, blue: 0.82)) -> NSImage {
        let view = VStack(alignment: .leading, spacing: 10) {
            Text(title).font(serif(18, .regular)).foregroundStyle(ink.opacity(0.6))
            Text(body).font(serif(30, .heavy)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 360, height: 240, alignment: .topLeading)
        .background(tint)
        return picture(view, points: CGSize(width: 360, height: 240), pixels: CGSize(width: 720, height: 480), dark: false)
    }

    /// Wingman's verdict on a report card, in the panel's own words and with its own mood bar.
    static func verdict(_ v: (sentence: String, tag: String, dot: Color), said: Reel.Said) -> NSImage {
        let view = VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 30, height: 30)
                Text("Wingman 鑑定").font(serif(20)).foregroundStyle(.white.opacity(0.75))
            }
            Text(v.sentence).font(sans(34, .heavy)).foregroundStyle(.white)
            HStack(spacing: 8) {
                Circle().fill(v.dot).frame(width: 12, height: 12)
                Text(v.tag).font(sans(20))
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color.white.opacity(0.12), in: Capsule())
            if let tension = said.tension {
                MoodBar(tension: tension, subtext: (said.subtext ?? 0) >= Brain.meaningful).scaleEffect(1.7, anchor: .leading)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(width: 480, height: 320, alignment: .topLeading)
        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
        .overlay(Rectangle().strokeBorder(Color(red: 0.31, green: 0.27, blue: 0.90), lineWidth: 6))
        return picture(view, points: CGSize(width: 480, height: 320), pixels: CGSize(width: 960, height: 640))
    }

    // MARK: - The case file

    /// An open manila folder: a typed label, and on the page Wingman's panel, or a message and its verdict.
    static func caseFile(number: String, title: String, panel: AppModel? = nil, message: Reel.Line? = nil,
                         app: ChatApp? = nil, verdict: (sentence: String, tag: String, dot: Color)? = nil) -> NSImage {
        let view = ZStack(alignment: .topLeading) {
            Color(red: 0.86, green: 0.72, blue: 0.48)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("CASE \(number)").font(.custom("American Typewriter", size: 30).weight(.bold)).foregroundStyle(ink)
                    Text(title).font(serif(28, .heavy)).foregroundStyle(ink)
                }
                if let panel {
                    SuggestionView(model: panel)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.13, green: 0.13, blue: 0.15)))
                        .environment(\.colorScheme, .dark)
                        .scaleEffect(1.25, anchor: .topLeading)
                } else if let message {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(app?.name ?? "") · \(message.from)\(message.time.map { " · \($0)" } ?? "")").font(sans(18)).foregroundStyle(ink.opacity(0.6))
                        Text(message.text).font(sans(30, .bold)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .frame(width: 600, alignment: .leading)
                    .background(paper)
                    if let verdict {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Wingman 鑑定").font(serif(20)).foregroundStyle(.white.opacity(0.7))
                            Text(verdict.sentence).font(sans(34, .heavy)).foregroundStyle(.white)
                            HStack(spacing: 8) { Circle().fill(verdict.dot).frame(width: 12, height: 12); Text(verdict.tag).font(sans(22)) }
                                .foregroundStyle(.white)
                        }
                        .padding(22)
                        .frame(width: 600, alignment: .leading)
                        .background(Color(red: 0.10, green: 0.10, blue: 0.14))
                    }
                }
            }
            .padding(36)
        }
        return picture(view, points: CGSize(width: 680, height: 900), pixels: CGSize(width: 1360, height: 1800), dark: false)
    }

    // MARK: - Small textures

    static func gradient(_ colors: [NSColor], size: CGSize = CGSize(width: 256, height: 256), angle: CGFloat = -60) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: colors)?.draw(in: rect, angle: angle)
            return true
        }
    }

    /// Planks, cork, wallpaper, brick and the city through the window, drawn once.
    static func pattern(_ kind: String) -> NSImage {
        NSImage(size: CGSize(width: 512, height: 512), flipped: false) { rect in
            var random = SystemRandomNumberGenerator()
            switch kind {
            case "wood":
                for i in 0..<8 {
                    let shade = CGFloat.random(in: 0.22...0.30, using: &random)
                    NSColor(red: shade + 0.08, green: shade * 0.62, blue: shade * 0.38, alpha: 1).setFill()
                    NSRect(x: 0, y: CGFloat(i) * 64, width: 512, height: 63).fill()
                    NSColor(white: 0, alpha: 0.35).setFill()
                    NSRect(x: 0, y: CGFloat(i) * 64 + 62, width: 512, height: 2).fill()
                    for _ in 0..<14 {
                        NSColor(white: 0, alpha: 0.06).setFill()
                        NSRect(x: 0, y: CGFloat(i) * 64 + CGFloat.random(in: 2...60, using: &random), width: 512, height: 1).fill()
                    }
                }
            case "cork":
                NSColor(red: 0.62, green: 0.44, blue: 0.26, alpha: 1).setFill()
                rect.fill()
                for _ in 0..<2600 {
                    NSColor(red: CGFloat.random(in: 0.35...0.8, using: &random), green: CGFloat.random(in: 0.25...0.55, using: &random),
                            blue: 0.18, alpha: 0.6).setFill()
                    NSBezierPath(ovalIn: NSRect(x: CGFloat.random(in: 0...512, using: &random), y: CGFloat.random(in: 0...512, using: &random),
                                                width: 3, height: 3)).fill()
                }
            case "wall":
                NSColor(red: 0.12, green: 0.20, blue: 0.20, alpha: 1).setFill()
                rect.fill()
                for i in 0..<16 {
                    NSColor(red: 0.16, green: 0.25, blue: 0.24, alpha: 1).setFill()
                    NSRect(x: CGFloat(i) * 32, y: 0, width: 12, height: 512).fill()
                }
            case "brick":
                NSColor(red: 0.16, green: 0.12, blue: 0.12, alpha: 1).setFill()
                rect.fill()
                for row in 0..<16 {
                    for column in 0..<5 {
                        let x = CGFloat(column) * 108 + (row.isMultiple(of: 2) ? 0 : 54) - 54
                        NSColor(red: CGFloat.random(in: 0.30...0.42, using: &random), green: 0.14, blue: 0.12, alpha: 1).setFill()
                        NSBezierPath(roundedRect: NSRect(x: x, y: CGFloat(row) * 32 + 3, width: 102, height: 27), xRadius: 3, yRadius: 3).fill()
                    }
                }
            default:    // "city": a wet night through glass, all out of focus
                NSGradient(colors: [NSColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 1), NSColor(red: 0.10, green: 0.08, blue: 0.20, alpha: 1)])?
                    .draw(in: rect, angle: -90)
                let lights: [NSColor] = [.systemPink, .systemTeal, .systemOrange, .systemYellow, .systemPurple]
                for _ in 0..<70 {
                    let size = CGFloat.random(in: 10...46, using: &random)
                    lights.randomElement(using: &random)!.withAlphaComponent(CGFloat.random(in: 0.15...0.55, using: &random)).setFill()
                    NSBezierPath(ovalIn: NSRect(x: CGFloat.random(in: 0...512, using: &random), y: CGFloat.random(in: 0...300, using: &random),
                                                width: size, height: size)).fill()
                }
            }
            return true
        }
    }

    /// Light falling through blinds, for the window light's gobo.
    static let blinds = NSImage(size: CGSize(width: 256, height: 256), flipped: false) { rect in
        NSColor.black.setFill()
        rect.fill()
        NSColor.white.setFill()
        for i in 0..<9 {
            NSRect(x: 30, y: CGFloat(i) * 26 + 14, width: 196, height: 15).fill()
        }
        return true
    }
}

// MARK: - Type over the frames

/// Noir type: a serif caption typed out a key at a time, a case title, a rubber stamp.
struct NoirOverlay: View {
    let caption: String?
    let title: String?
    let stamp: String?
    let stampAt: Double
    let t: Double
    /// The last shot: what Wingman is, and how to get it.
    var ending = false

    /// Keys a second, and the pause a "／" makes; scripts/reel_sound.py clacks to the same clock.
    static let rate = 16.0
    static let pause = 0.35
    static let delay = 0.08

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            // Letterbox bars, as in the pictures this is borrowing from.
            VStack {
                Color.black.frame(height: 70)
                Spacer()
                Color.black.frame(height: 70)
            }
            if let caption {
                Text(typed(caption))
                    .font(NoirArt.serif(27, .heavy))
                    .foregroundStyle(Color(red: 0.98, green: 0.95, blue: 0.86))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .shadow(color: .black.opacity(0.9), radius: 6)
                    .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                    .padding(.top, 104)
                    .padding(.horizontal, 24)
            }
            if let title {
                VStack(spacing: 4) {
                    Text(title.components(separatedBy: "｜").first ?? "").font(.custom("American Typewriter", size: 22).weight(.bold))
                        .foregroundStyle(Color(red: 0.98, green: 0.80, blue: 0.40))
                    Text(title.components(separatedBy: "｜").dropFirst().joined()).font(NoirArt.serif(34, .heavy))
                        .foregroundStyle(Color(red: 0.98, green: 0.95, blue: 0.86))
                }
                .shadow(color: .black, radius: 8)
                .opacity(min(1, max(0, (t - 0.25) / 0.3)))
                .padding(.top, 560)
            }
            if ending {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 34, height: 34)
                        Text("Wingman").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                    Text("Jev 判斷 · 你決定 · 不會自動送出").font(NoirArt.sans(15)).foregroundStyle(.white.opacity(0.8))
                    Text("Mac 版測試中 · 留言「僚機」開放時通知你")
                        .font(NoirArt.sans(15, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(red: 0.31, green: 0.27, blue: 0.90), in: Capsule())
                }
                .shadow(color: .black, radius: 10)
                .opacity(min(1, max(0, (t - 1.3) / 0.4)))
                .padding(.top, 530)
            }
            if let stamp, t >= stampAt {
                let x = min(1, (t - stampAt) / 0.14)
                Text(stamp)
                    .font(.custom("American Typewriter", size: stamp.count > 6 ? 40 : 46).weight(.heavy))
                    .foregroundStyle(NoirArt.red.opacity(0.92))
                    .padding(.horizontal, 18).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NoirArt.red.opacity(0.92), lineWidth: 5))
                    .rotationEffect(.degrees(-11))
                    .scaleEffect(2.2 - 1.2 * x)
                    .opacity(x)
                    .padding(.top, 455)
            }
        }
    }

    /// As much of the caption as has been typed by `t`, a "／" starting a new line after a beat.
    private func typed(_ caption: String) -> String {
        var clock = Self.delay, out = ""
        for character in caption {
            if character == "／" {
                clock += Self.pause
                guard clock <= t else { break }
                out.append("\n")
                continue
            }
            guard clock <= t else { break }
            out.append(character)
            clock += 1 / Self.rate
        }
        return out
    }
}
