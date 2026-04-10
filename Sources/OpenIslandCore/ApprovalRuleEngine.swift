import Foundation

/// A persistent allow/deny rule for tool calls.
public struct ApprovalRule: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var pattern: String
    public var action: RuleAction
    public var label: String
    public var addedAt: Date

    public enum RuleAction: String, Codable, Sendable {
        case allow
        case deny
    }

    public init(
        id: UUID = UUID(),
        pattern: String,
        action: RuleAction,
        label: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.pattern = pattern.lowercased()
        self.action = action
        self.label = label ?? pattern
        self.addedAt = addedAt
    }
}

/// Persistent rule engine for auto-approving or auto-denying tool calls.
/// Rules are checked before the built-in classifier. Deny wins over allow.
public final class ApprovalRuleEngine: Sendable {
    private let rulesURL: URL
    private let lock = NSLock()

    private struct RulesData: Codable {
        var rules: [ApprovalRule]
    }

    public static let shared = ApprovalRuleEngine()

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("OpenIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        rulesURL = supportDir.appendingPathComponent("rules.json")
    }

    // MARK: - Public API

    public func getRules() -> [ApprovalRule] {
        lock.withLock { load().rules }
    }

    public func addRule(pattern: String, action: ApprovalRule.RuleAction, label: String? = nil) -> Bool {
        lock.withLock {
            var data = load()
            let normalized = pattern.lowercased()
            // Prevent duplicates
            if data.rules.contains(where: { $0.pattern == normalized && $0.action == action }) {
                return false
            }
            data.rules.append(ApprovalRule(pattern: pattern, action: action, label: label))
            save(data)
            return true
        }
    }

    public func removeRule(id: UUID) -> Bool {
        lock.withLock {
            var data = load()
            let before = data.rules.count
            data.rules.removeAll { $0.id == id }
            if data.rules.count < before {
                save(data)
                return true
            }
            return false
        }
    }

    /// Check a Bash command against rules. Returns 'allow', 'deny', or nil (no match).
    public func matchBashCommand(_ command: String) -> ApprovalRule.RuleAction? {
        let rules = lock.withLock { load().rules }
        let normalized = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var bestDeny: ApprovalRule? = nil
        var bestAllow: ApprovalRule? = nil

        for rule in rules {
            let pat = rule.pattern
            // Full command prefix match
            if matchPrefix(normalized, pattern: pat) {
                if rule.action == .deny {
                    if bestDeny == nil || pat.count > bestDeny!.pattern.count { bestDeny = rule }
                } else {
                    if bestAllow == nil || pat.count > bestAllow!.pattern.count { bestAllow = rule }
                }
                continue
            }
            // Check individual segments of compound commands
            let segments = normalized.split(whereSeparator: { "&&||;|".contains($0) })
            for seg in segments {
                let trimmed = seg.trimmingCharacters(in: .whitespaces)
                if matchPrefix(trimmed, pattern: pat) {
                    if rule.action == .deny {
                        if bestDeny == nil || pat.count > bestDeny!.pattern.count { bestDeny = rule }
                    } else {
                        if bestAllow == nil || pat.count > bestAllow!.pattern.count { bestAllow = rule }
                    }
                    break
                }
            }
        }

        // Deny wins over allow
        if let bestDeny { return .deny }
        if let bestAllow { return .allow }
        return nil
    }

    /// Check a non-Bash tool name against rules. Returns 'allow', 'deny', or nil.
    public func matchToolName(_ toolName: String) -> ApprovalRule.RuleAction? {
        let rules = lock.withLock { load().rules }
        // Check deny first
        if rules.contains(where: { $0.action == .deny && $0.pattern == toolName }) { return .deny }
        if rules.contains(where: { $0.action == .allow && $0.pattern == toolName }) { return .allow }
        return nil
    }

    // MARK: - Private

    private func load() -> RulesData {
        guard let data = try? Data(contentsOf: rulesURL),
              let decoded = try? JSONDecoder().decode(RulesData.self, from: data) else {
            return RulesData(rules: [])
        }
        return decoded
    }

    private func save(_ data: RulesData) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(data) {
            try? encoded.write(to: rulesURL, options: .atomic)
        }
    }

    private func matchPrefix(_ command: String, pattern: String) -> Bool {
        command == pattern
            || command.hasPrefix(pattern + " ")
            || command.hasPrefix(pattern + "\t")
    }
}
