import AppKit
import WingmanCore

/// Plays Wingman's two sounds. They mark moments you waited for, never background work: suggestions
/// finishing while the panel is open, and a reply landing in the message box.
@MainActor
enum Sounds {
    private static var made: [String: Data] = [:]
    private static var playing: [NSSound] = []

    static func play(_ event: Chime.Event) {
        guard Prefs.shared.soundsOn else { return }
        play(Prefs.shared.soundVoice, event)
    }

    /// Also the preview when a voice is picked in settings.
    static func play(_ voice: Chime.Voice, _ event: Chime.Event) {
        let key = "\(voice.rawValue).\(event)"
        let data = made[key] ?? Chime.wav(Chime.samples(voice, event))
        made[key] = data
        guard let sound = NSSound(data: data) else { return }
        playing.removeAll { !$0.isPlaying }
        playing.append(sound)     // NSSound stops when released
        sound.play()
    }

    /// Makes the chosen voice ahead of time, so the first sound is not late.
    static func prepare() {
        for event in Chime.Event.allCases {
            let voice = Prefs.shared.soundVoice
            let key = "\(voice.rawValue).\(event)"
            if made[key] == nil { made[key] = Chime.wav(Chime.samples(voice, event)) }
        }
    }
}

extension Chime.Voice {
    var name: String {
        switch self {
        case .wood: L("木質")
        case .droplet: L("水滴")
        case .glass: L("玻璃")
        case .tap: L("輕觸")
        }
    }
}
