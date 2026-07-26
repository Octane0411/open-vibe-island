import Foundation

/// A bounded, metadata-only description of context that Orbit may inspect.
/// It intentionally carries no prompt, transcript, command, or file contents.
public struct OrbitContextSegment: Codable, Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
        case receipt
    }

    public let id: UUID
    public let provenanceID: String
    public let kind: Kind
    public let estimatedTokens: Int
    public let priority: Int
    public let containsSensitiveData: Bool

    public init(
        id: UUID = UUID(),
        provenanceID: String,
        kind: Kind,
        estimatedTokens: Int,
        priority: Int = 0,
        containsSensitiveData: Bool = false
    ) {
        self.id = id
        self.provenanceID = provenanceID
        self.kind = kind
        self.estimatedTokens = max(0, estimatedTokens)
        self.priority = priority
        self.containsSensitiveData = containsSensitiveData
    }
}

public struct OrbitContextBudgetPolicy: Codable, Equatable, Sendable {
    public let targetTokens: Int
    public let reservedTokens: Int
    public let requireRedaction: Bool

    public init(targetTokens: Int, reservedTokens: Int = 0, requireRedaction: Bool = true) {
        self.targetTokens = max(0, targetTokens)
        self.reservedTokens = max(0, reservedTokens)
        self.requireRedaction = requireRedaction
    }

    public var usableTokens: Int {
        max(0, targetTokens - reservedTokens)
    }
}

public struct OrbitContextBudgetReport: Codable, Equatable, Sendable {
    public enum Decision: String, Codable, Sendable {
        case withinBudget
        case needsCompaction
        case redactionRequired
    }

    public let inputTokens: Int
    public let retainedTokens: Int
    public let omittedTokens: Int
    public let retainedSegmentIDs: [UUID]
    public let omittedSegmentIDs: [UUID]
    public let redactedSegmentIDs: [UUID]
    public let decision: Decision

    public var estimatedSavingsPercent: Double {
        guard inputTokens > 0 else { return 0 }
        return (Double(omittedTokens) / Double(inputTokens)) * 100
    }
}

/// Deterministic local assessment only. It never rewrites provider state and
/// never returns segment contents. A later summarizer can consume this report
/// through an explicit, separately approved interface.
public enum OrbitContextBudgeter {
    public static func assess(
        segments: [OrbitContextSegment],
        policy: OrbitContextBudgetPolicy
    ) -> OrbitContextBudgetReport {
        let inputTokens = segments.reduce(0) { $0 + $1.estimatedTokens }
        let redactedIDs = policy.requireRedaction
            ? segments.filter(\.containsSensitiveData).map(\.id)
            : []
        let budget = policy.usableTokens
        let ordered = segments.enumerated().sorted {
            if $0.element.priority != $1.element.priority {
                return $0.element.priority > $1.element.priority
            }
            return $0.offset < $1.offset
        }

        var retainedTokens = 0
        var retainedIDs: [UUID] = []
        var omittedIDs: [UUID] = []
        for item in ordered {
            if retainedTokens + item.element.estimatedTokens <= budget {
                retainedTokens += item.element.estimatedTokens
                retainedIDs.append(item.element.id)
            } else {
                omittedIDs.append(item.element.id)
            }
        }

        let decision: OrbitContextBudgetReport.Decision
        if !redactedIDs.isEmpty {
            decision = .redactionRequired
        } else if inputTokens > budget {
            decision = .needsCompaction
        } else {
            decision = .withinBudget
        }

        return OrbitContextBudgetReport(
            inputTokens: inputTokens,
            retainedTokens: retainedTokens,
            omittedTokens: max(0, inputTokens - retainedTokens),
            retainedSegmentIDs: retainedIDs,
            omittedSegmentIDs: omittedIDs,
            redactedSegmentIDs: redactedIDs,
            decision: decision
        )
    }
}
