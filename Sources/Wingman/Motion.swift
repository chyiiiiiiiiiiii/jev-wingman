import SwiftUI

// Loading and reveal motion, after ChunUI (github.com/liseami/ChunUI, MIT) — CCSkeleton's bars and the
// chat reveal numbers Lulo took from it: 320 ms, cubic (0.22, 0.8, 0.36, 1), 14 pt, 70 ms apart.

enum Motion {
    static let reveal = Animation.timingCurve(0.22, 0.8, 0.36, 1, duration: 0.32)
    static let stagger = 0.07
    static let rise: CGFloat = 14

    /// A draft sliding up into place, later ones a beat behind.
    static func arrival(_ index: Int) -> AnyTransition {
        .opacity.combined(with: .offset(y: rise)).animation(reveal.delay(Double(index) * stagger))
    }
}

/// One skeleton bar. Every bar sweeps on its own rhythm (1.3–1.7 s from a random phase), because bars
/// pulsing in step look mechanical; the highlight is 8% of the foreground; Reduce Motion stops it.
struct Bone: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: radius ?? height / 2)
            .fill(Color.primary.opacity(0.10))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .modifier(BoneSweep())
    }
}

extension EnvironmentValues {
    /// Off while the panel is put away: a hidden window's timeline still redraws 30 times a second, which
    /// kept Wingman at about 15% CPU with no chat in front.
    @Entry var skeletonMoves = true
}

private struct BoneSweep: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.skeletonMoves) private var moves
    @State private var duration = Double.random(in: 1.3...1.7)
    @State private var phase = Double.random(in: 0..<1)

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geometry in
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !moves)) { timeline in
                        let raw = (timeline.date.timeIntervalSinceReferenceDate / duration + phase)
                            .truncatingRemainder(dividingBy: 1)
                        let eased = raw * raw * (3 - 2 * raw)          // ease-in-out, fast through the middle
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: Color.primary.opacity(0.08), location: 0.5),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width)
                            .offset(x: (eased * 2 - 1) * geometry.size.width)
                    }
                    .transaction { $0.animation = nil }
                }
                .mask(content)
            }
        }
    }
}

/// Stands in for a draft while it is being written, the same height so the panel does not jump.
struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Bone(width: 20, height: 20, radius: 5)
            VStack(alignment: .leading, spacing: 7) {
                Bone(width: 56, height: 9)
                Bone(height: 11)
                Bone(height: 11).padding(.trailing, 140)
            }
            .padding(.top, 2)
        }
        .padding(8)
    }
}
