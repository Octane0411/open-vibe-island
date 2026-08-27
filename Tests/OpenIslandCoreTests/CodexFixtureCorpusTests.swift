import Foundation
import Testing
@testable import OpenIslandCore

/// Regression coverage driven by anonymized transcripts captured from a real
/// Codex corpus, one directory per `cli_version` plus two edge buckets.
///
/// The point of testing against real files rather than hand-written samples is
/// that the failures this refactor exists to fix were all shape surprises —
/// a field that turned out to be polymorphic, a record type nobody had seen, a
/// client that renamed itself. Synthetic fixtures reproduce only the shapes
/// their author already knew about.
///
/// The corpus is read and decoded exactly once for the whole test run. Walking
/// it per test put enough parallel CPU and disk load on CI to perturb
/// latency-sensitive tests elsewhere in the suite, so every assertion below
/// reads from `analysis` instead.
///
/// The fixtures are generated from the maintainer's own session history and
/// are deliberately not committed — they are ignored by git and exist only on
/// machines where `scripts/codex-fixtures.py` has been run. The whole suite is
/// skipped, not failed, when they are absent, so CI stays green without them
/// and local runs get the extra coverage.
/// Whether the locally generated corpus exists. Lives outside the suite because
/// a `@Suite` trait cannot reference a member of the type it decorates — the
/// macro expansion becomes circular.
func codexCorpusIsAvailable() -> Bool {
    !CodexFixtureCorpusTests.allFixtures().isEmpty
}

@Suite("Codex fixture corpus", .enabled(if: codexCorpusIsAvailable()))
struct CodexFixtureCorpusTests {

    // MARK: - Corpus location

    static let corpusRoot: URL? = {
        // Tests run from the build directory, so walk up to the package root.
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            directory.deleteLastPathComponent()
            let candidate = directory
                .appendingPathComponent("Tests/Fixtures/codex-rollouts", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }()

    static func versionDirectories() -> [URL] {
        guard let root = corpusRoot else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return contents.filter { $0.hasDirectoryPath }.sorted { $0.path < $1.path }
    }

    static func fixtures(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "jsonl" }.sorted { $0.path < $1.path }
    }

    static func allFixtures() -> [URL] {
        versionDirectories().flatMap(fixtures(in:))
    }

