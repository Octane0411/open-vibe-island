import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

struct AntigravitySessionTrackingTests {
    private let fileManager = FileManager.default

    private func makeRoot() throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("antigravity-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Writes a conversation DB with a specific mtime (spread hours apart so
    /// activity ordering is unambiguous).
    private func touchConversation(_ root: URL, id: String, modifiedAt: Date) throws {
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        try fileManager.createDirectory(at: conversations, withIntermediateDirectories: true)
        let fileURL = conversations.appendingPathComponent("\(id).db")
        try Data("fixture".utf8).write(to: fileURL)
        try fileManager.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: fileURL.path
        )
    }

    private func writeHistory(_ root: URL, lines: [String]) throws {
        try lines.joined(separator: "\n").write(
            to: root.appendingPathComponent("history.jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeSummariesDatabase(_ root: URL, rows: [(id: String, title: String, preview: String, workspaceURI: String?)]) throws {
        // The SQLite3 system module does not re-export SQLITE_TRANSIENT;
        // binding with it is required so SQLite copies Swift-bridged string
        // buffers before the temporary C representation is released.
        let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
        let databaseURL = root.appendingPathComponent("conversation_summaries.db")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            sqlite3_close(database)
            return
        }
        defer { sqlite3_close(database) }

        let create = """
        CREATE TABLE conversation_summaries (
            conversation_id text PRIMARY KEY,
            title text NOT NULL DEFAULT '',
            preview text NOT NULL DEFAULT '',
            workspace_uris text NOT NULL DEFAULT ''
        );
        """
        sqlite3_exec(database, create, nil, nil, nil)

        for row in rows {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(database, "INSERT INTO conversation_summaries (conversation_id, title, preview, workspace_uris) VALUES (?, ?, ?, ?)", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, row.id, -1, transient)
            sqlite3_bind_text(statement, 2, row.title, -1, transient)
            sqlite3_bind_text(statement, 3, row.preview, -1, transient)
            if let uri = row.workspaceURI {
                let payload = "[\"\(uri)\"]"
                sqlite3_bind_text(statement, 4, payload, -1, transient)
            } else {
                sqlite3_bind_text(statement, 4, "", -1, transient)
            }
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    private func historyLine(id: String, display: String, timestamp: Date, workspace: String?) -> String {
        let milliseconds = Int64(timestamp.timeIntervalSince1970 * 1000)
        let workspaceJSON = workspace.map { ",\"workspace\":\"\($0)\"" } ?? ""
        return "{\"display\":\"\(display)\",\"timestamp\":\(milliseconds),\"conversationId\":\"\(id)\"\(workspaceJSON),\"type\":\"prompt\"}"
    }

    @Test
    func discoverBuildsRunningSessionFromRecentConversation() throws {
        let root = try makeRoot()
        defer { try? fileManager.removeItem(at: root) }

        let now = Date.now
        let id = "6e279cf2-7dbe-41c8-b3fc-4b0328750678"
        try touchConversation(root, id: id, modifiedAt: now.addingTimeInterval(-30))
        try writeHistory(root, lines: [
            historyLine(id: id, display: "Fix the failing tests", timestamp: now.addingTimeInterval(-60), workspace: "/tmp/project-a"),
        ])

        let sessions = AntigravitySessionDiscovery(rootURL: root).discover(now: now)

        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session.id == id)
        #expect(session.tool == .antigravity)
        #expect(session.phase == .running)
        #expect(session.summary == "Fix the failing tests")
        #expect(session.jumpTarget?.workingDirectory == "/tmp/project-a")
        #expect(session.jumpTarget?.workspaceName == "project-a")
    }

    @Test
    func discoverMarksQuietSessionsCompletedAndDropsOldOnes() throws {
        let root = try makeRoot()
        defer { try? fileManager.removeItem(at: root) }

        let now = Date.now
        try touchConversation(root, id: "quiet-session", modifiedAt: now.addingTimeInterval(-3_600))
        try touchConversation(root, id: "ancient-session", modifiedAt: now.addingTimeInterval(-172_800))

        let sessions = AntigravitySessionDiscovery(rootURL: root).discover(now: now)
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        #expect(byID["quiet-session"]?.phase == .completed)
        #expect(byID["ancient-session"] == nil)
    }

    @Test
    func discoverPrefersHistoryPromptTimestampOverFileMtimeForActivity() throws {
        let root = try makeRoot()
        defer { try? fileManager.removeItem(at: root) }

        let now = Date.now
        let id = "fresh-prompt"
        // File mtime is old, but a fresh prompt arrived — the session must
        // surface as running with the prompt time as updatedAt.
        try touchConversation(root, id: id, modifiedAt: now.addingTimeInterval(-3_600))
        try writeHistory(root, lines: [
            historyLine(id: id, display: " newest question ", timestamp: now.addingTimeInterval(-120), workspace: nil),
        ])

        let sessions = AntigravitySessionDiscovery(rootURL: root).discover(now: now)
        let session = try #require(sessions.first)

        #expect(session.phase == .running)
        #expect(session.summary == "newest question")
    }

    @Test
    func discoverUsesSummaryTitleAndWorkspaceFallback() throws {
        let root = try makeRoot()
        defer { try? fileManager.removeItem(at: root) }

        let now = Date.now
        let id = "titled-conversation"
        try touchConversation(root, id: id, modifiedAt: now.addingTimeInterval(-60))
        try writeSummariesDatabase(root, rows: [(
            id: id,
            title: "Refactor rollout reducer",
            preview: "earlier preview text",
            workspaceURI: "file:///Users/demo/Some%20Project"
        )])

        let sessions = AntigravitySessionDiscovery(rootURL: root).discover(now: now)
        let session = try #require(sessions.first)

        #expect(session.title == "Refactor rollout reducer")
        #expect(session.summary == "earlier preview text")
        #expect(session.jumpTarget?.workingDirectory == "/Users/demo/Some Project")
    }

    @Test
    func discoverKeepsNewestPromptPerConversationAndCapsResultCount() throws {
        let root = try makeRoot()
        defer { try? fileManager.removeItem(at: root) }

        let now = Date.now
        for index in 0..<25 {
            try touchConversation(root, id: "conversation-\(index)", modifiedAt: now.addingTimeInterval(TimeInterval(-index * 60)))
        }

        let sessions = AntigravitySessionDiscovery(rootURL: root).discover(now: now)
        #expect(sessions.count == AntigravitySessionDiscovery.maxDiscoveredSessions)
        // Newest conversation first in, so the dropped ones are the oldest.
        #expect(!sessions.contains { $0.id == "conversation-24" })
    }

    @Test
    func summariesReaderReturnsEmptyForMissingDatabase() {
        let reader = AntigravitySummariesReader(databasePath: "/nonexistent/summaries.db")
        #expect(reader.summaries(for: ["any-id"]).isEmpty)
    }
}
