import AppKit

/// Manages notification sound playback using macOS system sounds.
///
/// Shells out to `/usr/bin/afplay` to play the sound. Both `NSSound` and
/// `AudioServicesPlaySystemSound` silently fail when the app is launched
/// outside of a signed `.app` bundle (e.g. `swift run` for local dev, or
/// any dev-signed bundle whose cdhash has drifted). `afplay` is a tiny
/// command-line tool shipped with macOS that has no such constraint and
/// reliably plays .aiff/.wav/.mp3 at the current system volume.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    private static let defaultsKey = "notification.sound.name"
    private static let afplayPath = "/usr/bin/afplay"
    static let defaultSoundName = "Bottle"

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
        let url = URL(fileURLWithPath: soundsDirectory)
            .appendingPathComponent("\(name).aiff")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        // Detach on a background queue so the Process.run + short-lived
        // afplay child doesn't block the main actor. Fire-and-forget.
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: afplayPath)
            process.arguments = [url.path]
            process.standardOutput = nil
            process.standardError = nil
            try? process.run()
        }
    }

    /// Plays the user-selected notification sound, respecting the mute setting.
    static func playNotification(isMuted: Bool) {
        guard !isMuted else { return }
        play(selectedSoundName)
    }
}
