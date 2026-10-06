import AppKit
import SwiftUI
import WingmanCore

/// The scenes of 〈腦內會議室〉 (promo/reel-02): the lead on a sofa, and the meeting in their head where
/// Impulse, Worry, Please and Meh argue over a reply until Wingman walks in. Every verdict shown is
/// Wingman's own, from staged.json, in the panel's own words. Drawn per frame: `t` is the second into the beat.
struct ReelScene: View {
    let name: String
    let t: Double
    let context: ReelContext

    var body: some View {
        ZStack {
            switch name {
            case "sofa-buzz": SofaShot(moment: .buzz, t: t, context: context)
            case "sofa-send": SofaShot(moment: .send, t: t, context: context)
            case "sofa-reply": SofaShot(moment: .reply, t: t, context: context)
            case "door": DoorShot(t: t)
            case "keyboard": ReelCharacter(shot: "C", t: t)
            case "end": MeetingEnd(t: t)
            case "room-drafts": DraftsShot(t: t, context: context)
            default:
                if name.hasPrefix("room-") {
                    RoomShot(phase: String(name.dropFirst(5)), t: t, context: context)
                } else if name.hasPrefix("verdict-") {
                    VerdictShot(chat: String(name.dropFirst(8)), t: t, context: context)
                }
            }
        }
        .frame(width: 450, height: 800)
        .clipped()
    }
}

/// What the scenes need from the made-up chats and what Wingman said about them.
@MainActor
struct ReelContext {
    let said: [String: Reel.Said]
    let lines: (String) -> [Reel.Line]
    let app: (String) -> ChatApp?
    /// The panel for a chat, with Wingman's ranked drafts in it.
    let panel: (String) -> AppModel
    /// Words the other side says in the story, not Wingman: their reply at the end.
    let text: String?
    /// The chat the story is about.
    let chat: String

    var incoming: Reel.Line? { lines(chat).last { !$0.isMe } }
    var best: String { said[chat]?.best ?? "" }

    /// Wingman's verdict as the panel words it: what is going on, and when to answer.
    func verdict(_ id: String) -> (sentence: String, tag: String, dot: Color)? {
        guard let s = said[id] else { return nil }
        let sentence = SuggestionView.plain(s.intent, sure: s.intentConfidence >= 0.5)
        if s.needsReply < 0.35 { return (sentence, L("這則可以不回"), .gray) }
        guard let urgency = s.urgency else { return (sentence, L("你的回覆會公開"), .blue) }
        return (sentence, SuggestionView.urgencyText(urgency), SuggestionView.urgencyColor(urgency))
    }
}

// MARK: - Timing and type

private func span(_ t: Double, _ start: Double, _ end: Double) -> Double { min(1, max(0, (t - start) / (end - start))) }
private func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
/// Overshoots a little before settling, for things that pop in.
private func pop(_ x: Double) -> Double {
    guard x < 1 else { return 1 }
    let c = 1.70158, p = x - 1
    return 1 + (c + 1) * p * p * p + c * p * p
}
/// A shake that is the same on every render of the same frame.
private func shake(_ t: Double, _ amount: Double) -> CGSize {
    let frame = Int(t * 30)
    return CGSize(width: sin(Double(frame) * 12.9898) * amount, height: cos(Double(frame) * 78.233) * amount)
}
private func zh(_ size: Double, _ weight: Font.Weight = .regular) -> Font { .custom("PingFang TC", size: size).weight(weight) }

// MARK: - The minds

enum Mind: String, CaseIterable {
    case impulse, worry, please, meh

    var name: String {
        switch self {
        case .impulse: "衝動"
        case .worry: "焦慮"
        case .please: "討好"
        case .meh: "擺爛"
        }
    }

    var color: Color {
        switch self {
        case .impulse: Color(red: 0.95, green: 0.33, blue: 0.30)
        case .worry: Color(red: 0.62, green: 0.56, blue: 1.0)
        case .please: Color(red: 1.0, green: 0.56, blue: 0.72)
        case .meh: Color(red: 0.62, green: 0.65, blue: 0.68)
        }
    }

    /// Where each sits at the table.
    var seat: Double {
        switch self {
        case .impulse: 78
        case .worry: 176
        case .please: 274
        case .meh: 372
        }
    }
}

private enum Mood: Equatable { case idle, talking, shocked, happy, look(Double), asleep }

/// One of the voices in the head: a soft shape with a face that says what it is.
private struct Blob: View {
    let mind: Mind
    let t: Double
    var mood: Mood = .idle
    var size = 86.0

    var body: some View {
        ZStack {
            shape
            face.offset(y: mind == .meh && mood != .happy ? 6 : -4)
            if mind == .impulse { flames }
            if mind == .worry, mood != .asleep {
                ReelDrop().fill(Color(red: 0.62, green: 0.86, blue: 1)).frame(width: 11, height: 16)
                    .offset(x: size * 0.42, y: -size * 0.22 + 14 * (t.truncatingRemainder(dividingBy: 0.9) / 0.9))
            }
            if mood == .asleep {
                Text("z z Z").font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .offset(x: size * 0.45, y: -size * 0.55 - 6 * sin(t * 3))
            }
        }
        .frame(width: size * 1.7, height: size * 1.4)
        .offset(worryShiver)
    }

