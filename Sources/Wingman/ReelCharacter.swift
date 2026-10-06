import AppKit
import SwiftUI

/// The made-up lead of a promo Reel, drawn with shapes so every shot keeps the same face. It stands in for
/// footage nobody has filmed: `shot` is the side beat's letter in reel.json, `t` the second into it.
struct ReelCharacter: View {
    let shot: String
    let t: Double

    var body: some View {
        ZStack {
            switch shot {
            case "C": KeyboardShot(t: t)
            case "F": MorningShot(t: t)
            default: DeskShot(shot: shot, t: t)
            }
        }
        .frame(width: 450, height: 800)
    }
}

// MARK: - Timing

private func span(_ t: Double, _ start: Double, _ end: Double) -> Double { min(1, max(0, (t - start) / (end - start))) }
private func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
/// Eyes shut for a moment at each of these seconds.
private func blinking(_ t: Double, at moments: [Double]) -> Bool { moments.contains { abs(t - $0) < 0.06 } }

// MARK: - Palette

private enum Ink {
    static let skin = Color(red: 0.99, green: 0.86, blue: 0.75)
    static let skinShade = Color(red: 0.93, green: 0.74, blue: 0.64)
    static let hair = Color(red: 0.17, green: 0.15, blue: 0.21)
    static let line = Color(red: 0.16, green: 0.12, blue: 0.17)
    static let hoodie = Color(red: 0.31, green: 0.27, blue: 0.90)
    static let hoodieDark = Color(red: 0.22, green: 0.19, blue: 0.70)
    static let blush = Color(red: 1.0, green: 0.52, blue: 0.56)
    static let sweat = Color(red: 0.62, green: 0.86, blue: 1.0)
    static let night = LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.14), Color(red: 0.12, green: 0.10, blue: 0.20)],
                                      startPoint: .top, endPoint: .bottom)
    static let lamp = Color(red: 1.0, green: 0.82, blue: 0.48)
    static let screen = Color(red: 0.55, green: 0.85, blue: 1.0)
}

// MARK: - The face

struct ReelFace {
    enum Eyes { case open, half, closed, happy, squint, wide, look(Double) }
    enum Mouth { case flat, sigh, wavy, smile, smirk, tongue, frown }
    var eyes: Eyes = .open
    /// -1 worried (inner ends up) … 1 set on something (inner ends down).
    var brows = 0.0
    var mouth: Mouth = .flat
    var blush = 0.0
    /// How far a drop of sweat has slid, 0…1; nil for none.
    var sweat: Double?
}

/// A head drawn around its centre, hair and all.
private struct Head: View {
    let x: Double
    let y: Double
    let face: ReelFace

