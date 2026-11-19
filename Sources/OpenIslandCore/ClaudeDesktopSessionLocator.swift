import Foundation

/// Maps a Claude Code CLI session ID to the Claude desktop app's own
/// `local_…` session ID.
///
/// Claude.app keeps one JSON record per Code session under
/// `~/Library/Application Support/Claude/claude-code-sessions/<org>/<user>/local_<id>.json`
/// with both identifiers (`sessionId` and `cliSessionId`). Its
/// `claude://code/continue?session=` deep link validates the parameter
/// against `^local_[A-Za-z0-9-]{1,64}$`, so the CLI UUID hooks report must be
/// translated before the jump can target the exact conversation.
public enum ClaudeDesktopSessionLocator {
    public static let continueURLPrefix = "claude://code/continue?session="

    private static let desktopSessionIDPattern = try! NSRegularExpression(
        pattern: "^local_[A-Za-z0-9-]{1,64}$"
    )

    public static func defaultSessionsDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    /// Returns the desktop session ID for `cliSessionID`, or `nil` when no
    /// record references it. Scans at most two directory levels below
    /// `sessionsDirectory`, matching the layout Claude.app writes.
    public static func desktopSessionID(
        forCLISessionID cliSessionID: String,
        sessionsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        let trimmedCLISessionID = cliSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCLISessionID.isEmpty else {
            return nil
        }

        let root = sessionsDirectory ?? defaultSessionsDirectory(fileManager: fileManager)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json",
                  fileURL.lastPathComponent.hasPrefix("local_") else {
                continue
            }
            guard let record = loadRecord(at: fileURL),
                  record.cliSessionId.caseInsensitiveCompare(trimmedCLISessionID) == .orderedSame else {
                continue
            }
            let desktopSessionID = record.sessionId ?? fileURL.deletingPathExtension().lastPathComponent
            return isValidDesktopSessionID(desktopSessionID) ? desktopSessionID : nil
        }

        return nil
    }

    public static func continueURL(forDesktopSessionID desktopSessionID: String) -> String? {
        guard isValidDesktopSessionID(desktopSessionID) else {
            return nil
        }
        return continueURLPrefix + desktopSessionID
    }

    public static func isValidDesktopSessionID(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return desktopSessionIDPattern.firstMatch(in: value, range: range) != nil
    }

    private struct SessionRecord: Decodable {
        var sessionId: String?
        var cliSessionId: String
    }

    private static func loadRecord(at url: URL) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionRecord.self, from: data)
    }
}
