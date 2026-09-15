import Foundation

/// Guardian review rollouts are internal Codex work, not conversations. Match
/// explicit metadata rather than the word "compact", which is valid user work.
public enum CodexInternalSessionFilter {
    static func isInternalReview(metadata: [String: Any]) -> Bool {
        if metadata["thread_source"] as? String == "guardian_review" { return true }
        let source = metadata["source"] as? [String: Any]
        let subagent = source?["subagent"] as? [String: Any]
        return subagent?["other"] as? String == "guardian"
    }

    public static func isInternalReview(transcriptPath: String?) -> Bool {
        guard let transcriptPath,
              let handle = FileHandle(forReadingAtPath: transcriptPath) else { return false }
        defer { try? handle.close() }
        // session_meta is the first record. Bound reads even for large histories;
        // missing, incomplete or unfamiliar metadata must preserve the session.
        guard let data = try? handle.read(upToCount: 256 * 1_024),
              let line = data.split(separator: 10, maxSplits: 1).first,
              let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any] else { return false }
        return isInternalReview(metadata: payload)
    }
}
