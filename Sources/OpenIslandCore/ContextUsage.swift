import Foundation

public enum ContextWindowTable {
    /// Auto-compact threshold for the 200K context variant.
    public static let defaultWindow: Int = 160_000

    /// Auto-compact threshold for the 1M context variant.
    public static let oneMillionWindow: Int = 800_000

    /// Returns the auto-compact threshold for the given model. Detects the
    /// 1M variant in two ways:
    ///   1. Explicit `[1m]` suffix on the model identifier
    ///   2. `observedUsed > 200_000` — only possible on 1M (the 200K API
    ///      would have rejected the request)
    public static func window(for model: String?, observedUsed: Int = 0) -> Int {
        if let model, model.hasSuffix("[1m]") { return oneMillionWindow }
        if observedUsed > 200_000 { return oneMillionWindow }
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
            let window = ContextWindowTable.window(
                for: message["model"] as? String,
                observedUsed: used
            )
            latest = ContextUsage(used: used, window: window)
        }
        return latest
    }
}

extension ContextUsageReader {
    /// Maximum bytes to read from the tail of the transcript when looking
    /// for the last assistant-with-usage line. 64KB covers ~hundreds of
    /// turns; we extend to 256KB if no usage block is found.
    static let primaryTailBytes = 64 * 1024
    static let extendedTailBytes = 256 * 1024

    /// Reads the tail of the transcript file and returns the most recent
    /// context usage snapshot. Returns nil if the file is missing,
    /// unreadable, or contains no assistant-with-usage line in the
    /// extended tail window.
    public static func read(transcriptPath: String) -> ContextUsage? {
        if let usage = readTail(path: transcriptPath, bytes: primaryTailBytes) {
            return usage
        }
        return readTail(path: transcriptPath, bytes: extendedTailBytes)
    }

    private static func readTail(path: String, bytes: Int) -> ContextUsage? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        return parse(transcriptData: data)
    }
}
