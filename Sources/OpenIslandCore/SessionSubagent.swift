import Foundation

/// A child row inside a conversation. Children never contribute to root counts.
public struct SessionSubagent: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let role: String?
    public let task: String?
    public let phase: SessionPhase
    public let startedAt: Date?
    public let depth: Int
    public let model: String?
    public let reasoningEffort: String?

    public init(id: String, name: String, role: String? = nil, task: String? = nil,
                phase: SessionPhase, startedAt: Date? = nil, depth: Int = 1,
                model: String? = nil, reasoningEffort: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.task = task
        self.phase = phase
        self.startedAt = startedAt
        self.depth = depth
        self.model = model
        self.reasoningEffort = reasoningEffort
    }

    /// Attention remains visible even when ordinary child details are hidden.
    public static func visible(_ children: [Self], showDetails: Bool) -> [Self] {
        showDetails ? children : children.filter { $0.phase.requiresAttention }
    }
}

public extension CodexLiveSessionPolicy {
    /// Follow explicit parent IDs, never workspace names. Reject cycles and
    /// orphans rather than attaching them to an unrelated conversation.
    static func subagentsByRoot(
        _ threads: [CodexThread], rootIDs: Set<String>, now: Date = .now,
        lastActiveAt: [String: Date] = [:], completedWindow: TimeInterval = 300
    ) -> [String: [SessionSubagent]] {
        let byID = Dictionary(threads.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var result: [String: [SessionSubagent]] = [:]
        for child in threads {
            guard !child.ephemeral, let parentID = child.subagentParentID else { continue }
            switch child.status.type {
            case .active: break
            case .idle, .systemError:
                let activity = max(Double(child.updatedAt), lastActiveAt[child.id]?.timeIntervalSince1970 ?? 0)
                guard now.timeIntervalSince1970 - activity <= completedWindow else { continue }
            case .notLoaded: continue
            }
            var ancestor = parentID
            var visited: Set<String> = [child.id]
            var depth = 1
            while !rootIDs.contains(ancestor), visited.insert(ancestor).inserted,
                  let parent = byID[ancestor]?.subagentParentID {
                ancestor = parent
                depth += 1
            }
            guard rootIDs.contains(ancestor), !visited.contains(ancestor) else { continue }
            let name = (child.agentNickname ?? child.source?.subagentInfo?.nickname).flatMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let task = CodexRolloutReducer.userVisiblePromptSegment(from: child.preview)
            result[ancestor, default: []].append(SessionSubagent(
                id: child.id, name: name ?? String(child.id.prefix(8)),
                role: child.agentRole ?? child.source?.subagentInfo?.role, task: task.map { String($0.prefix(160)) },
                phase: phase(for: child.status), startedAt: Date(timeIntervalSince1970: Double(child.createdAt)),
                depth: depth, model: child.model, reasoningEffort: child.reasoningEffort
            ))
        }
        for root in result.keys {
            // Keep a stable tree order while siblings change state.
            result[root]?.sort {
                if $0.depth != $1.depth { return $0.depth < $1.depth }
                return $0.id < $1.id
            }
        }
        return result
    }
}
