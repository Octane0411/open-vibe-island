import Foundation
import Testing
@testable import OpenIslandCore

/// Cold start is where the rollout transcript is the only witness available,
/// and where the old implementation did most of its damage — spawned threads
/// became sessions, archived desktop threads looked alive, and scraped context
/// became titles. These tests drive the whole pipeline from the fixture corpus
/// the way a launch would.
@Suite("Codex cold start")
struct CodexColdStartTests {
    private func corpusFixtures() -> [URL] {
        CodexFixtureCorpusTests.allFixtures()
    }

    @Test("restoring the corpus produces sessions only for real conversations")
    func coldStartSkipsSpawnedThreads() throws {
        let fixtures = corpusFixtures()
        try #require(!fixtures.isEmpty, "fixture corpus missing")

        let pipeline = CodexIngestionPipeline(mode: .live)
        var started = 0
        var subagentFixtures = 0

        for fixture in fixtures {
            let reading = pipeline.rollout.read(fileAt: fixture)
            if reading.isSubagent { subagentFixtures += 1 }

            for event in pipeline.ingest(rolloutFile: fixture) {
                if case .sessionStarted = event { started += 1 }
            }
        }

        // Roughly half of a real corpus is threads Codex spawned for itself.
        #expect(subagentFixtures > 0, "corpus has no spawned-thread samples")
        #expect(started > 0, "no sessions restored at all")
        #expect(
            started + subagentFixtures <= fixtures.count,
            "spawned threads leaked into the session list"
        )
    }

    @Test("cold-start values are provisional and yield to live sources")
    func coldStartValuesAreProvisional() throws {
        let fixtures = corpusFixtures()
        let userFixture = try #require(fixtures.first { url in
            let source = CodexRolloutSource()
            let reading = source.read(fileAt: url)
            return !reading.isSubagent && reading.meta != nil
        })

        let pipeline = CodexIngestionPipeline(mode: .live)
        _ = pipeline.ingest(rolloutFile: userFixture)

        let source = CodexRolloutSource()
        let sessionID = try #require(source.read(fileAt: userFixture).meta?.sessionID)
        let restored = try #require(pipeline.store.session(for: sessionID))
        #expect(restored.workspace?.isProvisional == true)

        // The first live source replaces whatever replay guessed.
        pipeline.store.enterLiveMode()
        pipeline.store.apply(
            CodexObservation(
                ref: .sessionID(sessionID),
                source: .hook,
                seq: 1,
                observedAt: .now,
                patch: CodexFacetPatch(
                    workspace: CodexWorkspace(workingDirectory: "/Users/dev/live")
                )
            ),
            sessionKey: sessionID
        )

        let updated = try #require(pipeline.store.session(for: sessionID))
        #expect(updated.workspace?.value.workingDirectory == "/Users/dev/live")
        #expect(updated.workspace?.isProvisional == false)
    }

    @Test("restoring the whole corpus twice is idempotent")
    func restoreIsIdempotent() throws {
        let fixtures = corpusFixtures()
        try #require(!fixtures.isEmpty)

        let pipeline = CodexIngestionPipeline(mode: .live)
        for fixture in fixtures { _ = pipeline.ingest(rolloutFile: fixture) }
        let afterFirst = pipeline.store.allSessions().count

        // A rescan must not duplicate or resurrect anything.
        var secondPassStarts = 0
        for fixture in fixtures {
            for event in pipeline.ingest(rolloutFile: fixture) {
                if case .sessionStarted = event { secondPassStarts += 1 }
            }
        }

        #expect(pipeline.store.allSessions().count == afterFirst)
        #expect(secondPassStarts == 0)
    }

    @Test("no restored session is left without a workspace")
    func restoredSessionsHaveWorkspaces() throws {
        let fixtures = corpusFixtures()
        try #require(!fixtures.isEmpty)

        let pipeline = CodexIngestionPipeline(mode: .live)
        for fixture in fixtures { _ = pipeline.ingest(rolloutFile: fixture) }

        for session in pipeline.store.allSessions() where session.isUserVisible {
            #expect(
                session.workspace != nil,
                "session \(session.sessionKey) restored without a workspace"
            )
        }
    }
}
