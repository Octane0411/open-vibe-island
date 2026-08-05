import Foundation

/// Reads Claude Code's live session index at `<config dir>/sessions/`.
///
/// Claude Code maintains one small JSON file per running process
/// (`{pid}.json`) containing the session id and its current name. The
/// `name` field reflects `/rename` immediately, which makes this the
/// live complement to the `custom-title` transcript records that
/// `ClaudeTranscriptDiscovery` picks up on startup. Files are removed
/// when the session exits.
public final class ClaudeLiveSessionIndex: @unchecked Sendable {

    public static var defaultRootURL: URL {
        ClaudeConfigDirectory.resolved()
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private let rootURL: URL?
    private let fileManager: FileManager

    /// - Parameter rootURL: Injectable for tests. When `nil`, the root is
    ///   resolved per call so a changed Claude config directory takes
    ///   effect without restarting the app.
    public init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    /// Session names the user assigned themselves (`/rename`, `--name`),
    /// keyed by session id.
    ///
    /// Auto-generated names are excluded: Claude Code marks those with
    /// `nameSource` values like `"derived"` or `"auto"`, while user-assigned
    /// names carry `"user"` or omit the field entirely.
    public func userAssignedSessionNames() -> [String: String] {
        let rootURL = rootURL ?? Self.defaultRootURL
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var namesBySessionID: [String: String] = [:]

        for fileURL in fileURLs where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionID = object["sessionId"] as? String,
                  !sessionID.isEmpty,
                  let name = object["name"] as? String,
                  !name.isEmpty else {
                continue
            }

            if let nameSource = object["nameSource"] as? String,
               nameSource != "user" {
                continue
            }

            namesBySessionID[sessionID] = name
        }

        return namesBySessionID
    }
}
