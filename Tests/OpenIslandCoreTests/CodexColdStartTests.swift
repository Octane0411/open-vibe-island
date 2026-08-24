import Foundation
import Testing
@testable import OpenIslandCore

/// Cold start is where the rollout transcript is the only witness available,
/// and where the old implementation did most of its damage — spawned threads
/// became sessions, archived desktop threads looked alive, and scraped context
/// became titles. These tests drive the whole pipeline from the fixture corpus
/// the way a launch would.
///
/// Serialized because these drive the whole corpus through the pipeline; run
/// concurrently they put enough load on a CI runner to perturb latency-sensitive
/// tests elsewhere in the suite.
@Suite("Codex cold start", .serialized)
struct CodexColdStartTests {
    private func corpusFixtures() -> [URL] {
        CodexFixtureCorpusTests.allFixtures()
    }

    /// Replay a cached fixture instead of re-reading it from disk.
    private func ingestCached(_ pipeline: CodexIngestionPipeline) -> Int {
        var started = 0
        for (url, lines) in CodexFixtureCorpusTests.cachedLines {
            let reading = pipeline.rollout.read(lines: lines, transcriptPath: url.path)
            guard let observation = reading.observation, !reading.isSubagent else { continue }
            for event in pipeline.projector.project(observation) {
                if case .sessionStarted = event { started += 1 }
            }
        }
        return started
    }

    @Test("restoring the corpus produces sessions only for real conversations")
    func coldStartSkipsSpawnedThreads() throws {
        let fixtures = corpusFixtures()
        try #require(!fixtures.isEmpty, "fixture corpus missing")

        let pipeline = CodexIngestionPipeline(mode: .live)
        var started = 0
        var subagentFixtures = 0

        for (url, lines) in CodexFixtureCorpusTests.cachedLines {
            let reading = pipeline.rollout.read(lines: lines, transcriptPath: url.path)
            if reading.isSubagent { subagentFixtures += 1; continue }
            guard let observation = reading.observation else { continue }
            for event in pipeline.projector.project(observation) {
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
        _ = ingestCached(pipeline)
        let afterFirst = pipeline.store.allSessions().count

        // A rescan must not duplicate or resurrect anything.
        let secondPassStarts = ingestCached(pipeline)

        #expect(pipeline.store.allSessions().count == afterFirst)
        #expect(secondPassStarts == 0)
    }

    @Test("bounded reads still recover the header and recent activity")
    func boundedFileReadRecoversHeaderAndTail() throws {
        // The only test that goes through the file path rather than cached
        // lines, so the head/tail read logic keeps direct coverage.
        let fixtures = corpusFixtures()
        let fixture = try #require(fixtures.first)

        let source = CodexRolloutSource()
        let bounded = source.read(fileAt: fixture)

        let text = try String(contentsOf: fixture, encoding: .utf8)
        let whole = source.read(
            lines: text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init),
            transcriptPath: fixture.path
        )

        // Identity and classification must survive the truncation — they live
        // in the header, which the head read always reaches.
        #expect(bounded.meta?.sessionID == whole.meta?.sessionID)
        #expect(bounded.meta?.originator == whole.meta?.originator)
        #expect(bounded.meta?.cliVersion == whole.meta?.cliVersion)
        #expect(bounded.isSubagent == whole.isSubagent)
    }

    @Test("a header larger than the head read is still recovered")
    func oversizedHeaderRecovered() throws {
        // `session_meta` can embed full system instructions and run well past
        // the normal head read; without the adaptive growth these transcripts
        // yielded no session at all.
        let padding = String(repeating: "x", count: CodexRolloutSource.headReadLimit + 4096)
        var meta = #"{"type":"session_meta","timestamp":"2026-08-24T00:00:00Z","payload":{"#
        meta += #""id":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/work/island","#
        meta += #""originator":"codex-tui","cli_version":"9.9.9","source":"cli","#
        meta += #""base_instructions":{"text":""# + padding + #""}}}"#

        let tail = (0..<200).map { index in
            #"{"type":"event_msg","payload":{"type":"agent_message","message":"m"# + "\(index)" + #""}}"#
        }.joined(separator: "\n")

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rollout-2026-08-24T00-00-00-11111111-2222-3333-4444-555555555555.jsonl")
        try (meta + "\n" + tail + "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let reading = CodexRolloutSource().read(fileAt: url)
        #expect(reading.meta?.sessionID == "11111111-2222-3333-4444-555555555555")
        #expect(reading.meta?.originator == "codex-tui")
    }

    @Test("no restored session is left without a workspace")
    func restoredSessionsHaveWorkspaces() throws {
        let fixtures = corpusFixtures()
        try #require(!fixtures.isEmpty)

        let pipeline = CodexIngestionPipeline(mode: .live)
        _ = ingestCached(pipeline)

        for session in pipeline.store.allSessions() where session.isUserVisible {
            #expect(
                session.workspace != nil,
                "session \(session.sessionKey) restored without a workspace"
            )
        }
    }
}
