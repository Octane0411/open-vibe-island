import Foundation

public enum ContextWindowTable {
    public static let defaultWindow: Int = 200_000

    /// Returns the model's context window in tokens. Detects `[1m]` suffix
    /// for the 1M-context variant (e.g. `claude-opus-4-7[1m]`). Falls back
    /// to `defaultWindow` for unknown models or nil/empty input.
    public static func window(for model: String?) -> Int {
        guard let model, !model.isEmpty else { return defaultWindow }
        if model.hasSuffix("[1m]") { return 1_000_000 }
        return defaultWindow
    }
}

public struct ContextUsage: Equatable, Sendable {
    public var used: Int
    public var window: Int

    public init(used: Int, window: Int) {
        self.used = used
        self.window = window
    }

    public var percentUsed: Double {
        guard window > 0 else { return 0 }
        return min(100, Double(used) / Double(window) * 100)
    }

    public var percentLeft: Double {
        max(0, 100 - percentUsed)
    }
}

public enum ContextUsageReader {
    /// Parses a Claude transcript (JSONL) and returns the most recent
    /// assistant turn's context-usage snapshot. Returns nil if no
    /// assistant turn with a `usage` block exists. Malformed lines are
    /// skipped silently.
    public static func parse(transcriptData: Data) -> ContextUsage? {
        guard let text = String(data: transcriptData, encoding: .utf8) else {
            return nil
        }
        var latest: ContextUsage?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData),
                  let root = object as? [String: Any],
                  (root["type"] as? String) == "assistant",
                  let message = root["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else {
                continue
            }
            let input = (usage["input_tokens"] as? NSNumber)?.intValue ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? NSNumber)?.intValue ?? 0
            let used = input + cacheRead + cacheCreate
            let window = ContextWindowTable.window(for: message["model"] as? String)
            latest = ContextUsage(used: used, window: window)
        }
        return latest
    }
}
