import Foundation
import Testing
@testable import OpenIslandCore

/// The authority matrix is the arbitration rule for the whole Codex ingestion
/// layer, so its invariants are asserted directly rather than inferred from
/// higher-level behaviour.
@Suite("Codex authority matrix")
struct CodexAuthorityMatrixTests {
    @Test("hooks outrank the app-server for approvals; nothing else may raise one")
    func actionableAuthority() {
        #expect(CodexAuthorityMatrix.writers(for: .actionable) == [.hook, .appServer])
        #expect(!CodexAuthorityMatrix.canWrite(.rollout, .actionable))
        #expect(!CodexAuthorityMatrix.canWrite(.process, .actionable))
    }

    @Test("terminal placement may only come from hooks and process observation")
    func placementExcludesAppServerAndRollout() {
        #expect(!CodexAuthorityMatrix.canWrite(.appServer, .placement))
        #expect(!CodexAuthorityMatrix.canWrite(.rollout, .placement))
        #expect(CodexAuthorityMatrix.canWrite(.hook, .placement))
    }

    @Test("the rollout transcript may not decide liveness or run phase")
    func rolloutCannotDecideLifecycleOrLiveness() {
        // A vanished rollout file means the session was archived, not that it
        // ended — treating it as an end signal is what stranded Codex.app rows
        // in a permanently running state.
        #expect(!CodexAuthorityMatrix.canWrite(.rollout, .liveness))
        #expect(!CodexAuthorityMatrix.canWrite(.rollout, .lifecycle))
    }

    @Test("the rollout transcript is authoritative for surface classification")
    func rolloutOwnsSurface() {
        #expect(CodexAuthorityMatrix.rank(of: .rollout, for: .surface) == 0)
        #expect(CodexAuthorityMatrix.rank(of: .appServer, for: .surface) == 1)
        #expect(!CodexAuthorityMatrix.canWrite(.hook, .surface))
    }

    @Test("a stronger source overrides a weaker one regardless of arrival order")
    func strongerSourceWins() {
        // rollout holds narrative, app-server (stronger) arrives later with a
        // lower sequence number — it must still win.
        #expect(CodexAuthorityMatrix.shouldAccept(
            incoming: .appServer,
            incomingSeq: 1,
            heldBy: .rollout,
            heldSeq: 999,
            heldIsProvisional: false,
            facet: .narrative
        ))
    }

    @Test("a weaker source never overrides a stronger one")
    func weakerSourceRejected() {
        #expect(!CodexAuthorityMatrix.shouldAccept(
            incoming: .rollout,
            incomingSeq: 999,
            heldBy: .appServer,
            heldSeq: 1,
            heldIsProvisional: false,
            facet: .narrative
        ))
    }

    @Test("between equal sources the newer sequence wins")
    func equalSourcesOrderBySequence() {
        #expect(CodexAuthorityMatrix.shouldAccept(
            incoming: .hook, incomingSeq: 5, heldBy: .hook, heldSeq: 4,
            heldIsProvisional: false, facet: .placement
        ))
        #expect(!CodexAuthorityMatrix.shouldAccept(
            incoming: .hook, incomingSeq: 3, heldBy: .hook, heldSeq: 4,
            heldIsProvisional: false, facet: .placement
        ))
    }

    @Test("provisional cold-start values yield to any authoritative write")
    func provisionalYieldsToAnyAuthority() {
        #expect(CodexAuthorityMatrix.shouldAccept(
            incoming: .hook,
            incomingSeq: 0,
            heldBy: .appServer,
            heldSeq: 999,
            heldIsProvisional: true,
            facet: .lifecycle
        ))
    }

    @Test("an unauthorized source is rejected even against an empty slot")
    func unauthorizedRejectedEvenWhenUnset() {
        #expect(!CodexAuthorityMatrix.shouldAccept(
            incoming: .rollout,
            incomingSeq: 1,
            heldBy: nil,
            heldSeq: 0,
            heldIsProvisional: false,
            facet: .actionable
        ))
    }

    @Test("the app-server may name a desktop session's workspace")
    func appServerWritesWorkspace() {
        // Without this, every Codex.app session would fall back to the app
        // name for its workspace — the desktop path has no hook to supply it.
        #expect(CodexAuthorityMatrix.canWrite(.appServer, .workspace))
        #expect(CodexAuthorityMatrix.rank(of: .rollout, for: .workspace) == 0)
    }

    @Test("every facet has at least one authorized writer")
    func everyFacetIsWritable() {
        for facet in CodexFacet.allCases {
            #expect(!CodexAuthorityMatrix.writers(for: facet).isEmpty, "\(facet) has no writer")
        }
    }
}
