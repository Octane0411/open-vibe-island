import Foundation

/// Reads Claude Code's background daemon roster (`<config dir>/daemon/roster.json`).
///
/// The daemon keeps warm spare engines ready for the next dispatched session.
/// A spare already owns a reserved session ID and fires `SessionStart`, but it
/// is not a session the user started until a dispatch claims it. The roster
/// marks unclaimed spares with `dispatch.source == "spare"`; claimed sessions
/// carry `"fleet"` (`claude agents`) or `"shell"` (`claude --bg`).
///
/// The roster is a Claude Code internal file, so every reader fails open: an
/// unreadable or unexpected roster yields no spares and nothing is filtered.
public enum ClaudeDaemonRoster {
    public static func rosterURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        ClaudeConfigDirectory.resolved(environment: environment)
            .appendingPathComponent("daemon", isDirectory: true)
            .appendingPathComponent("roster.json")
    }

    /// Lowercased session IDs of warm spares that no dispatch has claimed.
    public static func unclaimedSpareSessionIDs(rosterData: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: rosterData) as? [String: Any],
              let workers = root["workers"] as? [String: Any] else {
            return []
        }

        var sessionIDs: Set<String> = []
        for case let worker as [String: Any] in workers.values {
            guard let dispatch = worker["dispatch"] as? [String: Any],
                  dispatch["source"] as? String == "spare",
                  let sessionID = (worker["sessionId"] as? String) ?? (dispatch["sessionId"] as? String),
                  !sessionID.isEmpty else {
                continue
            }
            sessionIDs.insert(sessionID.lowercased())
        }
        return sessionIDs
    }

    public static func unclaimedSpareSessionIDs(at url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return unclaimedSpareSessionIDs(rosterData: data)
    }

    public static func isUnclaimedSpare(
        sessionID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        unclaimedSpareSessionIDs(at: rosterURL(environment: environment))
            .contains(sessionID.lowercased())
    }
}
