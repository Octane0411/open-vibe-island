import Foundation
import SQLite3

public actor SQLiteGraphExecutionStore:
    GraphExecutionEventStore,
    GraphExecutionSnapshotStore
{
    public static let currentDatabaseSchemaVersion = 1

    private let databasePath: String

    public static func defaultDatabasePath() throws -> String {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupport
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("graph-execution.sqlite")
            .path
    }

    public init(databasePath: String) throws {
        self.databasePath = databasePath
        try Self.createParentDirectoryIfNeeded(databasePath)
        let database = try Self.openDatabase(at: databasePath)
        defer { sqlite3_close(database) }
        try Self.configure(database)
        try Self.migrate(database)
    }

    public func append(
        _ events: [GraphExecutionEventEnvelope],
        to runID: String,
        expectedVersion: UInt64
    ) throws -> GraphExecutionAppendResult {
        let normalized = try Self.normalize(events)
        let database = try Self.openConfiguredDatabase(
            at: databasePath
        )
        defer { sqlite3_close(database) }
        try Self.execute(database, sql: "BEGIN IMMEDIATE;")
        var committed = false

        defer {
            if !committed {
                try? Self.execute(database, sql: "ROLLBACK;")
            }
        }

        let currentVersion = try Self.currentVersion(
            runID: runID,
            database: database
        )

        for event in normalized where event.runID != runID {
            throw GraphExecutionPersistenceError.invalidRunID(
                expected: runID,
                actual: event.runID
            )
        }

        var newEvents: [GraphExecutionEventEnvelope] = []

        for event in normalized {
            guard event.schemaVersion
                    <= GraphExecutionSchema.eventEnvelopeVersion else {
                throw GraphExecutionPersistenceError
                    .unsupportedSchemaVersion(
                        artifact: "event envelope",
                        found: event.schemaVersion,
                        supported: GraphExecutionSchema.eventEnvelopeVersion
                    )
            }

            if let existing = try Self.event(
                withID: event.id,
                database: database
            ) {
                guard existing == event else {
                    throw GraphExecutionPersistenceError
                        .eventIDCollision(eventID: event.id)
                }
            } else {
                newEvents.append(event)
            }
        }

        let duplicateCount = events.count - newEvents.count

        if newEvents.isEmpty {
            try Self.execute(database, sql: "COMMIT;")
            committed = true
            return GraphExecutionAppendResult(
                previousVersion: currentVersion,
                newVersion: currentVersion,
                appendedCount: 0,
                deduplicatedCount: duplicateCount
            )
        }

        guard expectedVersion == currentVersion else {
            throw GraphExecutionPersistenceError
                .expectedVersionConflict(
                    runID: runID,
                    expected: expectedVersion,
                    actual: currentVersion
                )
        }

        var expectedSequence = currentVersion + 1

        for event in newEvents {
            guard event.streamSequence == expectedSequence else {
                if try Self.eventExists(
                    runID: runID,
                    sequence: event.streamSequence,
                    database: database
                ) {
                    throw GraphExecutionPersistenceError
                        .sequenceConflict(
                            runID: runID,
                            sequence: event.streamSequence
                        )
                }

                throw GraphExecutionPersistenceError.sequenceGap(
                    expected: expectedSequence,
                    actual: event.streamSequence
                )
            }

            try Self.insert(event, database: database)
            expectedSequence += 1
        }

        let newVersion = newEvents.last?.streamSequence
            ?? currentVersion
        try Self.setCurrentVersion(
            runID: runID,
            from: currentVersion,
            to: newVersion,
            database: database
        )
        try Self.execute(database, sql: "COMMIT;")
        committed = true

        return GraphExecutionAppendResult(
            previousVersion: currentVersion,
            newVersion: newVersion,
            appendedCount: newEvents.count,
            deduplicatedCount: duplicateCount
        )
    }

    public func read(
        runID: String,
        afterVersion: UInt64
    ) throws -> GraphExecutionEventStream {
        let database = try Self.openConfiguredDatabase(
            at: databasePath
        )
        defer { sqlite3_close(database) }
        let currentVersion = try Self.currentVersion(
            runID: runID,
            database: database
        )
        let sql = """
        SELECT
            event_id,
            stream_sequence,
            envelope_schema_version,
            event_type,
            payload_version,
            event_json
        FROM graph_execution_events
        WHERE run_id = ? AND stream_sequence > ?
        ORDER BY stream_sequence ASC, event_id ASC;
        """
        let statement = try Self.prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try Self.bind(runID, at: 1, statement: statement)
        sqlite3_bind_int64(
            statement,
            2,
            Int64(bitPattern: afterVersion)
        )
        var events: [GraphExecutionEventEnvelope] = []
        var expectedSequence = afterVersion + 1

        while true {
            let result = sqlite3_step(statement)

            if result == SQLITE_DONE {
                break
            }

            guard result == SQLITE_ROW else {
                throw Self.storageError(database, operation: "read events")
            }

            let storedID = try Self.textColumn(
                statement,
                index: 0,
                name: "event_id"
            )
            let storedSequence = UInt64(
                bitPattern: sqlite3_column_int64(statement, 1)
            )
            let storedEnvelopeVersion = Int(
                sqlite3_column_int(statement, 2)
            )
            let storedEventType = try Self.textColumn(
                statement,
                index: 3,
                name: "event_type"
            )
            let storedPayloadVersion = Int(
                sqlite3_column_int(statement, 4)
            )
            let data = try Self.dataColumn(
                statement,
                index: 5,
                name: "event_json"
            )
            let event = try Self.decodeEvent(data)

            guard storedSequence == expectedSequence else {
                throw GraphExecutionPersistenceError.corruptRecord(
                    "Run \(runID) expected sequence \(expectedSequence), found \(storedSequence)."
                )
            }

            guard event.id == storedID,
                  event.runID == runID,
                  event.streamSequence == storedSequence,
                  event.schemaVersion == storedEnvelopeVersion,
                  event.eventType == storedEventType,
                  event.payloadVersion == storedPayloadVersion else {
                throw GraphExecutionPersistenceError.corruptRecord(
                    "Event \(storedID) indexed metadata does not match its envelope."
                )
            }

            events.append(event)
            expectedSequence += 1
        }

        if afterVersion < currentVersion,
           expectedSequence - 1 != currentVersion {
            throw GraphExecutionPersistenceError.corruptRecord(
                "Run \(runID) stream head is \(currentVersion), but records end at \(expectedSequence - 1)."
            )
        }

        return GraphExecutionEventStream(
            runID: runID,
            afterVersion: afterVersion,
            currentVersion: currentVersion,
            events: events
        )
    }

    public func loadLatest(
        runID: String
    ) throws -> GraphExecutionSnapshot? {
        let database = try Self.openConfiguredDatabase(
            at: databasePath
        )
        defer { sqlite3_close(database) }
        let sql = """
        SELECT
            stream_version,
            snapshot_schema_version,
            snapshot_json
        FROM graph_execution_snapshots
        WHERE run_id = ?
        ORDER BY stream_version DESC
        LIMIT 1;
        """
        let statement = try Self.prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try Self.bind(runID, at: 1, statement: statement)
        let result = sqlite3_step(statement)

        if result == SQLITE_DONE {
            return nil
        }

        guard result == SQLITE_ROW else {
            throw Self.storageError(database, operation: "load snapshot")
        }

        let storedVersion = UInt64(
            bitPattern: sqlite3_column_int64(statement, 0)
        )
        let storedSchemaVersion = Int(
            sqlite3_column_int(statement, 1)
        )
        let data = try Self.dataColumn(
            statement,
            index: 2,
            name: "snapshot_json"
        )
        let snapshot = try Self.decodeSnapshot(data)

        guard snapshot.runID == runID,
              snapshot.streamVersion == storedVersion,
              snapshot.schemaVersion == storedSchemaVersion else {
            throw GraphExecutionPersistenceError.corruptRecord(
                "Snapshot \(runID)@\(storedVersion) indexed metadata does not match its payload."
            )
        }

        return snapshot
    }

    public func save(
        _ snapshot: GraphExecutionSnapshot
    ) throws {
        let database = try Self.openConfiguredDatabase(
            at: databasePath
        )
        defer { sqlite3_close(database) }
        try Self.execute(database, sql: "BEGIN IMMEDIATE;")
        var committed = false

        defer {
            if !committed {
                try? Self.execute(database, sql: "ROLLBACK;")
            }
        }

        if let existing = try Self.snapshot(
            runID: snapshot.runID,
            streamVersion: snapshot.streamVersion,
            database: database
        ) {
            guard existing == snapshot else {
                throw GraphExecutionPersistenceError.corruptRecord(
                    "Snapshot \(snapshot.runID)@\(snapshot.streamVersion) already exists with different content."
                )
            }

            try Self.execute(database, sql: "COMMIT;")
            committed = true
            return
        }

        let sql = """
        INSERT INTO graph_execution_snapshots (
            run_id,
            stream_version,
            snapshot_schema_version,
            graph_definition_version,
            graph_definition_digest,
            created_at,
            snapshot_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        let statement = try Self.prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }
        try Self.bind(snapshot.runID, at: 1, statement: statement)
        sqlite3_bind_int64(
            statement,
            2,
            Int64(bitPattern: snapshot.streamVersion)
        )
        sqlite3_bind_int(
            statement,
            3,
            Int32(snapshot.schemaVersion)
        )
        try Self.bind(
            snapshot.graphDefinitionVersion,
            at: 4,
            statement: statement
        )
        try Self.bind(
            snapshot.graphDefinitionDigest.value,
            at: 5,
            statement: statement
        )
        sqlite3_bind_double(
            statement,
            6,
            snapshot.createdAt.timeIntervalSince1970
        )
        try Self.bind(
            try Self.encode(snapshot),
            at: 7,
            statement: statement
        )

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw Self.storageError(database, operation: "insert snapshot")
        }

        try Self.execute(database, sql: "COMMIT;")
        committed = true
    }

    public func databaseSchemaVersion() throws -> Int {
        let database = try Self.openConfiguredDatabase(
            at: databasePath
        )
        defer { sqlite3_close(database) }
        let statement = try Self.prepare(
            database,
            sql: "PRAGMA user_version;"
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw Self.storageError(
                database,
                operation: "read schema version"
            )
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private static func createParentDirectoryIfNeeded(
        _ path: String
    ) throws {
        guard path != ":memory:" else {
            return
        }

        let directory = URL(fileURLWithPath: path)
            .deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private static func openConfiguredDatabase(
        at path: String
    ) throws -> OpaquePointer {
        let database = try openDatabase(at: path)

        do {
            try configure(database)
            return database
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    private static func openDatabase(
        at path: String
    ) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE
            | SQLITE_OPEN_CREATE
            | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &database, flags, nil)

        guard result == SQLITE_OK, let database else {
            let message = database.map {
                String(cString: sqlite3_errmsg($0))
            } ?? "unknown open error"

            if let database {
                sqlite3_close(database)
            }

            throw GraphExecutionPersistenceError.storageFailure(
                "Unable to open \(path): \(message)"
            )
        }

        sqlite3_busy_timeout(database, 5_000)
        return database
    }

    private static func configure(
        _ database: OpaquePointer
    ) throws {
        try execute(database, sql: "PRAGMA foreign_keys = ON;")
        try execute(database, sql: "PRAGMA journal_mode = WAL;")
        try execute(database, sql: "PRAGMA synchronous = FULL;")
    }

    private static func migrate(
        _ database: OpaquePointer
    ) throws {
        let version = try userVersion(database)

        guard version <= currentDatabaseSchemaVersion else {
            throw GraphExecutionPersistenceError
                .unsupportedSchemaVersion(
                    artifact: "SQLite database",
                    found: version,
                    supported: currentDatabaseSchemaVersion
                )
        }

        guard version < 1 else {
            return
        }

        try execute(database, sql: "BEGIN IMMEDIATE;")
        var committed = false

        defer {
            if !committed {
                try? execute(database, sql: "ROLLBACK;")
            }
        }

        let lockedVersion = try userVersion(database)

        if lockedVersion >= 1 {
            try execute(database, sql: "COMMIT;")
            committed = true
            return
        }

        try execute(
            database,
            sql: """
            CREATE TABLE graph_schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            );

            CREATE TABLE graph_execution_streams (
                run_id TEXT PRIMARY KEY,
                current_version INTEGER NOT NULL CHECK(current_version >= 0)
            );

            CREATE TABLE graph_execution_events (
                event_id TEXT PRIMARY KEY,
                run_id TEXT NOT NULL,
                stream_sequence INTEGER NOT NULL CHECK(stream_sequence > 0),
                envelope_schema_version INTEGER NOT NULL,
                event_type TEXT NOT NULL,
                payload_version INTEGER NOT NULL,
                occurred_at REAL NOT NULL,
                recorded_at REAL NOT NULL,
                event_json BLOB NOT NULL,
                UNIQUE(run_id, stream_sequence)
            );

            CREATE INDEX graph_execution_events_run_sequence
                ON graph_execution_events(run_id, stream_sequence);

            CREATE TABLE graph_execution_snapshots (
                run_id TEXT NOT NULL,
                stream_version INTEGER NOT NULL CHECK(stream_version >= 0),
                snapshot_schema_version INTEGER NOT NULL,
                graph_definition_version TEXT NOT NULL,
                graph_definition_digest TEXT NOT NULL,
                created_at REAL NOT NULL,
                snapshot_json BLOB NOT NULL,
                PRIMARY KEY(run_id, stream_version)
            );

            CREATE INDEX graph_execution_snapshots_latest
                ON graph_execution_snapshots(run_id, stream_version DESC);

            INSERT INTO graph_schema_migrations(version, applied_at)
                VALUES (1, unixepoch('subsec'));

            PRAGMA user_version = 1;
            """
        )
        try execute(database, sql: "COMMIT;")
        committed = true
    }

    private static func userVersion(
        _ database: OpaquePointer
    ) throws -> Int {
        let statement = try prepare(
            database,
            sql: "PRAGMA user_version;"
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw storageError(
                database,
                operation: "read user_version"
            )
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private static func currentVersion(
        runID: String,
        database: OpaquePointer
    ) throws -> UInt64 {
        let statement = try prepare(
            database,
            sql: """
            SELECT current_version
            FROM graph_execution_streams
            WHERE run_id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(runID, at: 1, statement: statement)
        let result = sqlite3_step(statement)

        if result == SQLITE_DONE {
            return 0
        }

        guard result == SQLITE_ROW else {
            throw storageError(database, operation: "read stream head")
        }

        return UInt64(
            bitPattern: sqlite3_column_int64(statement, 0)
        )
    }

    private static func setCurrentVersion(
        runID: String,
        from previousVersion: UInt64,
        to newVersion: UInt64,
        database: OpaquePointer
    ) throws {
        let statement = try prepare(
            database,
            sql: """
            INSERT INTO graph_execution_streams(run_id, current_version)
            VALUES (?, ?)
            ON CONFLICT(run_id) DO UPDATE SET
                current_version = excluded.current_version
            WHERE graph_execution_streams.current_version = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(runID, at: 1, statement: statement)
        sqlite3_bind_int64(
            statement,
            2,
            Int64(bitPattern: newVersion)
        )
        sqlite3_bind_int64(
            statement,
            3,
            Int64(bitPattern: previousVersion)
        )

        guard sqlite3_step(statement) == SQLITE_DONE,
              sqlite3_changes(database) == 1 else {
            throw GraphExecutionPersistenceError
                .expectedVersionConflict(
                    runID: runID,
                    expected: previousVersion,
                    actual: try currentVersion(
                        runID: runID,
                        database: database
                    )
                )
        }
    }

    private static func insert(
        _ event: GraphExecutionEventEnvelope,
        database: OpaquePointer
    ) throws {
        let statement = try prepare(
            database,
            sql: """
            INSERT INTO graph_execution_events (
                event_id,
                run_id,
                stream_sequence,
                envelope_schema_version,
                event_type,
                payload_version,
                occurred_at,
                recorded_at,
                event_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(event.id, at: 1, statement: statement)
        try bind(event.runID, at: 2, statement: statement)
        sqlite3_bind_int64(
            statement,
            3,
            Int64(bitPattern: event.streamSequence)
        )
        sqlite3_bind_int(
            statement,
            4,
            Int32(event.schemaVersion)
        )
        try bind(event.eventType, at: 5, statement: statement)
        sqlite3_bind_int(
            statement,
            6,
            Int32(event.payloadVersion)
        )
        sqlite3_bind_double(
            statement,
            7,
            event.occurredAt.timeIntervalSince1970
        )
        sqlite3_bind_double(
            statement,
            8,
            event.recordedAt.timeIntervalSince1970
        )
        try bind(
            try encode(event),
            at: 9,
            statement: statement
        )

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let code = sqlite3_extended_errcode(database)

            if code & 0xFF == SQLITE_CONSTRAINT {
                throw GraphExecutionPersistenceError
                    .sequenceConflict(
                        runID: event.runID,
                        sequence: event.streamSequence
                    )
            }

            throw storageError(database, operation: "insert event")
        }
    }

    private static func event(
        withID eventID: String,
        database: OpaquePointer
    ) throws -> GraphExecutionEventEnvelope? {
        let statement = try prepare(
            database,
            sql: """
            SELECT event_json
            FROM graph_execution_events
            WHERE event_id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(eventID, at: 1, statement: statement)
        let result = sqlite3_step(statement)

        if result == SQLITE_DONE {
            return nil
        }

        guard result == SQLITE_ROW else {
            throw storageError(database, operation: "read event ID")
        }

        return try decodeEvent(
            dataColumn(statement, index: 0, name: "event_json")
        )
    }

    private static func eventExists(
        runID: String,
        sequence: UInt64,
        database: OpaquePointer
    ) throws -> Bool {
        let statement = try prepare(
            database,
            sql: """
            SELECT 1
            FROM graph_execution_events
            WHERE run_id = ? AND stream_sequence = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(runID, at: 1, statement: statement)
        sqlite3_bind_int64(
            statement,
            2,
            Int64(bitPattern: sequence)
        )
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func snapshot(
        runID: String,
        streamVersion: UInt64,
        database: OpaquePointer
    ) throws -> GraphExecutionSnapshot? {
        let statement = try prepare(
            database,
            sql: """
            SELECT snapshot_json
            FROM graph_execution_snapshots
            WHERE run_id = ? AND stream_version = ?;
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(runID, at: 1, statement: statement)
        sqlite3_bind_int64(
            statement,
            2,
            Int64(bitPattern: streamVersion)
        )
        let result = sqlite3_step(statement)

        if result == SQLITE_DONE {
            return nil
        }

        guard result == SQLITE_ROW else {
            throw storageError(database, operation: "read snapshot")
        }

        return try decodeSnapshot(
            dataColumn(statement, index: 0, name: "snapshot_json")
        )
    }

    private static func normalize(
        _ events: [GraphExecutionEventEnvelope]
    ) throws -> [GraphExecutionEventEnvelope] {
        var byID: [String: GraphExecutionEventEnvelope] = [:]

        for event in events {
            if let existing = byID[event.id],
               existing != event {
                throw GraphExecutionPersistenceError.eventIDCollision(
                    eventID: event.id
                )
            }

            byID[event.id] = event
        }

        return byID.values.sorted {
            if $0.streamSequence != $1.streamSequence {
                return $0.streamSequence < $1.streamSequence
            }

            return $0.id < $1.id
        }
    }

    private static func encode<Value: Encodable>(
        _ value: Value
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970

        do {
            return try encoder.encode(value)
        } catch {
            throw GraphExecutionPersistenceError.storageFailure(
                "Unable to encode persisted value: \(error.localizedDescription)"
            )
        }
    }

    private static func decodeEvent(
        _ data: Data
    ) throws -> GraphExecutionEventEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            return try decoder.decode(
                GraphExecutionEventEnvelope.self,
                from: data
            )
        } catch {
            throw GraphExecutionPersistenceError.corruptRecord(
                "Unable to decode event envelope: \(error.localizedDescription)"
            )
        }
    }

    private static func decodeSnapshot(
        _ data: Data
    ) throws -> GraphExecutionSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        do {
            return try decoder.decode(
                GraphExecutionSnapshot.self,
                from: data
            )
        } catch {
            throw GraphExecutionPersistenceError.corruptRecord(
                "Unable to decode snapshot: \(error.localizedDescription)"
            )
        }
    }

    private static func execute(
        _ database: OpaquePointer,
        sql: String
    ) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(
            database,
            sql,
            nil,
            nil,
            &errorMessage
        )

        guard result == SQLITE_OK else {
            let message = errorMessage.map {
                String(cString: $0)
            } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw GraphExecutionPersistenceError.storageFailure(message)
        }
    }

    private static func prepare(
        _ database: OpaquePointer,
        sql: String
    ) throws -> OpaquePointer {
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw storageError(database, operation: "prepare SQL")
        }

        return statement
    }

    private static func bind(
        _ value: String,
        at index: Int32,
        statement: OpaquePointer
    ) throws {
        let result = value.withCString {
            sqlite3_bind_text(
                statement,
                index,
                $0,
                -1,
                sqliteTransient
            )
        }

        guard result == SQLITE_OK else {
            throw GraphExecutionPersistenceError.storageFailure(
                "Unable to bind text value."
            )
        }
    }

    private static func bind(
        _ value: Data,
        at index: Int32,
        statement: OpaquePointer
    ) throws {
        let result = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                index,
                bytes.baseAddress,
                Int32(bytes.count),
                sqliteTransient
            )
        }

        guard result == SQLITE_OK else {
            throw GraphExecutionPersistenceError.storageFailure(
                "Unable to bind data value."
            )
        }
    }

    private static func textColumn(
        _ statement: OpaquePointer,
        index: Int32,
        name: String
    ) throws -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            throw GraphExecutionPersistenceError.corruptRecord(
                "Column \(name) is null."
            )
        }

        return String(cString: value)
    }

    private static func dataColumn(
        _ statement: OpaquePointer,
        index: Int32,
        name: String
    ) throws -> Data {
        let count = Int(sqlite3_column_bytes(statement, index))

        guard count >= 0,
              let bytes = sqlite3_column_blob(statement, index)
                ?? (count == 0 ? UnsafeRawPointer(bitPattern: 1) : nil)
        else {
            throw GraphExecutionPersistenceError.corruptRecord(
                "Column \(name) is null."
            )
        }

        if count == 0 {
            return Data()
        }

        return Data(bytes: bytes, count: count)
    }

    private static func storageError(
        _ database: OpaquePointer,
        operation: String
    ) -> GraphExecutionPersistenceError {
        .storageFailure(
            "\(operation): \(String(cString: sqlite3_errmsg(database)))"
        )
    }

    private static var sqliteTransient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}
