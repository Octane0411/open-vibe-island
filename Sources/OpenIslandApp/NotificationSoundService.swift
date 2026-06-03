import AppKit

/// Different types of notification events that can have distinct sounds.
public enum NotificationEventType: String, CaseIterable, Identifiable {
    case completion = "completion"
    case permission = "permission"
    case question = "question"

    public var id: String { rawValue }
}

/// Manages notification sound playback using macOS system sounds.
@MainActor
struct NotificationSoundService {
    private static let soundsDirectory = "/System/Library/Sounds"
    static let defaultSoundName = "Bottle"
    private static let selectedSoundNameDefaultsKey = "notification.sound.name"

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
            UserDefaults.standard.string(forKey: selectedSoundNameDefaultsKey) ?? defaultSoundName
        }
        set {
            UserDefaults.standard.set(newValue, forKey: selectedSoundNameDefaultsKey)
        }
    }

    /// Gets the UserDefaults key for a specific event type.
    private static func defaultsKey(for eventType: NotificationEventType) -> String {
        "notification.sound.\(eventType.rawValue)"
    }

    /// Gets the sound name for a specific event type.
    static func soundName(for eventType: NotificationEventType) -> String {
        UserDefaults.standard.string(forKey: defaultsKey(for: eventType)) ?? defaultSoundName
    }

    /// Sets the sound name for a specific event type.
    static func setSoundName(_ name: String, for eventType: NotificationEventType) {
        UserDefaults.standard.set(name, forKey: defaultsKey(for: eventType))
    }

    /// Plays a system sound by name.
    static func play(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            return
        }
        sound.stop()
        sound.play()
    }

    /// Plays the notification sound for a specific event type, respecting the mute setting.
    static func playNotification(_ eventType: NotificationEventType, isMuted: Bool) {
        guard !isMuted else { return }
        play(soundName(for: eventType))
    }
}