    /// Fixture contents, read from disk once.
    static let cachedLines: [(url: URL, lines: [String])] = {
        allFixtures().map { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return (url, text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        }
    }()

    // MARK: - Single decode pass

    struct Analysis: Sendable {
        var fixtureCount = 0
        var directoryCount = 0
        var decodedHeaders = 0
        var subagentCount = 0
        var desktopCount = 0
        var misclassifiedDesktop: [String] = []
        var missingHeaders: [String] = []
        var unknownRecords: [CodexDiagnostics.UnknownRecord: Int] = [:]
        var unknownOriginators: [String: Int] = [:]
        var subagentEventLeaks: [String] = []
    }

    /// Decode the whole corpus once and record everything the tests assert on.
    ///
    /// Async, and yielding between fixtures, on purpose. Swift Testing runs
    /// tests on the cooperative thread pool, and decoding the corpus is
    /// synchronous CPU work — run straight through, it monopolizes those
    /// threads. `CodexAppServerClient` implements its request timeout as a Task
    /// awaiting `Task.sleep`, so a starved pool delays that sleep and makes an
    /// unrelated timeout test fail on runners with few cores. Yielding keeps the
    /// pool responsive without giving up any corpus coverage.
    private static let cache = AnalysisCache()

    static func analysis() async -> Analysis {
        await cache.value()
    }

    actor AnalysisCache {
        private var stored: Analysis?

        func value() async -> Analysis {
            if let stored { return stored }
            let computed = await Self.compute()
            stored = computed
            return computed
        }

        private static func compute() async -> Analysis {
            var result = Analysis()
            result.directoryCount = versionDirectories().count
            result.fixtureCount = cachedLines.count

            let diagnostics = CodexDiagnostics()
            let source = CodexRolloutSource(diagnostics: diagnostics)
            let store = CodexFacetStore()
            let projector = CodexSessionProjector(store: store)

            for (url, lines) in cachedLines {
                // Hand the pool back between files so concurrent async tests
                // keep making progress.
                await Task.yield()
                let reading = source.read(lines: lines, transcriptPath: url.path)
                guard let meta = reading.meta else {
                    result.missingHeaders.append(url.lastPathComponent)
                    continue
                }
                result.decodedHeaders += 1

                if reading.isSubagent {
                    result.subagentCount += 1
                    // A spawned thread must produce no session events at all.
                    if let observation = reading.observation,
                       !projector.project(observation).isEmpty {
                        result.subagentEventLeaks.append(url.lastPathComponent)
                    }
                    continue
                }

                guard let originator = meta.originator else { continue }
                if CodexIdentityResolver.desktopOriginators.contains(originator) {
                    let surface = CodexIdentityResolver.surface(
                        originator: originator,
                        source: meta.source,
                        threadSource: meta.threadSource,
                        parentThreadID: meta.parentThreadID
                    )
                    if surface == .desktopApp {
                        result.desktopCount += 1
                    } else {
                        result.misclassifiedDesktop.append("\(originator) in \(url.lastPathComponent)")
                    }
                }
            }

            let snapshot = diagnostics.snapshot()
            result.unknownRecords = snapshot.unknownRecords
            result.unknownOriginators = snapshot.unknownOriginators
            return result
        }
    }

    // MARK: - Assertions

    @Test("the corpus spans many Codex versions")
    func corpusIsPopulated() async {
        let analysis = await Self.analysis()
        // A single machine accumulates transcripts from many releases at once;
        // the corpus has to reflect that or it proves nothing about drift.
        #expect(analysis.directoryCount >= 10)
    }

    @Test("every fixture yields a session header the decoder understands")
    func everyFixtureDecodesItsHeader() async {
        let analysis = await Self.analysis()
        #expect(analysis.missingHeaders.isEmpty, "no session_meta in: \(analysis.missingHeaders)")
        #expect(analysis.decodedHeaders == analysis.fixtureCount)
    }

    @Test("spawned subagent transcripts never become user sessions")
    func subagentFixturesAreNotSessions() async {
        let analysis = await Self.analysis()
        // Roughly half of a real corpus is threads Codex spawned for itself.
        #expect(analysis.subagentCount > 0, "no spawned-thread samples captured")
        #expect(analysis.subagentEventLeaks.isEmpty, "leaked: \(analysis.subagentEventLeaks)")
    }

    @Test("desktop transcripts classify as Codex.app across both originator spellings")
    func desktopFixturesClassify() async {
        let analysis = await Self.analysis()
        #expect(analysis.misclassifiedDesktop.isEmpty, "\(analysis.misclassifiedDesktop)")
        #expect(analysis.desktopCount > 0, "corpus contains no desktop transcripts to verify")
    }

    @Test("no fixture reports an unknown originator")
    func noUnknownOriginators() async {
        // The allow-list is checked against the whole corpus rather than a
        // sample, so a Codex rename shows up here as a failing test instead of
        // as misclassified sessions in the wild. The edge-originator bucket is
        // captured deliberately and is expected to report.
        let unexpected = await Self.analysis().unknownOriginators
        #expect(unexpected.count <= 1, "unrecognized originators: \(unexpected.keys.sorted())")
    }

    @Test("the corpus decodes without reporting drift")
    func corpusDecodesCleanly() async {
        // The corpus is fully understood today, so any unrecognized record is a
        // real signal: either Codex introduced a type, or the table lost one.
        // Keeping the bar at zero is what turns a future Codex release into a
        // failing test instead of a silent behaviour change.
        let unknown = await Self.analysis().unknownRecords
        #expect(
            unknown.isEmpty,
            "unrecognized record types: \(unknown.keys.map(\.recordType).sorted())"
        )
    }

    @Test("injected context never becomes a session title")
    func injectedBlocksAreNotTitles() {
        // Codex prepends blocks to the transcript as if the user typed them.
        // Taking the first one as the title is what put
        // "<recommended_plugins> Here is a list…" in the session list.
        for injected in [
            "<recommended_plugins>\nHere is a list of plugins…",
            "<environment_context>\ncwd: /tmp",
            "<skills_instructions>\nuse skills",
            "<user_instructions>\nbe brief",
            "# AGENTS.md instructions for /repo",
            "<some_future_block>\ninvented later",
        ] {
            #expect(CodexRolloutSource.isInjectedBlock(injected), "not filtered: \(injected.prefix(30))")
        }
        // Real user text survives, including text that merely contains a tag.
        for real in [
            "fix the login bug",
            "为什么 <div> 没有渲染出来",
            "compare <a> and <b> tags",
        ] {
            #expect(!CodexRolloutSource.isInjectedBlock(real), "wrongly filtered: \(real)")
        }
    }

