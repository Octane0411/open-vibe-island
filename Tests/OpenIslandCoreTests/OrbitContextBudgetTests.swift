import Foundation
import Testing
@testable import OpenIslandCore

struct OrbitContextBudgetTests {
    @Test
    func retainsHighestPrioritySegmentsWithinBudget() {
        let low = OrbitContextSegment(provenanceID: "session:low", kind: .tool, estimatedTokens: 40, priority: 1)
        let high = OrbitContextSegment(provenanceID: "session:high", kind: .user, estimatedTokens: 30, priority: 10)
        let report = OrbitContextBudgeter.assess(
            segments: [low, high],
            policy: OrbitContextBudgetPolicy(targetTokens: 35)
        )

        #expect(report.inputTokens == 70)
        #expect(report.retainedTokens == 30)
        #expect(report.retainedSegmentIDs == [high.id])
        #expect(report.omittedSegmentIDs == [low.id])
        #expect(report.decision == .needsCompaction)
    }

    @Test
    func marksSensitiveProvenanceWithoutStoringContent() {
        let segment = OrbitContextSegment(
            provenanceID: "receipt:abc123",
            kind: .receipt,
            estimatedTokens: 12,
            containsSensitiveData: true
        )
        let report = OrbitContextBudgeter.assess(
            segments: [segment],
            policy: OrbitContextBudgetPolicy(targetTokens: 100)
        )

        #expect(report.decision == .redactionRequired)
        #expect(report.redactedSegmentIDs == [segment.id])
    }

    @Test
    func reservesTokensFromTargetBudget() {
        let segment = OrbitContextSegment(
            provenanceID: "session:system",
            kind: .system,
            estimatedTokens: 80
        )
        let report = OrbitContextBudgeter.assess(
            segments: [segment],
            policy: OrbitContextBudgetPolicy(targetTokens: 100, reservedTokens: 30)
        )

        #expect(report.retainedTokens == 0)
        #expect(report.omittedTokens == 80)
        #expect(report.estimatedSavingsPercent == 100)
    }

    @Test
    func emptyInputIsWithinBudget() {
        let report = OrbitContextBudgeter.assess(
            segments: [],
            policy: OrbitContextBudgetPolicy(targetTokens: 100)
        )

        #expect(report.inputTokens == 0)
        #expect(report.omittedTokens == 0)
        #expect(report.decision == .withinBudget)
    }
}