    private var worryShiver: CGSize { mind == .worry && mood != .happy && mood != .asleep ? shake(t, 1.6) : .zero }

    @ViewBuilder private var shape: some View {
        switch mind {
        case .impulse:
            RoundedRectangle(cornerRadius: size * 0.34).fill(mind.color.gradient).frame(width: size, height: size * 0.94)
        case .worry:
            Wobble(phase: t * 14).fill(mind.color.gradient).frame(width: size, height: size)
        case .please:
            Ellipse().fill(mind.color.gradient).frame(width: size * 1.12, height: size * 0.92)
        case .meh:
            // Lying flat on the table, unless something finally goes its way.
            Capsule().fill(mind.color.gradient)
                .frame(width: mood == .happy ? size * 0.8 : size * 1.45, height: mood == .happy ? size * 1.05 : size * 0.6)
        }
    }

    private var flames: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let flicker = 1 + 0.18 * sin(t * 22 + Double(i) * 2)
                Flame().fill(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), mind.color], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 30 * flicker)
                    .offset(x: Double(i - 1) * 22, y: -size * 0.47 - 12 * flicker + (i == 1 ? -6 : 0))
            }
        }
    }

    @ViewBuilder private var face: some View {
        let talking = mood == .talking
        HStack(spacing: size * 0.2) {
            eye(-1)
            eye(1)
        }
        .offset(y: -size * 0.08)
        .overlay(alignment: .top) {
            if mind == .impulse && mood != .happy {
                HStack(spacing: size * 0.22) {
                    Capsule().fill(Color.black.opacity(0.75)).frame(width: 16, height: 4.5).rotationEffect(.degrees(22))
                    Capsule().fill(Color.black.opacity(0.75)).frame(width: 16, height: 4.5).rotationEffect(.degrees(-22))
                }
                .offset(y: -size * 0.2)
            }
        }
        mouth(talking: talking).offset(y: size * 0.17)
        if mind == .please || mood == .happy {
            HStack(spacing: size * 0.52) {
                Ellipse().fill(Color(red: 1, green: 0.4, blue: 0.5).opacity(0.45)).frame(width: 15, height: 8)
                Ellipse().fill(Color(red: 1, green: 0.4, blue: 0.5).opacity(0.45)).frame(width: 15, height: 8)
            }
            .offset(y: size * 0.06)
        }
    }

    @ViewBuilder private func eye(_ side: Double) -> some View {
        let ink = Color(red: 0.13, green: 0.10, blue: 0.16)
        switch mood {
        case .happy:
            Path { p in
                p.move(to: CGPoint(x: 0, y: 7))
                p.addQuadCurve(to: CGPoint(x: 14, y: 7), control: CGPoint(x: 7, y: -3))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 3.2, lineCap: .round)).frame(width: 14, height: 8)
        case .asleep:
            Capsule().fill(ink).frame(width: 13, height: 3)
        case .shocked:
            ZStack { Circle().fill(.white); Circle().stroke(ink, lineWidth: 2); Circle().fill(ink).frame(width: 4, height: 4) }
                .frame(width: 19, height: 19)
        default:
            if mind == .please {
                Image(systemName: "heart.fill").font(.system(size: 15)).foregroundStyle(Color(red: 0.9, green: 0.12, blue: 0.35))
                    .scaleEffect(1 + 0.12 * sin(t * 9))
            } else if mind == .meh {
                ZStack(alignment: .bottom) {
                    Ellipse().fill(.white).frame(width: 15, height: 10)
                    Ellipse().fill(ink).frame(width: 8, height: 7)
                    Capsule().fill(ink).frame(width: 17, height: 2.6).offset(y: -8)
                }
            } else {
                let look: Double = { if case .look(let dx) = mood { return dx }; return 0 }()
                ZStack {
                    Ellipse().fill(.white).frame(width: mind == .worry ? 19 : 16, height: mind == .worry ? 21 : 17)
                    Ellipse().fill(ink).frame(width: mind == .worry ? 5 : 8, height: mind == .worry ? 6 : 10)
                        .offset(x: look * 4 + (mind == .worry ? sin(t * 30) * 1.2 : 0))
                }
            }
        }
    }

    @ViewBuilder private func mouth(talking: Bool) -> some View {
        let ink = Color(red: 0.13, green: 0.10, blue: 0.16)
        if talking {
            let open = 4 + 9 * abs(sin(t * 17))
            Ellipse().fill(ink).frame(width: 16, height: open)
                .overlay(Ellipse().fill(Color(red: 1, green: 0.45, blue: 0.5)).frame(width: 9, height: open * 0.4).offset(y: open * 0.2))
        } else if mood == .shocked {
            Ellipse().fill(ink).frame(width: 12, height: 14)
        } else if mood == .happy || mind == .please {
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: 20, y: 0))
                p.addQuadCurve(to: .zero, control: CGPoint(x: 10, y: 15))
            }
            .fill(ink).frame(width: 20, height: 9)
        } else if mind == .worry {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 4))
                for i in 0..<4 { p.addQuadCurve(to: CGPoint(x: Double(i + 1) * 5, y: 4), control: CGPoint(x: Double(i) * 5 + 2.5, y: i.isMultiple(of: 2) ? 0 : 8)) }
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round)).frame(width: 20, height: 8)
        } else {
            Capsule().fill(ink).frame(width: mind == .impulse ? 16 : 12, height: 3.2)
        }
    }
}

