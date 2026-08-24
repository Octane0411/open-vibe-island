import Foundation
import Testing
@testable import OpenIslandCore

@Suite("Codex facet store")
struct CodexFacetStoreTests {
    private func observation(
        source: CodexSource,
        seq: UInt64,
        patch: CodexFacetPatch,
        sessionID: String = "S1",
        at seconds: TimeInterval = 0
    ) -> CodexObservation {
        CodexObservation(
            ref: .sessionID(sessionID),
            source: source,
            seq: seq,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000 + seconds),
            patch: patch
        )
    }

    @Test("a source writing a facet it has no authority over is rejected")
    func unauthorizedWriteRejected() {
        let store = CodexFacetStore()
        store.enterLiveMode()

        let change = store.apply(
            observation(source: .rollout, seq: 1, patch: CodexFacetPatch(
                lifecycle: CodexLifecycle(phase: .completed)
            )),
            sessionKey: "S1"
        )

        #expect(change.rejected.contains(.lifecycle))
        #expect(!change.accepted.contains(.lifecycle))
        #expect(store.session(for: "S1")?.lifecycle == nil)
    }

    @Test("the app-server thread name survives a later transcript scrape")
    func appServerTitleNotOverwrittenByRollout() {
        let store = CodexFacetStore()
        store.enterLiveMode()

        store.apply(
            observation(source: .appServer, seq: 1, patch: CodexFacetPatch(
                narrative: CodexNarrative(title: "Ship the release")
            )),
            sessionKey: "S1"
        )
        store.apply(
            observation(source: .rollout, seq: 99, patch: CodexFacetPatch(
                narrative: CodexNarrative(title: "<injected context blob>")
            )),
            sessionKey: "S1"
        )

        #expect(store.session(for: "S1")?.narrative?.value.title == "Ship the release")
    }

    @Test("narrative fragments merge instead of erasing each other")
    func narrativeMerges() {
        let store = CodexFacetStore()
        store.enterLiveMode()

        store.apply(
            observation(source: .rollout, seq: 1, patch: CodexFacetPatch(
                narrative: CodexNarrative(initialUserPrompt: "first ask")
            )),
            sessionKey: "S1"
        )
        store.apply(
            observation(source: .rollout, seq: 2, patch: CodexFacetPatch(
                narrative: CodexNarrative(currentTool: "shell")
            )),
            sessionKey: "S1"
        )

        let narrative = store.session(for: "S1")?.narrative?.value
        #expect(narrative?.initialUserPrompt == "first ask")
        #expect(narrative?.currentTool == "shell")
    }

    @Test("out-of-order delivery from one source cannot rewind state")
    func lateArrivalIgnored() {
        let store = CodexFacetStore()
        store.enterLiveMode()

        store.apply(
            observation(source: .appServer, seq: 10, patch: CodexFacetPatch(
                lifecycle: CodexLifecycle(phase: .completed)
            )),
            sessionKey: "S1"
        )
        store.apply(
            observation(source: .appServer, seq: 2, patch: CodexFacetPatch(
                lifecycle: CodexLifecycle(phase: .running)
            )),
            sessionKey: "S1"
        )

        #expect(store.session(for: "S1")?.lifecycle?.value.phase == .completed)
    }

    @Test("cold-start replay lets the transcript fill every facet provisionally")
    func replayModeAllowsRolloutEverywhere() {
        let store = CodexFacetStore()   // starts in .replaying

        let change = store.apply(
            observation(source: .rollout, seq: 1, patch: CodexFacetPatch(
                lifecycle: CodexLifecycle(phase: .running),
                liveness: CodexLiveness(state: .alive)
            )),
            sessionKey: "S1"
        )

        #expect(change.accepted.contains(.lifecycle))
        #expect(store.session(for: "S1")?.lifecycle?.isProvisional == true)
    }

    @Test("the first authoritative write replaces a provisional value")
    func authoritativeWriteReplacesProvisional() {
        let store = CodexFacetStore()
        store.apply(
            observation(source: .rollout, seq: 50, patch: CodexFacetPatch(
                lifecycle: CodexLifecycle(phase: .running)
            )),
            sessionKey: "S1"
        )
        store.enterLiveMode()

        store.apply(
            observation(source: .appServer, seq: 1, patch: CodexFacetPatch(
                lifecycle: CodexLifecycle(phase: .completed)
            )),
            sessionKey: "S1"
        )

        let slot = store.session(for: "S1")?.lifecycle
        #expect(slot?.value.phase == .completed)
        #expect(slot?.isProvisional == false)
    }

    @Test("rejected writes are counted for the diagnostics pane")
    func rejectionsAreCounted() {
        let diagnostics = CodexDiagnostics()
        let store = CodexFacetStore(diagnostics: diagnostics)
        store.enterLiveMode()

        store.apply(
            observation(source: .rollout, seq: 1, patch: CodexFacetPatch(
                liveness: CodexLiveness(state: .ended(reason: .archived))
            )),
            sessionKey: "S1"
        )

        let snapshot = diagnostics.snapshot()
        #expect(!snapshot.rejectedWrites.isEmpty)
        #expect(snapshot.summaryLines.contains { $0.contains("liveness") })
    }

    @Test("applying the same observations in any order reaches the same state")
    func orderIndependence() {
        let patches: [(CodexSource, UInt64, CodexFacetPatch)] = [
            (.appServer, 3, CodexFacetPatch(lifecycle: CodexLifecycle(phase: .completed))),
            (.hook, 1, CodexFacetPatch(placement: CodexPlacement(terminalApp: "Ghostty"))),
            (.rollout, 2, CodexFacetPatch(surface: .cli)),
            (.appServer, 1, CodexFacetPatch(narrative: CodexNarrative(title: "T"))),
        ]

        func finalState(_ order: [Int]) -> CodexSessionFacets? {
            let store = CodexFacetStore()
            store.enterLiveMode()
            for index in order {
                let (source, seq, patch) = patches[index]
                store.apply(observation(source: source, seq: seq, patch: patch), sessionKey: "S1")
            }
            return store.session(for: "S1")
        }

        let forward = finalState([0, 1, 2, 3])
        let reversed = finalState([3, 2, 1, 0])
        let shuffled = finalState([2, 0, 3, 1])

        #expect(forward?.lifecycle?.value == reversed?.lifecycle?.value)
        #expect(forward?.lifecycle?.value == shuffled?.lifecycle?.value)
        #expect(forward?.placement?.value == shuffled?.placement?.value)
        #expect(forward?.surface?.value == shuffled?.surface?.value)
        #expect(forward?.narrative?.value.title == shuffled?.narrative?.value.title)
    }
}