    var body: some View {
        ZStack {
            Circle().fill(Ink.hair).frame(width: 142, height: 142).position(x: x, y: y - 8)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().fill(Ink.skin).frame(width: 24, height: 24).position(x: x + side * 61, y: y + 10)
                Circle().fill(Ink.skinShade).frame(width: 11, height: 11).position(x: x + side * 61, y: y + 10)
            }
            Circle().fill(Ink.skin).frame(width: 124, height: 124).position(x: x, y: y)
            bangs
            ForEach([-1.0, 1.0], id: \.self) { side in
                eye(at: CGPoint(x: x + side * 23, y: y + 12))
                Capsule().fill(Ink.hair)
                    .frame(width: 19, height: 5)
                    .rotationEffect(.degrees(-side * face.brows * 13))
                    .position(x: x + side * 23, y: y - 7 - (face.brows < 0 ? 3 : 0))
                Ellipse().fill(Ink.blush.opacity(face.blush * 0.5)).frame(width: 20, height: 11)
                    .position(x: x + side * 37, y: y + 30)
            }
            mouth.position(x: x, y: y + 36)
            if let slide = face.sweat {
                Drop().fill(Ink.sweat).frame(width: 12, height: 18)
                    .overlay(Drop().stroke(Color.white.opacity(0.8), lineWidth: 1.2))
                    .position(x: x + 56, y: y - 12 + 26 * slide)
                    .opacity(slide < 0.9 ? 1 : (1 - slide) * 10)
            }
        }
    }

    private var bangs: some View {
        Path { p in
            p.move(to: CGPoint(x: x - 66, y: y + 4))
            p.addQuadCurve(to: CGPoint(x: x, y: y - 72), control: CGPoint(x: x - 70, y: y - 70))
            p.addQuadCurve(to: CGPoint(x: x + 66, y: y + 4), control: CGPoint(x: x + 70, y: y - 70))
            let tips: [(Double, Double, Double)] = [(52, -26, -4), (36, -12, -2), (22, -32, 0), (6, -14, 0),
                                                      (-10, -34, 0), (-26, -14, 0), (-40, -30, 0), (-58, -6, 0)]
            var last = CGPoint(x: x + 66, y: y + 4)
            for (dx, dy, _) in tips {
                let next = CGPoint(x: x + dx, y: y + dy)
                p.addQuadCurve(to: next, control: CGPoint(x: (last.x + next.x) / 2 + 2, y: max(last.y, next.y) - 2))
                last = next
            }
            p.addQuadCurve(to: CGPoint(x: x - 66, y: y + 4), control: CGPoint(x: x - 64, y: y - 6))
            p.closeSubpath()
            // A tuft that will not lie down.
            p.move(to: CGPoint(x: x + 6, y: y - 70))
            p.addQuadCurve(to: CGPoint(x: x + 30, y: y - 92), control: CGPoint(x: x + 8, y: y - 92))
            p.addQuadCurve(to: CGPoint(x: x + 18, y: y - 68), control: CGPoint(x: x + 22, y: y - 78))
            p.closeSubpath()
        }
        .fill(Ink.hair)
    }

    @ViewBuilder private func eye(at c: CGPoint) -> some View {
        switch face.eyes {
        case .open:
            ZStack {
                Ellipse().fill(Ink.line).frame(width: 12, height: 16).position(c)
                Circle().fill(.white).frame(width: 4.5, height: 4.5).position(x: c.x + 2, y: c.y - 3)
            }
        case .half:
            ZStack {
                Ellipse().fill(Ink.line).frame(width: 12, height: 9).position(x: c.x, y: c.y + 3)
                Capsule().fill(Ink.line).frame(width: 17, height: 3).position(x: c.x, y: c.y - 1)
            }
        case .closed:
            Path { p in
                p.move(to: CGPoint(x: c.x - 8, y: c.y))
                p.addQuadCurve(to: CGPoint(x: c.x + 8, y: c.y), control: CGPoint(x: c.x, y: c.y + 6))
            }.stroke(Ink.line, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        case .happy:
            Path { p in
                p.move(to: CGPoint(x: c.x - 8, y: c.y + 3))
                p.addQuadCurve(to: CGPoint(x: c.x + 8, y: c.y + 3), control: CGPoint(x: c.x, y: c.y - 8))
            }.stroke(Ink.line, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        case .squint:
            Path { p in
                p.move(to: CGPoint(x: c.x - 8, y: c.y + 1))
                p.addQuadCurve(to: CGPoint(x: c.x + 8, y: c.y + 1), control: CGPoint(x: c.x, y: c.y - 3))
            }.stroke(Ink.line, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
        case .wide:
            ZStack {
                Ellipse().fill(.white).frame(width: 18, height: 20).position(c)
                Ellipse().stroke(Ink.line, lineWidth: 2).frame(width: 18, height: 20).position(c)
                Circle().fill(Ink.line).frame(width: 6, height: 6).position(c)
            }
        case .look(let side):
            ZStack {
                Ellipse().fill(.white).frame(width: 17, height: 19).position(c)
                Ellipse().stroke(Ink.line, lineWidth: 2).frame(width: 17, height: 19).position(c)
                Ellipse().fill(Ink.line).frame(width: 9, height: 12).position(x: c.x + side * 4, y: c.y + 1)
                Circle().fill(.white).frame(width: 3, height: 3).position(x: c.x + side * 4 + 2, y: c.y - 2)
            }
        }
    }

    @ViewBuilder private var mouth: some View {
        switch face.mouth {
        case .flat:
            Capsule().fill(Ink.line).frame(width: 14, height: 3.2)
        case .sigh:
            Ellipse().fill(Ink.line).frame(width: 13, height: 15)
                .overlay(Ellipse().fill(Ink.blush).frame(width: 8, height: 5).offset(y: 4))
        case .wavy:
            Path { p in
                p.move(to: CGPoint(x: 0, y: 4))
                for i in 0..<4 { p.addQuadCurve(to: CGPoint(x: Double(i + 1) * 6, y: 4), control: CGPoint(x: Double(i) * 6 + 3, y: i.isMultiple(of: 2) ? 0 : 8)) }
            }
            .stroke(Ink.line, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .frame(width: 24, height: 8)
        case .smile:
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 24, y: 0))
                p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: 12, y: 22))
            }
            .fill(Ink.line)
            .overlay(Ellipse().fill(Ink.blush).frame(width: 11, height: 5).offset(y: 5))
            .frame(width: 24, height: 12)
        case .smirk:
            Path { p in
                p.move(to: CGPoint(x: 0, y: 6))
                p.addQuadCurve(to: CGPoint(x: 22, y: 0), control: CGPoint(x: 12, y: 9))
            }
            .stroke(Ink.line, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            .frame(width: 22, height: 9)
        case .tongue:
            ZStack {
                Capsule().fill(Ink.line).frame(width: 14, height: 3.2)
                Ellipse().fill(Ink.blush).frame(width: 8, height: 8).offset(x: 5, y: 4)
            }
        case .frown:
            Path { p in
                p.move(to: CGPoint(x: 0, y: 7))
                p.addQuadCurve(to: CGPoint(x: 20, y: 7), control: CGPoint(x: 10, y: -3))
            }
            .stroke(Ink.line, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            .frame(width: 20, height: 8)
        }
    }
}