/// Wingman as a character: the app icon's speech bubble, calm, with a glow and a ✦.
private struct Buddy: View {
    let t: Double
    var size = 96.0
    var glow = 1.0
    var talking = false

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.45 * glow)).frame(width: size * 1.7).blur(radius: 26)
            BubbleShape().fill(LinearGradient(colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.16, green: 0.78, blue: 0.82)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size * 0.84)
            BubbleShape().stroke(Color.white.opacity(0.5), lineWidth: 2).frame(width: size, height: size * 0.84)
            HStack(spacing: size * 0.2) {
                ForEach(0..<2, id: \.self) { _ in
                    Ellipse().fill(.white).frame(width: size * 0.13, height: size * 0.17)
                        .overlay(Ellipse().fill(Color(red: 0.1, green: 0.1, blue: 0.25)).frame(width: size * 0.07, height: size * 0.1))
                }
            }
            .offset(y: -size * 0.08)
            Group {
                if talking {
                    Ellipse().fill(Color(red: 0.1, green: 0.1, blue: 0.25)).frame(width: size * 0.14, height: 3 + 8 * abs(sin(t * 15)))
                } else {
                    Path { p in
                        p.move(to: .zero)
                        p.addQuadCurve(to: CGPoint(x: size * 0.2, y: 0), control: CGPoint(x: size * 0.1, y: size * 0.09))
                    }
                    .stroke(Color(red: 0.1, green: 0.1, blue: 0.25), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                    .frame(width: size * 0.2, height: size * 0.06)
                }
            }
            .offset(y: size * 0.1)
            Text("✦").font(.system(size: size * 0.24)).foregroundStyle(.white)
                .rotationEffect(.degrees(t * 60))
                .offset(x: size * 0.46, y: -size * 0.46)
        }
        .offset(y: sin(t * 3.2) * 4)
    }
}

// MARK: - Shapes

struct ReelDrop: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - r.width / 2), control: CGPoint(x: r.maxX, y: r.midY - 2))
            p.addArc(center: CGPoint(x: r.midX, y: r.maxY - r.width / 2), radius: r.width / 2,
                     startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.midY - 2))
        }
    }
}

private struct Wobble: Shape {
    let phase: Double
    func path(in r: CGRect) -> Path {
        Path { p in
            for step in 0...72 {
                let a = Double(step) / 72 * 2 * .pi
                let radius = 1 + 0.045 * sin(a * 6 + phase)
                let point = CGPoint(x: r.midX + cos(a) * r.width / 2 * radius, y: r.midY + sin(a) * r.height / 2 * radius)
                step == 0 ? p.move(to: point) : p.addLine(to: point)
            }
            p.closeSubpath()
        }
    }
}

private struct Flame: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - r.width / 2), control: CGPoint(x: r.maxX, y: r.midY))
            p.addArc(center: CGPoint(x: r.midX, y: r.maxY - r.width / 2), radius: r.width / 2,
                     startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.midY))
        }
    }
}

/// A speech bubble with its tail at the bottom left: Wingman's outline.
private struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.84),
                     cornerRadius: r.height * 0.3)
        p.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.8))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.8))
        p.closeSubpath()
        return p
    }
}

/// What a mind says, popping in over its head.
private struct Speech: View {
    let text: String
    let t: Double
    var tint = Color.white
    var size = 20.0
    var jitter = 0.0

    var body: some View {
        Text(text)
            .font(zh(size, .heavy))
            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.16))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 9)
            // The drop shadow belongs to the bubble only; on the words it read as a double image.
            .background(RoundedRectangle(cornerRadius: 16).fill(tint).shadow(color: .black.opacity(0.25), radius: 0, x: 3, y: 4))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.85), lineWidth: 2.5))
            .fixedSize()
            .scaleEffect(max(0.01, pop(span(t, 0, 0.22))))
            .offset(shake(t, jitter))
    }
}