    @Test("a transcript opening with injected context titles from the real prompt")
    func titleSkipsInjectedOpening() {
        let lines = [
            #"{"type":"session_meta","timestamp":"2026-08-27T00:00:00Z","payload":{"id":"aaaa","cwd":"/Users/dev/work/personal","originator":"codex_work_desktop","cli_version":"0.148.0","source":"vscode","thread_source":"user"}}"#,
            #"{"type":"event_msg","payload":{"type":"user_message","message":"<recommended_plugins> Here is a list of plugins."}}"#,
            #"{"type":"event_msg","payload":{"type":"user_message","message":"这个仓库在哪里体现 RSI"}}"#,
        ]
        let reading = CodexRolloutSource().read(lines: lines, transcriptPath: "/tmp/r.jsonl")
        #expect(reading.observation?.patch.narrative?.initialUserPrompt == "这个仓库在哪里体现 RSI")
    }

    @Test("the legacy reducer filters the same injected blocks and keeps the cwd")
    func legacyDiscoveryMatchesOnTitleAndWorkspace() throws {
        // These two showed up together in the session list as
        // "/ · <recommended_plugins> Here…": the event_msg path had no
        // injected-block filter at all, and makeRecord dropped the working
        // directory so the workspace name resolved to "/".
        let transcript = """
        {"type":"session_meta","timestamp":"2026-08-27T00:00:00Z","payload":{"id":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/work/personal","originator":"codex_work_desktop","cli_version":"0.148.0","source":"vscode","thread_source":"user"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"<recommended_plugins> Here is a list of plugins."}}
        {"type":"event_msg","payload":{"type":"user_message","message":"这个仓库在哪里体现 RSI"}}
        """
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rollout-2026-08-27T00-00-00-11111111-2222-3333-4444-555555555555.jsonl")
        try (transcript + "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let discovery = CodexRolloutDiscovery(rootURL: url.deletingLastPathComponent())
        let record = try #require(discovery.discoverRecentSessions().first)

        #expect(record.codexMetadata?.initialUserPrompt == "这个仓库在哪里体现 RSI")
        #expect(record.jumpTarget?.workingDirectory == "/Users/dev/work/personal")
        #expect(record.jumpTarget?.workspaceName == "personal")
        // The row renders the summary; it must not be injected context either.
        #expect(!record.summary.contains("recommended_plugins"))
    }

    @Test("harness instructions are not treated as things the user said")
    func developerRoleIsNotUserText() {
        // `developer` messages carry the harness's own setup — "You are a
        // helpful assistant…", multi-agent wiring, desktop app context — and
        // outnumber real user messages in a live transcript. Mapping every
        // non-assistant role to "user" put a system prompt in the list.
        let decoder = CodexRecordDecoder()
        let developer = #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"text":"You are a helpful assistant. You will be presented…"}]}}"#
        #expect(decoder.decode(line: developer) == nil)

        let user = #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"text":"格雷GTO 开局前期发展"}]}}"#
        #expect(decoder.decode(line: user)?.kind == .userMessage)

        let assistant = #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"text":"我先确认一下"}]}}"#
        #expect(decoder.decode(line: assistant)?.kind == .assistantMessage)
    }

    @Test("a transcript whose only user text is a developer prompt yields no prompt")
    func developerOnlyTranscriptHasNoPrompt() {
        let lines = [
            #"{"type":"session_meta","timestamp":"2026-08-27T00:00:00Z","payload":{"id":"bbbb","cwd":"/Users/dev/.codex/.chatgpt-projects/g-p-abc","originator":"codex_work_desktop","cli_version":"0.148.0","source":"vscode","thread_source":"user"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"text":"You are a helpful assistant. You will be presented with a conversation."}]}}"#,
        ]
        let reading = CodexRolloutSource().read(lines: lines, transcriptPath: "/tmp/r.jsonl")
        #expect(reading.observation?.patch.narrative?.initialUserPrompt == nil)
        #expect(reading.observation?.patch.narrative?.lastUserPrompt == nil)
    }

    @Test("unrecognized record types are counted rather than dropped")
    func driftIsReported() {
        let diagnostics = CodexDiagnostics()
        let decoder = CodexRecordDecoder(diagnostics: diagnostics)

        // A record type from a hypothetical future release.
        let line = #"{"type":"quantum_state","payload":{},"timestamp":"2026-08-24T00:00:00Z"}"#
        #expect(decoder.decode(line: line, cliVersion: "9.9.9") == nil)

        let snapshot = diagnostics.snapshot()
        let key = CodexDiagnostics.UnknownRecord(recordType: "quantum_state", cliVersion: "9.9.9")
        #expect(snapshot.unknownRecords[key] == 1)
        #expect(snapshot.summaryLines.contains { $0.contains("quantum_state") })
    }
}