private struct Drop: Shape {
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

/// Shoulders and chest in the hoodie, from the neck down past the bottom of the frame.
private struct Torso: View {
    let x: Double
    let y: Double      // where the neck meets the shoulders

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: x - 112, y: 820))
                p.addLine(to: CGPoint(x: x - 104, y: y + 52))
                p.addQuadCurve(to: CGPoint(x: x - 34, y: y), control: CGPoint(x: x - 98, y: y + 4))
                p.addLine(to: CGPoint(x: x + 34, y: y))
                p.addQuadCurve(to: CGPoint(x: x + 104, y: y + 52), control: CGPoint(x: x + 98, y: y + 4))
                p.addLine(to: CGPoint(x: x + 112, y: 820))
                p.closeSubpath()
            }
            .fill(Ink.hoodie)
            Ellipse().fill(Ink.hoodieDark).frame(width: 104, height: 34).position(x: x, y: y + 6)
            Rectangle().fill(Ink.skin).frame(width: 30, height: 30).position(x: x, y: y - 10)
            Ellipse().fill(Ink.skinShade).frame(width: 30, height: 10).position(x: x, y: y - 22)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Path { p in
                    p.move(to: CGPoint(x: x + side * 12, y: y + 16))
                    p.addLine(to: CGPoint(x: x + side * 15, y: y + 62))
                }
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 6, height: 10).position(x: x + side * 15, y: y + 66)
            }
        }
    }
}

/// A forearm in its sleeve and a hand, from below the frame of the laptop up to `hand`.
private struct Arm: View {
    let from: CGPoint
    let hand: CGPoint

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: from)
                p.addQuadCurve(to: hand, control: CGPoint(x: from.x + 14, y: (from.y + hand.y) / 2))
            }
            .stroke(Ink.hoodie, style: StrokeStyle(lineWidth: 30, lineCap: .round))
            Circle().fill(Ink.skin).frame(width: 30, height: 30).position(hand)
            Circle().stroke(Ink.skinShade, lineWidth: 1.5).frame(width: 30, height: 30).position(hand)
        }
    }
}

/// The lead from the waist up, for scenes drawn elsewhere: head at (225, 330), a hand that can reach the keys.
struct ReelLead: View {
    let face: ReelFace
    /// 0 resting … 1 reaching over the lid to press a key.
    var handUp = 0.0

