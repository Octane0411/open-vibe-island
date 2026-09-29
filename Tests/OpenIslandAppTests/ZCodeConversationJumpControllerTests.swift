import Foundation
import SQLite3
import Testing
@testable import OpenIslandApp

struct ZCodeConversationJumpControllerTests {
    @Test
    func taskIndexResolvesConversationTitleAndWorkspaceByHookSessionID() throws {
        let fixture = try makeTaskIndex()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let record = fixture.taskIndex.conversation(id: "sess_exact")

        #expect(
            record == ZCodeConversationRecord(
                id: "sess_exact",
                title: "Watch配对与新增Agent支持",
                workspacePath: "/Users/demo/open-vibe-island"
            )
        )
        #expect(fixture.taskIndex.conversation(id: "missing") == nil)
    }

    @Test
    func expiredFocusDeadlineStopsBeforeAccessibilityOrAppActivation() throws {
        let fixture = try makeTaskIndex()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let controller = ZCodeConversationJumpController(
            taskIndex: fixture.taskIndex,
            clock: { 0 },
            focusTimeout: 0
        )

        #expect(controller.focus(conversationID: "sess_exact") == .unavailable("focus-timeout"))
    }

    private func makeTaskIndex() throws -> (rootURL: URL, taskIndex: ZCodeTaskIndex) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-zcode-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let databaseURL = rootURL.appendingPathComponent("tasks-index.sqlite")
        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        let openedDatabase = try #require(database)
        defer { sqlite3_close(openedDatabase) }

        let schema = """
        CREATE TABLE tasks (
            task_id TEXT NOT NULL,
            title TEXT NOT NULL,
            workspace_path TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO tasks (task_id, title, workspace_path, updated_at, deleted)
        VALUES (
            'sess_exact',
            'Watch配对与新增Agent支持',
            '/Users/demo/open-vibe-island',
            42,
            0
        );
        """
        #expect(sqlite3_exec(openedDatabase, schema, nil, nil, nil) == SQLITE_OK)

        return (rootURL, ZCodeTaskIndex(databasePath: databaseURL.path))
    }
}