/// A chat message shown large, the way the scenes quote it.
private struct MessageCard: View {
    let app: ChatApp?
    let sender: String
    let text: String
    var time: String? = nil
    var dark = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(app?.name ?? "").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(sender).font(zh(13, .semibold))
                if let time { Text(time).font(.system(size: 11)).foregroundStyle(.tertiary) }
            }
            Text(text).font(zh(19, .medium)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
        .background(dark ? Color(red: 0.13, green: 0.13, blue: 0.16) : .white, in: RoundedRectangle(cornerRadius: 16))
        .environment(\.colorScheme, dark ? .dark : .light)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private var tint: Color {
        switch app {
        case .slack: Color(red: 0.88, green: 0.12, blue: 0.35)
        case .discord: Color(red: 0.35, green: 0.40, blue: 0.95)
        case .line: Color(red: 0.02, green: 0.78, blue: 0.33)
        case .instagram: Color(red: 0.88, green: 0.19, blue: 0.62)
        default: Color.gray
        }
    }
}

/// Wingman's verdict as a card: the panel's sentence and its tag, larger.
private struct VerdictCard: View {
    let sentence: String
    let tag: String
    let dot: Color
    var width = 250.0

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 20, height: 20)
                Text("Wingman").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            }
            Text(sentence).font(zh(19, .bold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(tag).font(zh(14, .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.white.opacity(0.12), in: Capsule())
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .background(Color(red: 0.11, green: 0.11, blue: 0.15), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(red: 0.31, green: 0.27, blue: 0.90), lineWidth: 2))
        .environment(\.colorScheme, .dark)
        .shadow(color: Color(red: 0.31, green: 0.27, blue: 0.90).opacity(0.5), radius: 16)
    }
}

// MARK: - The sofa

private struct SofaShot: View {
    enum Moment { case buzz, send, reply }
    let moment: Moment
    let t: Double
    let context: ReelContext

    var body: some View {
        let zoom = moment == .buzz ? 1 + 0.16 * smooth(span(t, 0.9, 2.0)) : 1
        ZStack {
            room
            ZStack {
                sofa
                ReelLead(face: face, handUp: handUp)
                ReelLaptop().offset(y: 34)
            }
            .offset(y: 44)
            .scaleEffect(zoom, anchor: UnitPoint(x: 0.5, y: 0.47))
            overlays
        }
    }

    private var room: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.30, green: 0.22, blue: 0.42), Color(red: 0.62, green: 0.36, blue: 0.40)],
                           startPoint: .top, endPoint: .bottom)
            // A window on the city at dusk.
            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(red: 0.22, green: 0.20, blue: 0.45), Color(red: 0.98, green: 0.55, blue: 0.40)],
                                                                    startPoint: .top, endPoint: .bottom))
                .frame(width: 150, height: 170).position(x: 95, y: 300)
            ForEach(0..<6, id: \.self) { i in
                Rectangle().fill(Color(red: 0.16, green: 0.12, blue: 0.28))
                    .frame(width: 20, height: 40 + Double((i * 37) % 60)).position(x: 32 + Double(i) * 25, y: 385 - Double((i * 37) % 60) / 2)
            }
            RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.8), lineWidth: 6).frame(width: 150, height: 170).position(x: 95, y: 300)
            // A floor lamp.
            Rectangle().fill(Color(white: 0.2)).frame(width: 5, height: 300).position(x: 400, y: 470)
            Ellipse().fill(Color(red: 1, green: 0.85, blue: 0.55)).frame(width: 70, height: 34).position(x: 400, y: 318)
            Circle().fill(Color(red: 1, green: 0.8, blue: 0.5).opacity(0.35)).frame(width: 200).blur(radius: 40).position(x: 400, y: 330)
            Rectangle().fill(Color(red: 0.36, green: 0.24, blue: 0.24)).frame(width: 450, height: 180).position(x: 225, y: 710)
        }
    }

    private var sofa: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34).fill(Color(red: 0.93, green: 0.58, blue: 0.38)).frame(width: 400, height: 210).position(x: 225, y: 470)
            RoundedRectangle(cornerRadius: 26).fill(Color(red: 0.86, green: 0.50, blue: 0.32)).frame(width: 66, height: 190).position(x: 40, y: 560)
            RoundedRectangle(cornerRadius: 26).fill(Color(red: 0.86, green: 0.50, blue: 0.32)).frame(width: 66, height: 190).position(x: 410, y: 560)
            RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.98, green: 0.82, blue: 0.40)).frame(width: 70, height: 66)
                .rotationEffect(.degrees(-10)).position(x: 88, y: 470)
        }
    }

    private var face: ReelFace {
        switch moment {
        case .buzz:
            if t < 0.75 { return ReelFace(eyes: .happy, brows: 0, mouth: .smile, blush: 0.2) }
            return ReelFace(eyes: .wide, brows: -1, mouth: .wavy, sweat: span(t, 0.9, 2.0))
        case .send:
            return t < 0.9 ? ReelFace(eyes: .squint, brows: 0.6, mouth: .tongue) : ReelFace(eyes: .happy, mouth: .smile, blush: 0.6)
        case .reply:
            return ReelFace(eyes: .happy, mouth: .smile, blush: 1)
        }
    }

    private var handUp: Double { moment == .send ? span(t, 0.6, 0.85) - span(t, 0.95, 1.2) : 0 }

    @ViewBuilder private var overlays: some View {
        switch moment {
        case .buzz:
            if let line = context.incoming {
                let shown = pop(span(t, 0.45, 0.7))
                MessageCard(app: context.app(context.chat), sender: line.from, text: line.text)
                    .scaleEffect(max(0.01, shown))
                    .position(x: 225, y: 252)
                    .opacity(t > 0.45 ? 1 : 0)
            }
            Text("!").font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.3))
                .shadow(color: .black.opacity(0.4), radius: 0, x: 3, y: 3)
                .scaleEffect(max(0.01, pop(span(t, 0.75, 0.95))))
                .position(x: 322, y: 382)
                .opacity(t > 0.75 ? 1 : 0)
        case .send:
            let fly = smooth(span(t, 1.0, 1.6))
            Text(context.best)
                .font(zh(15, .medium)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(red: 0.25, green: 0.45, blue: 0.95), in: RoundedRectangle(cornerRadius: 16))
                .frame(width: 300)
                .fixedSize(horizontal: false, vertical: true)
                .position(x: 225, y: 500 - 240 * fly)
                .opacity(t > 1.0 ? 1 - span(t, 1.8, 2.2) : 0)
                .scaleEffect(0.6 + 0.4 * fly)
        case .reply:
            if let reply = context.text, let line = context.incoming {
                MessageCard(app: context.app(context.chat), sender: line.from, text: reply)
                    .scaleEffect(max(0.01, pop(span(t, 0.1, 0.35))))
                    .position(x: 225, y: 252)
                    .opacity(t > 0.1 ? 1 : 0)
            }
            ForEach(0..<6, id: \.self) { i in
                let rise = span(t, 0.4 + Double(i) * 0.12, 1.6 + Double(i) * 0.12)
                Image(systemName: "heart.fill").font(.system(size: 16 + Double(i % 3) * 6))
                    .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.55))
                    .position(x: 150 + Double(i) * 32, y: 460 - 140 * rise)
                    .opacity(rise > 0 ? 1 - rise : 0)
            }
        }
    }
}