    var body: some View {
        ZStack {
            Torso(x: 225, y: 410)
            if handUp > 0 { Arm(from: CGPoint(x: 335, y: 640), hand: CGPoint(x: 305, y: 520 - 50 * handUp)) }
            Head(x: 225, y: 330, face: face)
        }
    }
}

/// The lead's laptop, seen from behind, with the app's icon on the lid.
struct ReelLaptop: View {
    var body: some View { Laptop() }
}

// MARK: - Shots

/// Night at the desk: the lamp, the laptop's glow, and the face over the lid.
private struct DeskShot: View {
    let shot: String
    let t: Double

    var body: some View {
        let pose = pose
        ZStack {
            Ink.night
            NightWindow()
            Lamp()
            Torso(x: 225, y: 410 + pose.slump)
            // A hand on the head goes in front of it; one reaching for the keys, behind the lid.
            if let hand = pose.hand, shot != "A" { Arm(from: CGPoint(x: 330, y: 520), hand: hand) }
            Head(x: 225 + pose.lean.x, y: 330 + pose.slump + pose.lean.y, face: pose.face)
            if let hand = pose.hand, shot == "A" { Arm(from: CGPoint(x: 330, y: 520), hand: hand) }
            // The screen lights the face from below.
            Ellipse().fill(RadialGradient(colors: [Ink.screen.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 320, height: 240).position(x: 225, y: 430)
            Laptop()
            Desk(night: true)
            effects
        }
    }

    private struct Pose {
        var face = ReelFace()
        var slump = 0.0
        var lean = CGPoint.zero
        var hand: CGPoint?
    }

    private var pose: Pose {
        var pose = Pose()
        switch shot {
        case "A":   // a long sigh, then a scratch of the head
            let sigh = smooth(span(t, 0.3, 0.8))
            pose.slump = 10 * sigh
            pose.face = ReelFace(eyes: t < 0.3 ? .open : .half, brows: -1, mouth: t < 0.3 ? .flat : t < 1.1 ? .sigh : .wavy)
            if blinking(t, at: [0.15]) { pose.face.eyes = .closed }
            if t > 1.0 {
                let up = smooth(span(t, 1.0, 1.25))
                let scratch = sin(t * 2 * .pi * 7) * span(t, 1.25, 1.35)
                pose.hand = CGPoint(x: 300 - 16 * up + 5 * scratch, y: 520 - 218 * up + 4 * abs(scratch))
            }
        case "B":   // typing, deleting, sweating
            let bob = sin(t * 2 * .pi * 6) * 2.5
            pose.slump = bob
            pose.lean = CGPoint(x: 0, y: 6)
            pose.face = ReelFace(eyes: .wide, brows: 1, mouth: .wavy, sweat: span(t, 0.2, 1.9))
        case "D":   // leaning in to fill a blank
            pose.lean = CGPoint(x: 0, y: 12 * smooth(span(t, 0, 0.4)))
            pose.slump = sin(t * 2 * .pi * 5) * 1.5
            pose.face = ReelFace(eyes: .squint, brows: 0.8, mouth: .tongue)
        case "E":   // a nod, a press, a smile
            let nod = sin(.pi * span(t, 0.1, 0.45)) + sin(.pi * span(t, 0.45, 0.8))
            pose.lean = CGPoint(x: 0, y: 9 * nod)
            let done = t > 0.9
            pose.face = ReelFace(eyes: done ? .happy : .open, brows: 0, mouth: done ? .smile : .flat, blush: done ? 1 : 0.3)
            if t > 0.95 {
                let press = span(t, 0.95, 1.1) - span(t, 1.15, 1.35)
                pose.hand = CGPoint(x: 312, y: 460 + 16 * press)
            }
        default:
            break
        }
        return pose
    }

    @ViewBuilder private var effects: some View {
        switch shot {
        case "A":
            let puff = span(t, 0.45, 1.7)
            Text("唉～").font(.custom("PingFang TC", size: 26).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.75 * (1 - span(t, 1.4, 1.9))))
                .position(x: 168 - 10 * puff, y: 392 - 66 * puff)
                .opacity(t > 0.45 ? 1 : 0)
            Scribble(turn: t * 2.5)
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 70, height: 46)
                .scaleEffect(smooth(span(t, 1.15, 1.45)))
                .position(x: 225, y: 212)
        case "B":
            ForEach(0..<4, id: \.self) { i in
                let start = 0.15 + Double(i) * 0.42
                let rise = span(t, start, start + 0.8)
                Text("⌫").font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.45))
                    .position(x: 160 + Double(i % 2) * 130 + Double(i) * 6, y: 460 - 70 * rise)
                    .opacity(t > start ? 1 - rise : 0)
            }
        case "D":
            let pop = smooth(span(t, 0.8, 1.05))
            Text("12 點").font(.custom("PingFang TC", size: 22).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Ink.hoodie, in: Capsule())
                .scaleEffect(0.6 + 0.4 * pop)
                .opacity(pop)
                .position(x: 330, y: 430 - 24 * pop)
            Sparkles(progress: span(t, 0.95, 1.6)).position(x: 330, y: 405)
        case "E":
            let rise = span(t, 1.1, 1.75)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 40))
                .foregroundStyle(.white, Color(red: 0.2, green: 0.78, blue: 0.5))
                .position(x: 340, y: 420 - 60 * smooth(rise))
                .opacity(t > 1.1 ? 1 - span(t, 1.6, 1.8) : 0)
            Sparkles(progress: span(t, 1.1, 1.7)).position(x: 312, y: 455)
        default:
            EmptyView()
        }
    }
}

