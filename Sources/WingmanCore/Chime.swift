import Foundation

/// Two short, quiet sounds: suggestions are ready while you wait for them, and a reply was typed in.
///
/// They are synthesised rather than shipped as files: a few sine partials under a soft envelope and a small
/// room, so each voice stays warm and short, and the tests can hold every one to a loudness and length limit.
public enum Chime {
    public enum Event: CaseIterable { case ready, inserted }

    /// In the order settings shows them: tuned voices first, then the textures.
    public enum Voice: String, CaseIterable {
        /// A soft mallet on wood, like a marimba.
        case wood
        /// A plucked metal tine.
        case kalimba
        /// A plucked string; ready is a quick three-note arpeggio.
        case harp
        /// An electric piano's bell-like tone.
        case keys
        /// A small glass bell.
        case glass
        /// A water drop.
        case droplet
        /// A knock on a hollow bamboo tube.
        case bamboo
        /// A barely-there tap, like a trackpad click.
        case tap
    }

    public static let sampleRate = 44_100

    /// Stereo samples, interleaved left and right, in -1…1.
    public static func samples(_ voice: Voice, _ event: Event) -> [Float] {
        let ready = event == .ready
        var dry = [Double](repeating: 0, count: Int(length(voice) * Double(sampleRate)))
        switch voice {
        case .wood:
            let mallet = [Partial(1, 1, 0.13), Partial(4, 0.22, 0.03), Partial(9.9, 0.05, 0.01)]
            if ready {
                strike(&dry, at: 0, pitch: 659.26, partials: mallet)                // E5
                strike(&dry, at: 0.085, pitch: 987.77, level: 0.85, partials: mallet)  // B5, a fifth up
            } else {
                strike(&dry, at: 0, pitch: 783.99, partials: mallet.map { $0.shortened(0.7) })   // G5
            }
        case .droplet:
            let drop = [Partial(1, 1, 0.055), Partial(2, 0.08, 0.02)]
            if ready {
                strike(&dry, at: 0, pitch: 880, partials: drop, glide: 0.5)
                strike(&dry, at: 0.09, pitch: 1175, level: 0.8, partials: drop, glide: 0.5)
            } else {
                strike(&dry, at: 0, pitch: 740, partials: drop, glide: 0.45)
            }
        case .glass:
            // A struck bar's overtones are not whole multiples; that is what makes it ring like glass.
            let bell = [Partial(1, 1, 0.3), Partial(2.76, 0.25, 0.12), Partial(5.4, 0.08, 0.05), Partial(8.93, 0.03, 0.02)]
            if ready {
                strike(&dry, at: 0, pitch: 880, partials: bell)                      // A5
                strike(&dry, at: 0.07, pitch: 1318.51, level: 0.6, partials: bell)  // E6
            } else {
                strike(&dry, at: 0, pitch: 1046.5, level: 0.8, partials: bell.map { $0.shortened(0.5) })  // C6
            }
        case .tap:
            let thump = [Partial(1, 1, 0.018), Partial(2.3, 0.2, 0.008)]
            strike(&dry, at: 0, pitch: 190, partials: thump, click: 0.3)
            if ready { strike(&dry, at: 0.07, pitch: 240, level: 0.8, partials: thump, click: 0.3) }
        case .kalimba:
            // A tine is a bar clamped at one end: its overtones sit at 6.27 and 17.55 times the note.
            let tine = [Partial(1, 1, 0.38), Partial(6.267, 0.16, 0.045), Partial(17.55, 0.03, 0.012)]
            if ready {
                strike(&dry, at: 0, pitch: 659.26, partials: tine, click: 0.05)                // E5
                strike(&dry, at: 0.1, pitch: 880, level: 0.85, partials: tine, click: 0.05)    // A5, a fourth up
            } else {
                strike(&dry, at: 0, pitch: 523.25, level: 0.9, partials: tine.map { $0.shortened(0.6) }, click: 0.05)  // C5
            }
        case .harp:
            if ready {
                for (index, pitch) in [523.25, 659.26, 783.99].enumerated() {                  // C5 E5 G5
                    pluck(&dry, at: Double(index) * 0.065, pitch: pitch, level: 1 - Double(index) * 0.1)
                }
            } else {
                pluck(&dry, at: 0, pitch: 392, level: 0.9, sustain: 0.992)                     // G4
            }
        case .keys:
            if ready {
                electricPiano(&dry, at: 0, pitch: 440)                                          // A4
                electricPiano(&dry, at: 0.08, pitch: 659.26, level: 0.8)                        // E5, a fifth up
            } else {
                electricPiano(&dry, at: 0, pitch: 554.37, level: 0.85, decay: 0.3)              // C#5
            }
        case .bamboo:
            // A hollow tube's modes are close and die fast; a little noise is the stick.
            let tube = [Partial(1, 1, 0.07), Partial(2.37, 0.45, 0.035), Partial(4.1, 0.15, 0.015)]
            if ready {
                strike(&dry, at: 0, pitch: 520, partials: tube, click: 0.25)
                strike(&dry, at: 0.09, pitch: 693, level: 0.85, partials: tube, click: 0.25)
            } else {
                strike(&dry, at: 0, pitch: 440, level: 0.9, partials: tube, click: 0.25)
            }
        }
        return finish(room(dry), peak: loudness(voice) * (ready ? 1 : 0.75))
    }

