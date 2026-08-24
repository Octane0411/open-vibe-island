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
@Suite("Codex fixture corpus")
struct CodexFixtureCorpusTests {
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

    @Test("the corpus is present and spans many Codex versions")
    func corpusIsPopulated() throws {
        let directories = Self.versionDirectories()
        try #require(!directories.isEmpty, "fixture corpus missing — run scripts/codex-fixtures.py")
        // A single machine accumulates transcripts from many releases at once;
        // the corpus has to reflect that or it proves nothing about drift.
        #expect(directories.count >= 10)
        #expect(!Self.allFixtures().isEmpty)
    }

    @Test("every fixture yields a session header the decoder understands")
    func everyFixtureDecodesItsHeader() throws {
        let source = CodexRolloutSource()
        var decoded = 0

        for fixture in Self.allFixtures() {
            let reading = source.read(fileAt: fixture)
            #expect(reading.meta != nil, "no session_meta decoded from \(fixture.lastPathComponent)")
            if let meta = reading.meta {
                #expect(!meta.sessionID.isEmpty)
                #expect(!meta.cwd.isEmpty)
                decoded += 1
            }
        }

        #expect(decoded == Self.allFixtures().count)
    }

    @Test("spawned subagent transcripts never become user sessions")
    func subagentFixturesAreNotSessions() throws {
        guard let root = Self.corpusRoot else { return }
        let directory = root.appendingPathComponent("edge-subagent", isDirectory: true)
        let fixtures = Self.fixtures(in: directory)
        try #require(!fixtures.isEmpty, "no subagent fixtures captured")

        let rollout = CodexRolloutSource()
        let store = CodexFacetStore()
        let projector = CodexSessionProjector(store: store)

        for fixture in fixtures {
            let reading = rollout.read(fileAt: fixture)
            #expect(reading.isSubagent, "\(fixture.lastPathComponent) should classify as a subagent")

            if let observation = reading.observation {
                let events = projector.project(observation)
                #expect(events.isEmpty, "\(fixture.lastPathComponent) produced session events")
            }
        }
    }

    @Test("desktop transcripts classify as Codex.app across both originator spellings")
    func desktopFixturesClassify() throws {
        let source = CodexRolloutSource()
        var seenDesktop = false

        for fixture in Self.allFixtures() {
            guard let meta = source.read(fileAt: fixture).meta else { continue }
            guard let originator = meta.originator,
                  CodexIdentityResolver.desktopOriginators.contains(originator) else { continue }
            guard meta.threadSource != "subagent" else { continue }
            if case .subagent = meta.source { continue }

            let surface = CodexIdentityResolver.surface(
                originator: originator,
                source: meta.source,
                threadSource: meta.threadSource,
                parentThreadID: meta.parentThreadID
            )
            #expect(surface == .desktopApp, "\(originator) in \(fixture.lastPathComponent)")
            seenDesktop = true
        }

        #expect(seenDesktop, "corpus contains no desktop transcripts to verify")
    }

    @Test("no fixture reports an unknown originator")
    func noUnknownOriginators() throws {
        // The allow-list is checked against the whole corpus rather than a
        // sample, so a Codex rename shows up here as a failing test instead of
        // as misclassified sessions in the wild.
        let diagnostics = CodexDiagnostics()
        let source = CodexRolloutSource(diagnostics: diagnostics)

        for fixture in Self.allFixtures() where !fixture.path.contains("edge-originator") {
            _ = source.read(fileAt: fixture)
        }

        let unknown = diagnostics.snapshot().unknownOriginators
        #expect(unknown.isEmpty, "unrecognized originators: \(unknown.keys.sorted())")
    }

    @Test("unrecognized record types are counted rather than dropped")
    func driftIsReported() throws {
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

    @Test("the corpus decodes without reporting widespread drift")
    func corpusDecodesCleanly() throws {
        let diagnostics = CodexDiagnostics()
        let source = CodexRolloutSource(diagnostics: diagnostics)

        for fixture in Self.allFixtures() {
            _ = source.read(fileAt: fixture)
        }

        // The corpus is fully understood today, so any unrecognized record is
        // a real signal: either Codex introduced a type, or the table lost one.
        // Keeping the bar at zero is what turns a future Codex release into a
        // failing test instead of a silent behaviour change.
        let unknown = diagnostics.snapshot().unknownRecords
        #expect(
            unknown.isEmpty,
            "unrecognized record types: \(unknown.keys.map(\.recordType).sorted())"
        )
    }
}
