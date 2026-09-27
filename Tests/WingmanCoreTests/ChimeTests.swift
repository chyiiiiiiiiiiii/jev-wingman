import Foundation
import Testing
@testable import WingmanCore

@Test(arguments: Chime.Voice.allCases, Chime.Event.allCases)
func everySoundIsShortQuietAndClickFree(voice: Chime.Voice, event: Chime.Event) {
    let samples = Chime.samples(voice, event)
    let seconds = Double(samples.count / 2) / Double(Chime.sampleRate)
    let peak = samples.map(abs).max() ?? 0

    #expect(seconds <= 1)
    // Audible, but far under full scale (0 dBFS): about -11 dBFS at most.
    #expect(peak > 0.05 && peak <= 0.3)
    let finite = samples.allSatisfy(\.isFinite)
    #expect(finite)
    // Starting or stopping on a non-zero sample is a click.
    let edges = Array(samples.prefix(2) + samples.suffix(2)).map(abs).max() ?? 0
    #expect(edges < 0.001)
}

@Test func readyAndInsertedSoundDifferent() {
    for voice in Chime.Voice.allCases {
        #expect(Chime.samples(voice, .ready) != Chime.samples(voice, .inserted))
    }
}

@Test func writesAPlayableWaveFile() {
    let samples: [Float] = [0, 0.5, -0.5, 1]
    let wav = Chime.wav(samples)
    func uint32(_ offset: Int) -> UInt32 { wav[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
    func uint16(_ offset: Int) -> UInt16 { UInt16(wav[offset]) | UInt16(wav[offset + 1]) << 8 }

    #expect(String(decoding: wav[0..<4], as: UTF8.self) == "RIFF")
    #expect(String(decoding: wav[8..<12], as: UTF8.self) == "WAVE")
    #expect(uint16(20) == 1)          // PCM
    #expect(uint16(22) == 2)          // stereo
    #expect(uint32(24) == 44_100)
    #expect(uint16(34) == 16)         // bits per sample
    #expect(uint32(40) == 8)          // four samples, two bytes each
    #expect(wav.count == 44 + 8)
    #expect(Int16(bitPattern: uint16(46)) == 16_384)   // 0.5 of full scale
    #expect(Int16(bitPattern: uint16(50)) == 32_767)
}