/// The ⌥Space close-up: a laptop keyboard from above, two thumbs, and a burst when both keys go down.
private struct KeyboardShot: View {
    let t: Double

    private static let rows = ["1234567890-", "QWERTYUIOP[", "ASDFGHJKL;'", "ZXCVBNM,./⇧"]
    private static let bottom: [(String, Double)] = [("fn", 30), ("⌃", 30), ("⌥", 36), ("⌘", 40), ("", 150), ("⌘", 40), ("⌥", 30)]

    var body: some View {
        let press = smooth(span(t, 0.3, 0.45)) - smooth(span(t, 0.95, 1.15))
        ZStack {
            Color(red: 0.12, green: 0.10, blue: 0.10)
            Ellipse().fill(RadialGradient(colors: [Ink.lamp.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 560, height: 420).position(x: 140, y: 380)
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [Color(white: 0.80), Color(white: 0.68)], startPoint: .top, endPoint: .bottom))
                .frame(width: 420, height: 268).position(x: 225, y: 440)
            VStack(spacing: 6) {
                ForEach(Self.rows, id: \.self) { row in
                    HStack(spacing: 5) { ForEach(Array(row), id: \.self) { key(String($0), width: 30) } }
                }
                HStack(spacing: 5) {
                    ForEach(Array(Self.bottom.enumerated()), id: \.offset) { index, item in
                        key(item.0, width: item.1, lit: (index == 2 || index == 4) ? press : 0, label: index == 2 ? "option" : nil)
                    }
                }
            }
            .position(x: 225, y: 440)
            Circle().stroke(Ink.hoodie.opacity(0.8 * (1 - span(t, 0.45, 1.0))), lineWidth: 4)
                .frame(width: 60 + 260 * span(t, 0.45, 1.0), height: 60 + 260 * span(t, 0.45, 1.0))
                .position(x: 238, y: 528)
                .opacity(t > 0.45 ? 1 : 0)
            Sparkles(progress: span(t, 0.42, 1.2), reach: 120).position(x: 238, y: 520)
            thumb(x: 128 - 6 * (1 - press), angle: 16, press: press)
            thumb(x: 250, angle: -10, press: press)
        }
    }

