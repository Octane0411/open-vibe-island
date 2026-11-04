import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeSessionTitleTests {
    // MARK: - Helpers

    private func makeTempDirectory(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Mirrors Claude Desktop's `<base>/<uuid>/<uuid>/local_<uuid>.json` layout.
    private func makeDesktopSessionDirectory(base: URL) throws -> URL {
        let dir = base
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func writeDesktopSession(
        in dir: URL,
        name: String = "local_\(UUID().uuidString).json",
        contents: String,
        modifiedAt: Date? = nil
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if let modifiedAt {
            try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
        }
        return url
    }

    private func writeTranscript(_ lines: [String], to url: URL) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Resolver precedence

    @Test
    func resolverPrefersCustomTitle() {
        #expect(ClaudeSessionTitleResolver.resolve(customTitle: "Renamed", desktopTitle: "Desktop", aiTitle: "AI") == "Renamed")
    }

    @Test
    func resolverFallsBackToDesktopTitle() {
        #expect(ClaudeSessionTitleResolver.resolve(customTitle: nil, desktopTitle: "Desktop", aiTitle: "AI") == "Desktop")
        #expect(ClaudeSessionTitleResolver.resolve(customTitle: "   ", desktopTitle: "Desktop", aiTitle: "AI") == "Desktop")
    }

    @Test
    func resolverFallsBackToAITitle() {
        #expect(ClaudeSessionTitleResolver.resolve(customTitle: nil, desktopTitle: "", aiTitle: "Risposta PONG") == "Risposta PONG")
    }

    @Test
    func resolverReturnsNilWithoutAnySource() {
        #expect(ClaudeSessionTitleResolver.resolve(customTitle: nil, desktopTitle: nil, aiTitle: nil) == nil)
        #expect(ClaudeSessionTitleResolver.resolve(customTitle: "", desktopTitle: " \n", aiTitle: nil) == nil)
    }

    // MARK: - Claude Desktop index

    @Test
    func desktopIndexReadsTitlesAndSkipsUntitledAndMalformedFiles() throws {
        let base = try makeTempDirectory("desktop-index")
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = try makeDesktopSessionDirectory(base: base)

        try writeDesktopSession(
            in: dir,
            contents: #"{"sessionId":"local_1","cliSessionId":"cli-titled","cwd":"/tmp","title":"Sign the scooter insurance contract","titleSource":"user","enabledMcpTools":{"a":true}}"#
        )
        try writeDesktopSession(
            in: dir,
            contents: #"{"sessionId":"local_2","cliSessionId":"cli-untitled","cwd":"/tmp","enabledMcpTools":{"a":{"nested":[1,2,"}"]}}}"#
        )
        try writeDesktopSession(
            in: dir,
            contents: #"{"sessionId":"local_3","cliSessionId":"cli-empty","title":"   "}"#
        )
        try writeDesktopSession(in: dir, contents: "not json at all")
        try writeDesktopSession(in: dir, contents: #"{"cliSessionId": "cli-broken", "title": "#)

        let index = ClaudeDesktopSessionTitleIndex(baseURL: base)
        #expect(index.refreshIfNeeded(force: true))

        #expect(index.title(forCLISessionID: "cli-titled") == "Sign the scooter insurance contract")
        #expect(index.title(forCLISessionID: "cli-untitled") == nil)
        #expect(index.title(forCLISessionID: "cli-empty") == nil)
        #expect(index.title(forCLISessionID: "cli-broken") == nil)
        #expect(index.title(forCLISessionID: "unknown") == nil)
    }

    @Test
    func desktopIndexToleratesMissingDirectory() {
        let index = ClaudeDesktopSessionTitleIndex(
            baseURL: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        )
        #expect(index.refreshIfNeeded(force: true) == false)
        #expect(index.title(forCLISessionID: "anything") == nil)
    }

    @Test
    func desktopIndexFallsBackToFullParseWhenTitleIsBeyondPrefix() throws {
        let base = try makeTempDirectory("desktop-index-large")
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = try makeDesktopSessionDirectory(base: base)

        let padding = String(repeating: "x", count: 4_096)
        try writeDesktopSession(
            in: dir,
            contents: #"{"cliSessionId":"cli-late","padding":"\#(padding)","title":"Late title"}"#
        )

        let index = ClaudeDesktopSessionTitleIndex(baseURL: base, prefixByteCount: 256)
        index.refreshIfNeeded(force: true)
        #expect(index.title(forCLISessionID: "cli-late") == "Late title")
    }

    @Test
    func desktopIndexPicksUpChangedTitleWhenModificationDateChanges() throws {
        let base = try makeTempDirectory("desktop-index-refresh")
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = try makeDesktopSessionDirectory(base: base)
        let name = "local_refresh.json"
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        try writeDesktopSession(
            in: dir,
            name: name,
            contents: #"{"cliSessionId":"cli-refresh","title":"First title"}"#,
            modifiedAt: start
        )

        let index = ClaudeDesktopSessionTitleIndex(baseURL: base, minimumRescanInterval: 5)
        index.refreshIfNeeded(now: start, force: true)
        #expect(index.title(forCLISessionID: "cli-refresh") == "First title")

        try writeDesktopSession(
            in: dir,
            name: name,
            contents: #"{"cliSessionId":"cli-refresh","title":"Renamed in Desktop"}"#,
            modifiedAt: start.addingTimeInterval(10)
        )

        // Within the throttle window nothing is re-read.
        #expect(index.refreshIfNeeded(now: start.addingTimeInterval(1)) == false)
        #expect(index.title(forCLISessionID: "cli-refresh") == "First title")

        // After the window, the changed file is re-read.
        #expect(index.refreshIfNeeded(now: start.addingTimeInterval(6)))
        #expect(index.title(forCLISessionID: "cli-refresh") == "Renamed in Desktop")
    }

    @Test
    func topLevelScannerIgnoresNestedTitleKeys() {
        let json = #"{"meta":{"title":"nested"},"cliSessionId":"abc","list":[{"title":"x"}],"title":"top"}"#
        let result = TopLevelJSONStringScanner.scan(Data(json.utf8), keys: ["cliSessionId", "title"])
        #expect(result == .complete(["cliSessionId": "abc", "title": "top"]))
    }

    @Test
    func topLevelScannerDecodesEscapes() {
        let json = #"{"title":"Café \"quoted\"","cliSessionId":"id"}"#
        let result = TopLevelJSONStringScanner.scan(Data(json.utf8), keys: ["cliSessionId", "title"])
        #expect(result == .complete(["cliSessionId": "id", "title": "Café \"quoted\""]))
    }

    // MARK: - Live transcript scanner

    @Test
    func transcriptScannerTracksLastTitlesIncrementally() throws {
        let dir = try makeTempDirectory("title-scanner")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")

        try writeTranscript([
            #"{"type":"user","message":{"role":"user","content":"mention custom-title in text"},"sessionId":"s"}"#,
            #"{"type":"ai-title","aiTitle":"First AI","sessionId":"s"}"#,
        ], to: url)

        let scanner = ClaudeTranscriptTitleScanner()
        #expect(scanner.titles(forTranscriptAt: url.path) == ClaudeTranscriptTitles(customTitle: nil, aiTitle: "First AI"))

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let appended: [String] = [
            #"{"type":"custom-title","customTitle":"ipad audit","sessionId":"s"}"#,
            #"{"type":"custom-title","customTitle":"ipad audit (fork)","sessionId":"s"}"#,
            #"{"type":"ai-title","aiTitle":"Second AI","sessionId":"s"}"#,
        ]
        let appendedText = appended.joined(separator: "\n") + "\n"
        try handle.write(contentsOf: Data(appendedText.utf8))
        try handle.close()

        #expect(scanner.titles(forTranscriptAt: url.path) == ClaudeTranscriptTitles(customTitle: "ipad audit (fork)", aiTitle: "Second AI"))
        #expect(scanner.titles(forTranscriptAt: "/nonexistent/\(UUID().uuidString).jsonl") == ClaudeTranscriptTitles())
    }

    @Test
    func titleServiceAppliesPrecedenceAcrossSources() throws {
        let dir = try makeTempDirectory("title-service")
        defer { try? FileManager.default.removeItem(at: dir) }
        let desktopBase = dir.appendingPathComponent("desktop", isDirectory: true)
        let sessionDir = try makeDesktopSessionDirectory(base: desktopBase)
        try writeDesktopSession(
            in: sessionDir,
            contents: #"{"cliSessionId":"sess-1","title":"Desktop title"}"#
        )

        let transcript = dir.appendingPathComponent("sess-1.jsonl")
        try writeTranscript([#"{"type":"ai-title","aiTitle":"AI title","sessionId":"sess-1"}"#], to: transcript)

        let service = ClaudeSessionTitleService(
            desktopIndex: ClaudeDesktopSessionTitleIndex(baseURL: desktopBase)
        )
        #expect(service.refreshNow(sessionID: "sess-1", transcriptPath: transcript.path) == "Desktop title")
        #expect(service.cachedTitle(forSessionID: "sess-1") == "Desktop title")

        // AI title only for a session Desktop doesn't know.
        let other = dir.appendingPathComponent("sess-2.jsonl")
        try writeTranscript([#"{"type":"ai-title","aiTitle":"Only AI","sessionId":"sess-2"}"#], to: other)
        #expect(service.refreshNow(sessionID: "sess-2", transcriptPath: other.path) == "Only AI")

        // A rename in the transcript beats the Desktop title.
        try writeTranscript([
            #"{"type":"ai-title","aiTitle":"AI title","sessionId":"sess-1"}"#,
            #"{"type":"custom-title","customTitle":"Renamed","sessionId":"sess-1"}"#,
        ], to: transcript)
        #expect(service.refreshNow(sessionID: "sess-1", transcriptPath: transcript.path) == "Renamed")

        // No source at all.
        #expect(service.refreshNow(sessionID: "sess-3", transcriptPath: nil) == nil)
    }

    @Test
    func titleServiceNotifiesOnChange() async throws {
        let dir = try makeTempDirectory("title-service-notify")
        defer { try? FileManager.default.removeItem(at: dir) }
        let transcript = dir.appendingPathComponent("sess.jsonl")
        try writeTranscript([#"{"type":"ai-title","aiTitle":"Async AI","sessionId":"sess"}"#], to: transcript)

        let service = ClaudeSessionTitleService(desktopIndex: nil)
        let received = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            service.setChangeHandler { sessionID, title in
                #expect(sessionID == "sess")
                continuation.resume(returning: title)
            }
            service.requestRefresh(sessionID: "sess", transcriptPath: transcript.path)
        }
        service.setChangeHandler(nil)
        #expect(received == "Async AI")
        #expect(service.cachedTitle(forSessionID: "sess") == "Async AI")
    }

    // MARK: - Metadata compatibility

    @Test
    func metadataDecodesWithoutSessionTitleKey() throws {
        let json = #"{"transcriptPath":"/tmp/a.jsonl","initialUserPrompt":"hi","activeSubagents":[],"activeTasks":[]}"#
        let metadata = try JSONDecoder().decode(ClaudeSessionMetadata.self, from: Data(json.utf8))
        #expect(metadata.sessionTitle == nil)
        #expect(metadata.initialUserPrompt == "hi")
    }

    @Test
    func metadataRoundTripsSessionTitleAndCountsAsNonEmpty() throws {
        let metadata = ClaudeSessionMetadata(sessionTitle: "Named")
        #expect(metadata.isEmpty == false)
        let decoded = try JSONDecoder().decode(
            ClaudeSessionMetadata.self,
            from: JSONEncoder().encode(metadata)
        )
        #expect(decoded.sessionTitle == "Named")
    }
}