    /// 16-bit PCM WAV, stereo, for NSSound or AVAudioPlayer.
    public static func wav(_ samples: [Float]) -> Data {
        let channels = 2, bytesPerSample = 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let body = samples.count * bytesPerSample
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + body))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(channels))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * channels * bytesPerSample))
        append(UInt16(channels * bytesPerSample)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(body))
        for sample in samples { append(Int16((max(-1, min(1, sample)) * 32_767).rounded())) }
        return data
    }

    // MARK: - Synthesis

    private struct Partial {
        let ratio: Double, level: Double, decay: Double
        init(_ ratio: Double, _ level: Double, _ decay: Double) { self.ratio = ratio; self.level = level; self.decay = decay }
        func shortened(_ factor: Double) -> Partial { Partial(ratio, level, decay * factor) }
    }

    /// Seconds of sound, room tail included.
    private static func length(_ voice: Voice) -> Double {
        switch voice {
        case .wood: 0.75
        case .kalimba, .harp, .keys, .glass: 0.9
        case .droplet: 0.5
        case .bamboo: 0.45
        case .tap: 0.35
        }
    }

    /// Peak level: a bright bell sounds louder than a low tap at the same level. All sit well under full scale.
    private static func loudness(_ voice: Voice) -> Double {
        switch voice {
        case .wood: 0.22
        case .kalimba: 0.17
        case .harp: 0.2
        case .keys: 0.18
        case .glass: 0.15
        case .droplet: 0.18
        case .bamboo: 0.24
        case .tap: 0.28
        }
    }

    /// One note: partials decaying at their own rates under a raised-cosine attack (no click). `glide` bends
    /// the pitch up by that fraction in the first few milliseconds, the way a drop of water sounds.
    /// `click` adds a little softened noise at the start, the body of a tap.
    private static func strike(_ buffer: inout [Double], at start: Double, pitch: Double, level: Double = 1,
                               partials: [Partial], glide: Double = 0, click: Double = 0) {
        let rate = Double(sampleRate), first = Int(start * rate), attack = 0.004, bend = 0.012
        var noise: UInt32 = 0x2545_F491, smooth = 0.0
        for i in first..<buffer.count {
            let t = Double(i - first) / rate
            let onset = t < attack ? 0.5 - 0.5 * cos(Double.pi * t / attack) : 1
            // Phase of a pitch rising from `pitch` to `pitch * (1 + glide)`: the integral of the frequency.
            let travelled = t + glide * (t - bend * (1 - exp(-t / bend)))
            var sum = 0.0
            for partial in partials {
                let envelope = partial.level * exp(-t / partial.decay)
                guard envelope > 1e-5 else { continue }
                sum += envelope * sin(2 * Double.pi * pitch * partial.ratio * travelled)
            }
            if click > 0 && t < 0.03 {
                noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5
                smooth += 0.25 * (Double(noise) / Double(UInt32.max) * 2 - 1 - smooth)
                sum += click * smooth * exp(-t / 0.004)
            }
            buffer[i] += level * onset * sum
        }
    }

    /// A plucked string (Karplus–Strong): a burst of softened noise circulating in a delay one period long,
    /// averaged on each pass so the highs die first, the way a string's do.
    private static func pluck(_ buffer: inout [Double], at start: Double, pitch: Double, level: Double = 1,
                              sustain: Double = 0.995) {
        let rate = Double(sampleRate), first = Int(start * rate)
        let period = max(2, Int((rate / pitch).rounded()))
        var noise: UInt32 = 0x9E37_79B9, soft = 0.0
        var line = (0..<period).map { _ -> Double in
            noise ^= noise << 13; noise ^= noise >> 17; noise ^= noise << 5
            soft += 0.5 * (Double(noise) / Double(UInt32.max) * 2 - 1 - soft)   // a felt pick, not a nail
            return soft
        }
        var index = 0, previous = 0.0
        for i in first..<buffer.count {
            let t = Double(i - first) / rate
            let onset = t < 0.002 ? 0.5 - 0.5 * cos(Double.pi * t / 0.002) : 1
            let current = line[index]
            line[index] = sustain * 0.5 * (current + previous)
            previous = current
            index = (index + 1) % period
            buffer[i] += level * onset * current
        }
    }

    /// An electric piano, by frequency modulation: a bright attack that mellows as the modulation fades,
    /// with the brief high ping of the tine on top.
    private static func electricPiano(_ buffer: inout [Double], at start: Double, pitch: Double, level: Double = 1,
                                      decay: Double = 0.55) {
        let rate = Double(sampleRate), first = Int(start * rate), attack = 0.003
        for i in first..<buffer.count {
            let t = Double(i - first) / rate
            let onset = t < attack ? 0.5 - 0.5 * cos(Double.pi * t / attack) : 1
            let index = 1.6 * exp(-t / 0.18)
            let body = sin(2 * Double.pi * pitch * t + index * sin(2 * Double.pi * pitch * t)) * exp(-t / decay)
            let ping = 0.06 * sin(2 * Double.pi * pitch * 14 * t) * exp(-t / 0.015)
            buffer[i] += level * onset * (body + ping)
        }
    }

    /// A small room, slightly different in each ear: four damped combs and an allpass per side (Schroeder).
    private static func room(_ dry: [Double]) -> (left: [Double], right: [Double]) {
        func side(_ combs: [Double]) -> [Double] {
            let rate = Double(sampleRate)
            var wet = [Double](repeating: 0, count: dry.count)
            for milliseconds in combs {
                let delay = Int(milliseconds / 1000 * rate)
                var line = [Double](repeating: 0, count: delay), index = 0, damped = 0.0
                for i in 0..<dry.count {
                    let out = line[index]
                    damped = out * 0.65 + damped * 0.35
                    line[index] = dry[i] + damped * 0.62
                    index = (index + 1) % delay
                    wet[i] += out / Double(combs.count)
                }
            }
            let delay = Int(0.005 * rate)
            var line = [Double](repeating: 0, count: delay), index = 0
            for i in 0..<wet.count {
                let delayed = line[index]
                let input = wet[i] + delayed * 0.5
                line[index] = input
                wet[i] = delayed - input * 0.5
                index = (index + 1) % delay
            }
            return zip(dry, wet).map { $0 + 0.16 * $1 }
        }
        return (side([29.7, 37.1, 41.1, 43.7]), side([30.9, 36.2, 42.3, 45.1]))
    }

    /// Scaled to `peak`, faded to silence over the last tenth of a second, interleaved.
    private static func finish(_ sound: (left: [Double], right: [Double]), peak: Double) -> [Float] {
        let loudest = max(sound.left.map(abs).max() ?? 0, sound.right.map(abs).max() ?? 0)
        let gain = loudest > 0 ? peak / loudest : 0
        let fade = min(sound.left.count, sampleRate / 10)
        var out = [Float](repeating: 0, count: sound.left.count * 2)
        for i in 0..<sound.left.count {
            let remaining = sound.left.count - 1 - i
            let tail = remaining < fade ? Double(remaining) / Double(fade) : 1
            out[i * 2] = Float(sound.left[i] * gain * tail)
            out[i * 2 + 1] = Float(sound.right[i] * gain * tail)
        }
        return out
    }
}
