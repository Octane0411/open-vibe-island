import Foundation

/// Custom packages use the same product label in macOS and the app UI.
enum AppBranding {
    static let displayName: String = {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? "Open Island"
    }()

    static var settingsWindowTitle: String { "\(displayName) Settings" }

    static func apply(to text: String) -> String {
        guard displayName != "Open Island" else { return text }
        return text
            .replacingOccurrences(of: "Open Island OSS", with: displayName)
            .replacingOccurrences(of: "Open Island", with: displayName)
    }
}