// MARK: - The door to the head

private struct DoorShot: View {
    let t: Double

    var body: some View {
        let slam = pop(span(t, 0.25, 0.42))
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.18, blue: 0.26), Color(red: 0.06, green: 0.10, blue: 0.16)], startPoint: .top, endPoint: .bottom)
            // The siren's sweep.
            Path { p in
                p.move(to: CGPoint(x: 225, y: 232))
                p.addLine(to: CGPoint(x: 225 + 600 * cos(t * 7), y: 232 + 600 * sin(t * 7)))
                p.addLine(to: CGPoint(x: 225 + 600 * cos(t * 7 + 0.5), y: 232 + 600 * sin(t * 7 + 0.5)))
                p.closeSubpath()
            }
            .fill(Color.red.opacity(0.22))
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.55, green: 0.36, blue: 0.24)).frame(width: 230, height: 360)
                RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.2), lineWidth: 3).frame(width: 190, height: 140).offset(y: -80)
                RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.2), lineWidth: 3).frame(width: 190, height: 140).offset(y: 85)
                Circle().fill(Color(red: 0.95, green: 0.8, blue: 0.4)).frame(width: 18).offset(x: 85, y: 20)
                Text("腦內會議室").font(zh(24, .heavy)).foregroundStyle(Color(red: 0.2, green: 0.14, blue: 0.1))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color(red: 0.98, green: 0.93, blue: 0.82), in: RoundedRectangle(cornerRadius: 8))
                    .offset(y: -120)
            }
            .position(x: 225, y: 445)
            Capsule().fill(Color.red).frame(width: 46, height: 26).position(x: 225, y: 240)
                .shadow(color: .red, radius: 16 + 8 * sin(t * 14))
            Text("緊急會議").font(zh(40, .black)).foregroundStyle(Color(red: 0.92, green: 0.15, blue: 0.2))
                .padding(.horizontal, 14).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(red: 0.92, green: 0.15, blue: 0.2), lineWidth: 5))
                .rotationEffect(.degrees(-12))
                .scaleEffect(2.4 - 1.4 * slam)
                .opacity(t > 0.25 ? 1 : 0)
                .position(x: 228, y: 470)
        }
        .offset(t > 0.4 && t < 0.7 ? shake(t, 6) : .zero)
    }
}

// MARK: - The meeting

private struct RoomShot: View {
    let phase: String
    let t: Double
    let context: ReelContext

    var body: some View {
        ZStack {
            scene
                .offset(phase == "chaos" ? shake(t, 5 + 5 * span(t, 0, 2)) : .zero)
            if phase == "enter" { enterLight }
            // Everyone stops dead: the lights drop.
            if phase == "freeze" { Color.black.opacity(0.5) }
        }
    }

