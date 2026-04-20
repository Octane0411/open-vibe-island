import Foundation

public enum CursorTranscriptReader {
    /// Extracts the initial user prompt from a Cursor agent transcript JSONL file.
    /// Reads only the first few KB of the file for efficiency.
    public static func initialUserPrompt(at path: String, limit: Int = 200) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        let data = handle.readData(ofLength: 32_768)
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return nil }

        guard let newlineIndex = text.firstIndex(of: "\n") else {
            return extractPrompt(from: text, limit: limit)
        }

        return extractPrompt(from: String(text[..<newlineIndex]), limit: limit)
    }

    private static func extractPrompt(from jsonLine: String, limit: Int) -> String? {
        guard let lineData = jsonLine.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              entry["role"] as? String == "user",
              let message = entry["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return nil
        }

        for block in content {
            guard block["type"] as? String == "text",
                  let rawText = block["text"] as? String,
                  !rawText.isEmpty else { continue }

            if let prompt = extractUserQuery(from: rawText) {
                return clipped(prompt, limit: limit)
            }

            return clipped(rawText, limit: limit)
        }

        return nil
    }

    /// Extracts the user's actual query from system-injected content.
    /// Cursor wraps user queries in `<user_query>` tags when system context is present.
    private static func extractUserQuery(from text: String) -> String? {
        guard let startRange = text.range(of: "<user_query>"),
              let endRange = text.range(of: "</user_query>") else {
            return nil
        }

        let query = text[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    private static func clipped(_ value: String, limit: Int) -> String? {
        let collapsed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > limit else { return collapsed }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit - 1)
        return "\(collapsed[..<endIndex])\u{2026}"
    }
}
