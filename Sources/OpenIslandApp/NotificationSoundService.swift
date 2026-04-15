import AppKit
import AudioToolbox

/// Manages notification sound playback using macOS system sounds.
///
/// Uses AudioToolbox's `AudioServicesPlaySystemSound` instead of `NSSound`
/// because the latter relies on bundle context and silently fails when the
/// app is launched via `swift run` or any other non-bundled path.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"
    static let defaultSoundName = "Bottle"

    /// Cache of registered system sound IDs so we don't re-register the same
    /// file on every notification. Keyed by sound name (e.g. "Bottle").
    private static var soundIDCache: [String: SystemSoundID] = [:]

    /// Returns the list of available system sound names (without file extension).
    static func availableSounds() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: soundsDirectory) else {
            return []
        }
        return contents
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }

    /// The currently selected sound name, persisted in UserDefaults.
    static var selectedSoundName: String {
        get {
            UserDefaults.standard.string(forKey: defaultsKey) ?? defaultSoundName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// Plays a system sound by name.
    static func play(_ name: String) {
        let soundID: SystemSoundID
        if let cached = soundIDCache[name] {
            soundID = cached
        } else {
            let url = URL(fileURLWithPath: soundsDirectory)
                .appendingPathComponent("\(name).aiff")
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }
            var id: SystemSoundID = 0
            let status = AudioServicesCreateSystemSoundID(url as CFURL, &id)
            guard status == kAudioServicesNoError else {
                return
            }
            soundIDCache[name] = id
            soundID = id
        }
        AudioServicesPlaySystemSound(soundID)
    }

    /// Plays the user-selected notification sound, respecting the mute setting.
    static func playNotification(isMuted: Bool) {
        guard !isMuted else { return }
        play(selectedSoundName)
    }
}