    private var scene: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.80, green: 0.93, blue: 0.90), Color(red: 0.70, green: 0.86, blue: 0.88)], startPoint: .top, endPoint: .bottom)
            // The door Wingman comes through.
            Rectangle().fill(Color(red: 0.55, green: 0.36, blue: 0.24)).frame(width: 60, height: 300).position(x: 440, y: 450)
            screen.position(x: 225, y: 322)
            ForEach(Mind.allCases, id: \.self) { mind in
                if mind != .meh { seat(mind) }
            }
            Rectangle().fill(Color(red: 0.88, green: 0.72, blue: 0.52)).frame(width: 470, height: 26).position(x: 225, y: 612)
            Rectangle().fill(Color(red: 0.62, green: 0.42, blue: 0.28)).frame(width: 470, height: 190).position(x: 225, y: 720)
            seat(.meh)
            ForEach(Mind.allCases, id: \.self) { mind in
                Text(mind.name).font(zh(13, .bold)).foregroundStyle(Color(red: 0.25, green: 0.18, blue: 0.12))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
                    .position(x: mind.seat, y: 642)
                    .opacity(intro(mind) > 0 ? 1 : 0)
            }
            if ["enter", "board", "drafts", "party"].contains(phase) { buddy }
            speech
            if phase == "chaos" { flyingDrafts }
            if phase == "party" { Confetti(t: t) }
        }
    }

    /// Each mind pops up from behind the table at the start, one after another.
    private func intro(_ mind: Mind) -> Double {
        guard phase == "intro" else { return 1 }
        let index = Double(Mind.allCases.firstIndex(of: mind)!)
        return pop(span(t, 0.25 + index * 0.35, 0.5 + index * 0.35))
    }

    private func mood(_ mind: Mind) -> Mood {
        switch phase {
        case "impulse": mind == .impulse ? .talking : .look(-1)
        case "worry": mind == .worry ? .talking : .look(mind.seat < 176 ? 1 : -1)
        case "please": mind == .please ? .talking : .look(mind.seat < 274 ? 1 : -1)
        case "meh": mind == .meh ? .talking : .look(1)
        case "chaos": .talking
        case "freeze": .shocked
        case "enter": t < 0.6 ? .shocked : .look(1)
        case "board": mind == .meh ? .idle : .look(0)
        case "party": mind == .meh ? .asleep : .happy
        default: .idle
        }
    }

    private func seat(_ mind: Mind) -> some View {
        let up = intro(mind)
        let jump = phase == "impulse" && mind == .impulse ? abs(sin(t * 7)) * 26 : 0
        let bounce = phase == "party" && mind != .meh ? abs(sin(t * 8 + mind.seat)) * 18 : 0
        let y = mind == .meh ? 590.0 : 560
        return Blob(mind: mind, t: t, mood: mood(mind))
            .position(x: mind.seat, y: y + 80 * (1 - up) - jump - bounce)
            .opacity(up > 0 ? 1 : 0)
    }

    @ViewBuilder private var screen: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.16, green: 0.16, blue: 0.20)).frame(width: 380, height: 196)
            RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.09, green: 0.09, blue: 0.12)).frame(width: 362, height: 178)
            switch phase {
            case "board":
                if let v = context.verdict(context.chat), let s = context.said[context.chat] {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Wingman 判斷").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        Text(v.sentence).font(zh(24, .heavy))
                            .opacity(span(t, 0.25, 0.45))
                        HStack(spacing: 6) { Circle().fill(v.dot).frame(width: 8, height: 8); Text(v.tag).font(zh(14, .medium)) }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .opacity(span(t, 0.6, 0.8))
                        if let tension = s.tension {
                            MoodBar(tension: tension, subtext: (s.subtext ?? 0) >= Brain.meaningful)
                                .scaleEffect(1.35, anchor: .leading)
                                .opacity(span(t, 0.95, 1.15))
                        }
                    }
                    .padding(.horizontal, 22)
                    .frame(width: 362, height: 178, alignment: .leading)
                    .environment(\.colorScheme, .dark)
                }
            default:
                if let line = context.incoming {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(context.app(context.chat)?.name ?? "") · \(line.from)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Text(line.text).font(zh(24, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color(white: 0.24), in: RoundedRectangle(cornerRadius: 16))
                        if phase == "party", let reply = context.text {
                            Text(reply).font(zh(16, .medium)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color(white: 0.24), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .frame(width: 330, alignment: .leading)
                    .environment(\.colorScheme, .dark)
                }
            }
        }
    }

    @ViewBuilder private var speech: some View {
        switch phase {
        case "intro":
            EmptyView()
        case "impulse":
            Speech(text: "直接回「對啊」！", t: t, tint: Color(red: 1, green: 0.88, blue: 0.86), size: 24).position(x: 160, y: 455)
        case "worry":
            Speech(text: "她生氣了吧？？\n完了完了完了", t: t, tint: Color(red: 0.92, green: 0.90, blue: 1), size: 22, jitter: 2.5).position(x: 205, y: 445)
        case "please":
            Speech(text: "快約她！明天！\n後天！每天！🙏🙏🙏", t: t, tint: Color(red: 1, green: 0.90, blue: 0.94), size: 21).position(x: 260, y: 445)
        case "meh":
            Speech(text: "已讀……明天再說", t: t, tint: Color(white: 0.93), size: 22).position(x: 290, y: 470)
        case "chaos":
            ZStack {
                Speech(text: "對啊！", t: t, tint: Color(red: 1, green: 0.88, blue: 0.86), size: 26, jitter: 3).rotationEffect(.degrees(-8)).position(x: 92, y: 470)
                Speech(text: "完了完了", t: max(0, t - 0.1), tint: Color(red: 0.92, green: 0.90, blue: 1), size: 22, jitter: 3).rotationEffect(.degrees(6)).position(x: 200, y: 448)
                Speech(text: "🙏🙏🙏", t: max(0, t - 0.2), tint: Color(red: 1, green: 0.90, blue: 0.94), size: 24, jitter: 3).rotationEffect(.degrees(-4)).position(x: 300, y: 478)
                Speech(text: "zzz", t: max(0, t - 0.3), tint: Color(white: 0.93), size: 20, jitter: 2).rotationEffect(.degrees(10)).position(x: 380, y: 500)
            }
        case "enter":
            Speech(text: "大家好，我來主持", t: max(0, t - 1.0), tint: Color(red: 0.88, green: 0.97, blue: 1), size: 20)
                .position(x: 300, y: 395).opacity(t > 1.0 ? 1 : 0)
        case "board":
            Speech(text: "……果然", t: max(0, t - 1.6), tint: Color(red: 0.92, green: 0.90, blue: 1), size: 18)
                .position(x: 176, y: 470).opacity(t > 1.6 ? 1 : 0)
        default:
            EmptyView()
        }
    }

    private var buddy: some View {
        let arrive = smooth(span(t, 0.3, 1.1))
        let x = phase == "enter" ? 470 - 120 * arrive : 352
        let y = phase == "enter" ? 470.0 : phase == "party" ? 470 - abs(sin(t * 6)) * 14 : 470
        return Buddy(t: t, size: 84, glow: phase == "enter" ? arrive : 0.8, talking: phase == "enter" && t > 1.0 && t < 2.0)
            .position(x: x, y: y)
    }

    /// The room in the dark, and the light through the opening door.
    private var enterLight: some View {
        let open = smooth(span(t, 0.1, 0.5))
        return ZStack {
            Color.black.opacity(0.5 * (1 - span(t, 1.4, 2.0)))
            Path { p in
                p.move(to: CGPoint(x: 450, y: 300))
                p.addLine(to: CGPoint(x: 450, y: 600))
                p.addLine(to: CGPoint(x: 450 - 300 * open, y: 800))
                p.addLine(to: CGPoint(x: 450 - 120 * open, y: 300))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.75).opacity(0.55), .clear], startPoint: .trailing, endPoint: .leading))
        }
        .allowsHitTesting(false)
    }

    /// Drafts thrown out mid-argument, crossed out.
    private var flyingDrafts: some View {
        ZStack {
            ForEach(Array(["對啊", "沒有啦～", "🙏🙏🙏", "好", "你也很忙吧"].enumerated()), id: \.offset) { i, text in
                let start = Double(i) * 0.3
                let fly = span(t, start, start + 1.1)
                Text(text).font(zh(16, .bold)).foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.25))
                    .strikethrough(true, color: .red)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                    .rotationEffect(.degrees(Double(i * 37 % 50) - 25 + 200 * fly))
                    .position(x: 60 + Double(i * 83 % 330) + 120 * fly * (i.isMultiple(of: 2) ? 1 : -1), y: 560 - 360 * fly)
                    .opacity(fly > 0 && fly < 1 ? 1 : 0)
            }
        }
    }
}

