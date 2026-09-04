import Foundation
import XCTest
@testable import OpenIslandCore

final class SQLiteGraphExecutionStoreTests: XCTestCase {
    func testMigrationCreatesCurrentSchema() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )

        let version = try await store.databaseSchemaVersion()

        XCTAssertEqual(
            version,
            SQLiteGraphExecutionStore.currentDatabaseSchemaVersion
        )
    }

    func testEventsPersistAcrossStoreRestart() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let firstStore = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
        ]
        _ = try await firstStore.append(
            events,
            to: "run",
            expectedVersion: 0
        )
        let reopened = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )

        let stream = try await reopened.read(
            runID: "run",
            afterVersion: 0
        )

        XCTAssertEqual(stream.currentVersion, 2)
        XCTAssertEqual(stream.events, events)
    }

    func testSQLiteAppendEnforcesExpectedVersion() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        _ = try await store.append(
            [graphTestRunCreated()],
            to: "run",
            expectedVersion: 0
        )

        await XCTAssertThrowsErrorAsync {
            try await store.append(
                [graphTestNodeRegistered()],
                to: "run",
                expectedVersion: 0
            )
        } verify: {
            XCTAssertEqual(
                $0 as? GraphExecutionPersistenceError,
                .expectedVersionConflict(
                    runID: "run",
                    expected: 0,
                    actual: 1
                )
            )
        }
    }

    func testSQLiteExactDuplicateIsIdempotent() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let store = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let event = graphTestRunCreated()
        _ = try await store.append(
            [event],
            to: "run",
            expectedVersion: 0
        )

        let result = try await store.append(
            [event],
            to: "run",
            expectedVersion: 0
        )

        XCTAssertEqual(result.appendedCount, 0)
        XCTAssertEqual(result.deduplicatedCount, 1)
        XCTAssertEqual(result.newVersion, 1)
    }

    func testSnapshotPersistsAcrossStoreRestart() async throws {
        let fixture = try SQLiteStoreFixture()
        defer { fixture.remove() }
        let firstStore = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )
        let events = [
            graphTestRunCreated(),
            graphTestNodeRegistered(),
        ]
        let projection = try GraphExecutionProjector.replay(
            runID: "run",
            events: events
        ).projection
        let snapshot = GraphExecutionSnapshot(
            runID: "run",
            streamVersion: 2,
            graphDefinitionVersion: "1",
            graphDefinitionDigest: graphTestDigest,
            projectedState: projection,
            createdAt: graphTestTime.addingTimeInterval(10),
            createdBy: graphTestProducer,
            checkpointNamespace: "root"
        )
        try await firstStore.save(snapshot)
        let reopened = try SQLiteGraphExecutionStore(
            databasePath: fixture.path
        )

        let loaded = try await reopened.loadLatest(runID: "run")

        XCTAssertEqual(loaded, snapshot)
    }
}

struct SQLiteStoreFixture {
    let directory: URL
    let path: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "openisland-graph-store-\(UUID().uuidString)",
                isDirectory: true
            )
        path = directory.appendingPathComponent(
            "graph-execution.sqlite"
        ).path
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
