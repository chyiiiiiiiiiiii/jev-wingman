import AudioToolbox
import Foundation
import WingmanCore

/// Plays Wingman's two sounds. They mark moments you waited for, never background work: suggestions
/// finishing while the panel is open, and a reply landing in the message box.
///
/// They go out as system sound effects, like the Mac's own interface sounds: at the alert volume, on the
/// device chosen for sound effects, and silent when "Play user interface sound effects" is off.
@MainActor
enum Sounds {
    private static var made: [String: SystemSoundID] = [:]

    /// Bumped whenever `Chime` changes, so an older cached file is never played.
    private static let version = 1

    static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.moniit.wingman/Sounds", isDirectory: true)

    static func play(_ event: Chime.Event) {
        guard Prefs.shared.soundsOn else { return }
        play(Prefs.shared.soundVoice, event)
    }

    /// Also the preview when a voice is picked in settings.
    static func play(_ voice: Chime.Voice, _ event: Chime.Event) {
        guard let id = sound(voice, event) else { return }
        AudioServicesPlaySystemSound(id)
    }

    /// Makes the chosen voice ahead of time, so the first sound is not late.
    static func prepare() {
        for event in Chime.Event.allCases { _ = sound(Prefs.shared.soundVoice, event) }
    }

    /// The Mac-wide switch in System Settings › Sound; when it is off, no interface sound plays, Wingman's included.
    static var systemAllowsThem: Bool {
        CFPreferencesCopyAppValue("com.apple.sound.uiaudio.enabled" as CFString, kCFPreferencesAnyApplication) as? Int != 0
    }

    private static func sound(_ voice: Chime.Voice, _ event: Chime.Event) -> SystemSoundID? {
        let name = "v\(version)-\(voice.rawValue)-\(event).wav"
        if let id = made[name] { return id }
        let file = folder.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? Chime.wav(Chime.samples(voice, event)).write(to: file, options: .atomic)) != nil else { return nil }
        }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(file as CFURL, &id) == kAudioServicesNoError else { return nil }
        made[name] = id
        return id
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
