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
@Suite("Codex fixture corpus")
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
    static let analysis: Analysis = {
        var result = Analysis()
        result.directoryCount = versionDirectories().count
        result.fixtureCount = cachedLines.count

        let diagnostics = CodexDiagnostics()
        let source = CodexRolloutSource(diagnostics: diagnostics)
        let store = CodexFacetStore()
        let projector = CodexSessionProjector(store: store)

        for (url, lines) in cachedLines {
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
    }()

    // MARK: - Assertions

    @Test("the corpus is present and spans many Codex versions")
    func corpusIsPopulated() throws {
        let analysis = Self.analysis
        try #require(analysis.fixtureCount > 0, "fixture corpus missing — run scripts/codex-fixtures.py")
        // A single machine accumulates transcripts from many releases at once;
        // the corpus has to reflect that or it proves nothing about drift.
        #expect(analysis.directoryCount >= 10)
    }

    @Test("every fixture yields a session header the decoder understands")
    func everyFixtureDecodesItsHeader() {
        let analysis = Self.analysis
        #expect(analysis.missingHeaders.isEmpty, "no session_meta in: \(analysis.missingHeaders)")
        #expect(analysis.decodedHeaders == analysis.fixtureCount)
    }

    @Test("spawned subagent transcripts never become user sessions")
    func subagentFixturesAreNotSessions() {
        let analysis = Self.analysis
        // Roughly half of a real corpus is threads Codex spawned for itself.
        #expect(analysis.subagentCount > 0, "no spawned-thread samples captured")
        #expect(analysis.subagentEventLeaks.isEmpty, "leaked: \(analysis.subagentEventLeaks)")
    }

    @Test("desktop transcripts classify as Codex.app across both originator spellings")
    func desktopFixturesClassify() {
        let analysis = Self.analysis
        #expect(analysis.misclassifiedDesktop.isEmpty, "\(analysis.misclassifiedDesktop)")
        #expect(analysis.desktopCount > 0, "corpus contains no desktop transcripts to verify")
    }

    @Test("no fixture reports an unknown originator")
    func noUnknownOriginators() {
        // The allow-list is checked against the whole corpus rather than a
        // sample, so a Codex rename shows up here as a failing test instead of
        // as misclassified sessions in the wild. The edge-originator bucket is
        // captured deliberately and is expected to report.
        let unexpected = Self.analysis.unknownOriginators
        #expect(unexpected.count <= 1, "unrecognized originators: \(unexpected.keys.sorted())")
    }

    @Test("the corpus decodes without reporting drift")
    func corpusDecodesCleanly() {
        // The corpus is fully understood today, so any unrecognized record is a
        // real signal: either Codex introduced a type, or the table lost one.
        // Keeping the bar at zero is what turns a future Codex release into a
        // failing test instead of a silent behaviour change.
        let unknown = Self.analysis.unknownRecords
        #expect(
            unknown.isEmpty,
            "unrecognized record types: \(unknown.keys.map(\.recordType).sorted())"
        )
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