    private func key(_ label: String, width: Double, lit: Double = 0, label small: String? = nil) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: label.count > 1 ? 9 : 12, weight: .medium))
            if let small { Text(small).font(.system(size: 7)) }
        }
        .foregroundStyle(Color.white.opacity(0.85))
        .frame(width: width, height: 30)
        .background(RoundedRectangle(cornerRadius: 6).fill(lit > 0 ? Color(red: 0.12 + 0.2 * lit, green: 0.12 + 0.15 * lit, blue: 0.14 + 0.7 * lit)
                                                            : Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.hoodie.opacity(lit), lineWidth: 2))
        .shadow(color: Ink.hoodie.opacity(0.9 * lit), radius: 10 * lit)
        .scaleEffect(1 - 0.05 * lit)
    }

    private func thumb(x: Double, angle: Double, press: Double) -> some View {
        ZStack(alignment: .top) {
            Capsule().fill(Ink.skin).frame(width: 46, height: 150)
            Capsule().fill(Color(red: 1, green: 0.93, blue: 0.9)).frame(width: 26, height: 30).padding(.top, 8)
            Capsule().fill(Ink.hoodie).frame(width: 70, height: 60).offset(y: 120)
        }
        .rotationEffect(.degrees(angle))
        .position(x: x, y: 590 + 26 * (1 - press))
    }
}

/// The next morning: daylight, a phone, and a guilty grin.
private struct MorningShot: View {
    let t: Double

    var body: some View {
        let look: Double = t < 0.45 ? -1 : t < 0.9 ? 1 : 0
        let caught = t > 0.9
        let face = ReelFace(eyes: caught ? .look(0) : .look(look), brows: -0.6, mouth: caught ? .smirk : .flat,
                        blush: caught ? 0.9 : 0.2, sweat: span(t, 0.5, 1.6))
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 0.94, blue: 0.86), Color(red: 0.98, green: 0.85, blue: 0.74)],
                           startPoint: .top, endPoint: .bottom)
            SunWindow()
            Torso(x: 225, y: 410)
            Head(x: 225, y: 330 + (caught ? 3 : 0), face: face)
            Arm(from: CGPoint(x: 120, y: 560), hand: CGPoint(x: 180, y: 520))
            Arm(from: CGPoint(x: 330, y: 560), hand: CGPoint(x: 270, y: 520))
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.12))
                .frame(width: 74, height: 124).position(x: 225, y: 505)
            RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [Ink.screen.opacity(0.9), Ink.hoodie.opacity(0.8)],
                                                                   startPoint: .top, endPoint: .bottom))
                .frame(width: 62, height: 110).position(x: 225, y: 505)
            ZStack {
                Circle().fill(Color.red)
                Text("1").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 22, height: 22).position(x: 258, y: 446)
            Circle().fill(Ink.skin).frame(width: 30, height: 30).position(x: 186, y: 520)
            Circle().fill(Ink.skin).frame(width: 30, height: 30).position(x: 264, y: 520)
            Desk(night: false)
            Text("!?").font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.3))
                .rotationEffect(.degrees(12))
                .position(x: 320, y: 238)
                .opacity(t > 0.2 && t < 0.9 ? 1 : 0)
        }
    }
}

// MARK: - Props

private struct Laptop: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(white: 0.83), Color(white: 0.66)], startPoint: .top, endPoint: .bottom))
                .frame(width: 236, height: 146).position(x: 225, y: 527)
            Capsule().fill(Color.white.opacity(0.55)).frame(width: 220, height: 2.5).position(x: 225, y: 456)
            // A sticker of the app's icon on the lid.
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 52, height: 52)
                .rotationEffect(.degrees(-8))
                .position(x: 225, y: 522)
        }
    }
}

private struct Desk: View {
    let night: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(night ? Color(red: 0.20, green: 0.15, blue: 0.13) : Color(red: 0.80, green: 0.62, blue: 0.46))
                .frame(width: 450, height: 210).position(x: 225, y: 705)
            Rectangle().fill(Color.white.opacity(night ? 0.08 : 0.3)).frame(width: 450, height: 3).position(x: 225, y: 601)
            // A mug, and on the morning desk a plant.
            RoundedRectangle(cornerRadius: 8).fill(night ? Color(red: 0.86, green: 0.42, blue: 0.36) : .white)
                .frame(width: 40, height: 44).position(x: 64, y: 578)
            Circle().stroke(night ? Color(red: 0.86, green: 0.42, blue: 0.36) : .white, lineWidth: 6)
                .frame(width: 22, height: 22).position(x: 88, y: 576)
            if !night {
                RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.85, green: 0.5, blue: 0.35)).frame(width: 46, height: 40)
                    .position(x: 388, y: 580)
                ForEach([-24.0, 0, 24], id: \.self) { angle in
                    Ellipse().fill(Color(red: 0.36, green: 0.66, blue: 0.4)).frame(width: 18, height: 50)
                        .rotationEffect(.degrees(angle)).position(x: 388 + angle / 2, y: 540)
                }
            }
        }
    }
}

