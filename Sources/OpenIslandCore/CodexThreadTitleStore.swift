import Foundation
import SQLite3

/// Read-only access to the task titles maintained by Codex Desktop.
public struct CodexThreadTitleStore: Sendable {
    public let databasePath: String
    public let configPath: String

    public init(
        databasePath: String = Self.defaultDatabasePath(),
        configPath: String = Self.defaultConfigPath()
    ) {
        self.databasePath = databasePath
        self.configPath = configPath
    }

    public static func defaultDatabasePath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
            .path
    }

    public static func defaultConfigPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
            .path
    }

    public func title(for threadID: String) -> String? {
        titles(for: [threadID])[threadID]
    }

    public func titles(for threadIDs: Set<String>) -> [String: String] {
        guard !threadIDs.isEmpty,
              FileManager.default.fileExists(atPath: databasePath) else {
            return [:]
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databasePath, &database, flags, nil) == SQLITE_OK,
              let database else {
            if database != nil {
                sqlite3_close(database)
            }
            return [:]
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 60)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT id, title FROM threads WHERE title != '';",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        let statement else {
            return [:]
        }
        defer { sqlite3_finalize(statement) }

        var result: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idBytes = sqlite3_column_text(statement, 0),
                  let titleBytes = sqlite3_column_text(statement, 1) else {
                continue
            }

            let id = String(cString: idBytes)
            guard threadIDs.contains(id) else {
                continue
            }

            let title = String(cString: titleBytes)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                result[id] = title
            }
        }

        return result
    }

    /// Reads the current per-thread model and effort from Codex's state
    /// database. The service tier is a process-wide preference in
    /// `config.toml`, so it is used as a fallback until the rollout watcher
    /// observes a thread-specific setting.
    public func configurationMetadata(for threadID: String) -> CodexSessionMetadata? {
        guard !threadID.isEmpty,
              FileManager.default.fileExists(atPath: databasePath) else {
            return nil
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databasePath, &database, flags, nil) == SQLITE_OK,
              let database else {
            if database != nil {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 60)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT model, reasoning_effort FROM threads WHERE id = ? LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, threadID, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let metadata = CodexSessionMetadata(
            model: trimmedColumn(statement, index: 0),
            reasoningEffort: trimmedColumn(statement, index: 1),
            serviceTier: configuredServiceTier()
        )
        return metadata.isEmpty ? nil : metadata
    }

    private func configuredServiceTier() -> String? {
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }

        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard line.hasPrefix("service_tier"),
                  let separator = line.firstIndex(of: "=") else {
                continue
            }

            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }

        return nil
    }

    private func trimmedColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        let value = String(cString: bytes).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
