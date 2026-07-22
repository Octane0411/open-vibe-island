import Foundation
import SQLite3
import Testing
@testable import OpenIslandCore

struct CodexThreadTitleStoreTests {
    @Test
    func readsTrimmedTitlesForRequestedThreads() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-codex-titles-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }

        try createFixture(
            at: databaseURL.path,
            rows: [
                ("thread-a", "  查找 VibeIsland 项目  "),
                ("thread-b", "调研AI智能小车方案"),
                ("thread-blank", "   "),
            ]
        )

        let titles = CodexThreadTitleStore(databasePath: databaseURL.path).titles(
            for: ["thread-a", "thread-b", "thread-blank", "missing"]
        )

        #expect(titles == [
            "thread-a": "查找 VibeIsland 项目",
            "thread-b": "调研AI智能小车方案",
        ])
    }

    @Test
    func readsThreadConfigurationWithCurrentServiceTierFallback() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-codex-config-\(UUID().uuidString).sqlite")
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-codex-config-\(UUID().uuidString).toml")
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(at: configURL)
        }

        try createFixture(
            at: databaseURL.path,
            rows: [("thread-a", "Task", "gpt-5.6-sol", "xhigh")]
        )
        try "service_tier = \"priority\"\n".write(to: configURL, atomically: true, encoding: .utf8)

        let metadata = CodexThreadTitleStore(
            databasePath: databaseURL.path,
            configPath: configURL.path
        ).configurationMetadata(for: "thread-a")

        #expect(metadata?.model == "gpt-5.6-sol")
        #expect(metadata?.reasoningEffort == "xhigh")
        #expect(metadata?.serviceTier == "priority")
    }
}

private func createFixture(at path: String, rows: [(String, String)]) throws {
    try createFixture(at: path, rows: rows.map { ($0.0, $0.1, nil, nil) })
}

private func createFixture(
    at path: String,
    rows: [(String, String, String?, String?)]
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(path, &database) == SQLITE_OK else {
        throw NSError(domain: "CodexThreadTitleStoreTests", code: 1)
    }
    defer { sqlite3_close(database) }

    guard sqlite3_exec(database, "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT NOT NULL, model TEXT, reasoning_effort TEXT);", nil, nil, nil) == SQLITE_OK else {
        throw NSError(domain: "CodexThreadTitleStoreTests", code: 2)
    }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "INSERT INTO threads (id, title, model, reasoning_effort) VALUES (?, ?, ?, ?);", -1, &statement, nil) == SQLITE_OK else {
        throw NSError(domain: "CodexThreadTitleStoreTests", code: 3)
    }
    defer { sqlite3_finalize(statement) }

    for (id, title, model, effort) in rows {
        sqlite3_reset(statement)
        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, title, -1, SQLITE_TRANSIENT)
        if let model {
            sqlite3_bind_text(statement, 3, model, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        if let effort {
            sqlite3_bind_text(statement, 4, effort, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "CodexThreadTitleStoreTests", code: 4)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