private struct Lamp: View {
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 96, y: 330))
                p.addLine(to: CGPoint(x: 10, y: 600))
                p.addLine(to: CGPoint(x: 250, y: 600))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Ink.lamp.opacity(0.28), Ink.lamp.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            Path { p in
                p.move(to: CGPoint(x: 40, y: 598))
                p.addLine(to: CGPoint(x: 58, y: 420))
                p.addLine(to: CGPoint(x: 92, y: 330))
            }
            .stroke(Color(white: 0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            Ellipse().fill(Color(white: 0.3)).frame(width: 54, height: 12).position(x: 40, y: 600)
            Capsule().fill(Color(white: 0.4)).frame(width: 64, height: 28).rotationEffect(.degrees(28)).position(x: 96, y: 324)
            Circle().fill(Ink.lamp).frame(width: 16, height: 16).blur(radius: 3).position(x: 104, y: 338)
        }
    }
}

private struct NightWindow: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.10, green: 0.14, blue: 0.30))
                .frame(width: 120, height: 130).position(x: 362, y: 290)
            RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.3), lineWidth: 5)
                .frame(width: 120, height: 130).position(x: 362, y: 290)
            Rectangle().fill(Color(white: 0.3)).frame(width: 4, height: 130).position(x: 362, y: 290)
            Circle().fill(Color(red: 1, green: 0.95, blue: 0.75)).frame(width: 30, height: 30).position(x: 390, y: 258)
            Circle().fill(Color(red: 0.10, green: 0.14, blue: 0.30)).frame(width: 26, height: 26).position(x: 399, y: 252)
            ForEach([(330.0, 250.0), (345, 315), (395, 320), (320, 290)], id: \.0) { star in
                Text("✦").font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.7)).position(x: star.0, y: star.1)
            }
            Text("23:47").font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.4).opacity(0.9))
                .position(x: 362, y: 372)
        }
    }
}

private struct SunWindow: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.72, green: 0.88, blue: 1.0))
                .frame(width: 130, height: 140).position(x: 90, y: 290)
            Circle().fill(Color(red: 1, green: 0.84, blue: 0.4)).frame(width: 44, height: 44).position(x: 70, y: 262)
            RoundedRectangle(cornerRadius: 10).stroke(Color.white, lineWidth: 6)
                .frame(width: 130, height: 140).position(x: 90, y: 290)
            Rectangle().fill(Color.white).frame(width: 5, height: 140).position(x: 90, y: 290)
            Text("08:12").font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.55, green: 0.4, blue: 0.3))
                .position(x: 90, y: 378)
        }
    }
}

/// A tangle of a line above a worried head.
private struct Scribble: Shape {
    let turn: Double

    func path(in r: CGRect) -> Path {
        Path { p in
            let c = CGPoint(x: r.midX, y: r.midY)
            for step in 0...80 {
                let a = Double(step) / 80 * 6 * .pi + turn
                let radius = 0.5 + 0.5 * sin(Double(step) * 0.37)
                let point = CGPoint(x: c.x + cos(a) * r.width / 2 * radius, y: c.y + sin(a) * r.height / 2 * radius)
                step == 0 ? p.move(to: point) : p.addLine(to: point)
            }
        }
    }
}

/// Wingman's ✦, flying out and fading.
private struct Sparkles: View {
    let progress: Double
    var reach = 70.0

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let angle = Double(i) / 7 * 2 * .pi - .pi / 2
                Text("✦")
                    .font(.system(size: i.isMultiple(of: 2) ? 22 : 15))
                    .foregroundStyle(i.isMultiple(of: 3) ? Color(red: 0.4, green: 0.9, blue: 0.95) : Color.white)
                    .offset(x: cos(angle) * reach * smooth(progress), y: sin(angle) * reach * smooth(progress))
                    .opacity(progress > 0 ? 1 - span(progress, 0.6, 1) : 0)
            }
        }
    }
}