private struct Confetti: View {
    let t: Double

    var body: some View {
        ZStack {
            ForEach(0..<36, id: \.self) { i in
                let x = Double((i * 97) % 450)
                let fall = (t * (180 + Double(i % 5) * 40) + Double((i * 53) % 300)).truncatingRemainder(dividingBy: 700)
                RoundedRectangle(cornerRadius: 2)
                    .fill([Color.red, .yellow, .green, .blue, .pink, .orange][i % 6])
                    .frame(width: 8, height: 13)
                    .rotationEffect(.degrees(t * 300 + Double(i * 40)))
                    .position(x: x + 20 * sin(t * 3 + Double(i)), y: 180 + fall)
            }
        }
    }
}

/// Wingman's real panel up on the meeting room's screen, the minds watching from below.
private struct DraftsShot: View {
    let t: Double
    let context: ReelContext

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.16, blue: 0.20), Color(red: 0.05, green: 0.08, blue: 0.11)], startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 0.35, green: 0.85, blue: 0.95).opacity(0.18)).frame(width: 520).blur(radius: 60).position(x: 225, y: 420)
            SuggestionView(model: context.panel(context.chat))
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.13, green: 0.13, blue: 0.15)))
                .environment(\.colorScheme, .dark)
                .scaleEffect(0.9 + 0.1 * pop(span(t, 0, 0.3)))
                .position(x: 225, y: 425)
            ForEach(Array(Mind.allCases.enumerated()), id: \.offset) { i, mind in
                Blob(mind: mind, t: t, mood: .look(0), size: 74)
                    .brightness(-0.55)
                    .position(x: [70.0, 170, 280, 380][i], y: 700)
            }
            Buddy(t: t, size: 58).position(x: 400, y: 228)
        }
    }
}

