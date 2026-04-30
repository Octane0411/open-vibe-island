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
