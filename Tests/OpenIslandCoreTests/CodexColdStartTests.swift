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

    /// One cold-start restore of the whole corpus, shared by the tests below.
    ///
    /// Restoring per test meant decoding the corpus several times over; that
    /// much parallel work was enough to disturb latency-sensitive tests
    /// elsewhere in the run.
    struct Restore: Sendable {
        var pipeline: CodexIngestionPipeline
        var started: Int
        var subagentFixtures: Int
        var fixtureCount: Int
        var secondPassStarts: Int
        var sessionsAfterFirst: Int
    }

    static let restore: Restore = {
        let pipeline = CodexIngestionPipeline(mode: .live)
        var started = 0
        var subagent = 0

        func pass() -> Int {
            var count = 0
            for (url, lines) in CodexFixtureCorpusTests.cachedLines {
                let reading = pipeline.rollout.read(lines: lines, transcriptPath: url.path)
                guard let observation = reading.observation, !reading.isSubagent else { continue }
                for event in pipeline.projector.project(observation) {
                    if case .sessionStarted = event { count += 1 }
                }
            }
            return count
        }

        for (url, lines) in CodexFixtureCorpusTests.cachedLines {
            if pipeline.rollout.read(lines: lines, transcriptPath: url.path).isSubagent {
                subagent += 1
            }
        }
        started = pass()
        let afterFirst = pipeline.store.allSessions().count
        let second = pass()

        return Restore(
            pipeline: pipeline,
            started: started,
            subagentFixtures: subagent,
            fixtureCount: CodexFixtureCorpusTests.cachedLines.count,
            secondPassStarts: second,
            sessionsAfterFirst: afterFirst
        )
    }()

    @Test("restoring the corpus produces sessions only for real conversations")
    func coldStartSkipsSpawnedThreads() {
        let restore = Self.restore
        // Roughly half of a real corpus is threads Codex spawned for itself.
        #expect(restore.subagentFixtures > 0, "corpus has no spawned-thread samples")
        #expect(restore.started > 0, "no sessions restored at all")
        #expect(
            restore.started + restore.subagentFixtures <= restore.fixtureCount,
            "spawned threads leaked into the session list"
        )
    }

    @Test("restoring the whole corpus twice is idempotent")
    func restoreIsIdempotent() {
        let restore = Self.restore
        // A rescan must not duplicate or resurrect anything.
        #expect(restore.pipeline.store.allSessions().count == restore.sessionsAfterFirst)
        #expect(restore.secondPassStarts == 0)
    }

    @Test("no restored session is left without a workspace")
    func restoredSessionsHaveWorkspaces() {
        for session in Self.restore.pipeline.store.allSessions() where session.isUserVisible {
            #expect(
                session.workspace != nil,
                "session \(session.sessionKey) restored without a workspace"
            )
        }
    }

    @Test("cold-start values are provisional and yield to live sources")
    func coldStartValuesAreProvisional() throws {
        // A small hand-built transcript keeps this independent of the corpus.
        let lines = [
            #"{"type":"session_meta","timestamp":"2026-08-24T00:00:00Z","payload":{"id":"aaaa","cwd":"/Users/dev/work/island","originator":"codex-tui","cli_version":"9.9.9","source":"cli"}}"#
        ]
        let pipeline = CodexIngestionPipeline(mode: .live)
        let reading = pipeline.rollout.read(lines: lines, transcriptPath: "/tmp/x.jsonl")
        let observation = try #require(reading.observation)
        _ = pipeline.projector.project(observation)

        let restored = try #require(pipeline.store.session(for: "aaaa"))
        #expect(restored.workspace?.isProvisional == true)

        // The first live source replaces whatever replay guessed.
        pipeline.store.enterLiveMode()
        pipeline.store.apply(
            CodexObservation(
                ref: .sessionID("aaaa"),
                source: .hook,
                seq: 1,
                observedAt: .now,
                patch: CodexFacetPatch(
                    workspace: CodexWorkspace(workingDirectory: "/Users/dev/live")
                )
            ),
            sessionKey: "aaaa"
        )

        let updated = try #require(pipeline.store.session(for: "aaaa"))
        #expect(updated.workspace?.value.workingDirectory == "/Users/dev/live")
        #expect(updated.workspace?.isProvisional == false)
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

}