// MARK: - Every other time

/// One message, one mind losing it, and Wingman's verdict.
private struct VerdictShot: View {
    let chat: String
    let t: Double
    let context: ReelContext

    private var mind: Mind {
        switch chat {
        case "boss": .worry
        case "family": .please
        default: .meh
        }
    }

    private var outburst: String {
        switch chat {
        case "boss": "半夜問？！\n要被罵了！"
        case "family": "回十個愛心！"
        default: "這個我來！"
        }
    }

    /// A large faint prop that says where this message lands.
    private var prop: String {
        switch chat {
        case "boss": "🌙"
        case "family": "🌞"
        default: "🛠️"
        }
    }

    private var background: LinearGradient {
        switch chat {
        case "boss": LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.22), Color(red: 0.16, green: 0.12, blue: 0.30)], startPoint: .top, endPoint: .bottom)
        case "family": LinearGradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.70), Color(red: 1.0, green: 0.76, blue: 0.62)], startPoint: .top, endPoint: .bottom)
        default: LinearGradient(colors: [Color(red: 0.24, green: 0.25, blue: 0.36), Color(red: 0.32, green: 0.30, blue: 0.48)], startPoint: .top, endPoint: .bottom)
        }
    }

    var body: some View {
        let line = context.lines(chat).last { !$0.isMe }
        let verdict = context.verdict(chat)
        let wins = chat == "notice" && t > 1.45
        ZStack {
            background
            Text(prop).font(.system(size: 120)).opacity(0.22).rotationEffect(.degrees(-10)).position(x: 350, y: 410)
            if let line {
                MessageCard(app: context.app(chat), sender: line.from, text: line.text, time: line.time, dark: chat != "family")
                    .scaleEffect(max(0.01, pop(span(t, 0, 0.2))))
                    .position(x: 225, y: 268)
            }
            Blob(mind: mind, t: t, mood: wins ? .happy : .talking, size: 110)
                .position(x: 112, y: 545 - (wins ? abs(sin(t * 9)) * 20 : 0))
            Speech(text: wins ? "終於輪到我！" : outburst, t: wins ? t - 1.45 : t, tint: .white, size: 22, jitter: mind == .worry ? 2.5 : 0)
                .position(x: 140, y: 418)
            if let verdict {
                VerdictCard(sentence: verdict.sentence, tag: verdict.tag, dot: verdict.dot, width: 214)
                    .scaleEffect(max(0.01, pop(span(t, 0.75, 0.98))))
                    .opacity(t > 0.75 ? 1 : 0)
                    .position(x: 318, y: 540)
            }
        }
    }
}

// MARK: - The end

private struct MeetingEnd: View {
    let t: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.11, blue: 0.33), Color(red: 0.04, green: 0.05, blue: 0.08)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                Text("腦內會議太吵？").font(zh(36, .black)).foregroundStyle(.white)
                    .scaleEffect(max(0.01, pop(span(t, 0, 0.25))))
                HStack(spacing: 8) {
                    Text("⌥ Space").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3)))
                    Text("請 Wingman 主持").font(zh(22, .bold)).foregroundStyle(.white)
                }
                .opacity(span(t, 0.25, 0.45))
                Text("Jev 判斷 · 你決定 · 不會自動送出").font(zh(15)).foregroundStyle(Color.white.opacity(0.7))
                    .opacity(span(t, 0.45, 0.65))
            }
            .position(x: 225, y: 290)
            ForEach(Array(Mind.allCases.enumerated()), id: \.offset) { i, mind in
                Blob(mind: mind, t: t, mood: .happy, size: 64)
                    .position(x: [60.0, 130, 320, 390][i], y: 480 - abs(sin(t * 7 + Double(i))) * 10)
            }
            Buddy(t: t, size: 92).position(x: 225, y: 462)
            Text("Mac 版測試中 · 留言「僚機」開放時通知你")
                .font(zh(16, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Color(red: 0.31, green: 0.27, blue: 0.90), in: Capsule())
                .position(x: 225, y: 566)
                .opacity(span(t, 0.7, 0.9))
        }
    }
}
