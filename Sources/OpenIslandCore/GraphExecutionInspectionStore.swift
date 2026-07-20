import Foundation

public struct GraphExecutionStreamDescriptor:
    Equatable,
    Codable,
    Sendable
{
    public let runID: String
    public let currentVersion: UInt64

    public init(runID: String, currentVersion: UInt64) {
        self.runID = runID
        self.currentVersion = currentVersion
    }
}

public struct GraphExecutionEventPage:
    Equatable,
    Sendable
{
    public let runID: String
    public let afterVersion: UInt64
    public let currentVersion: UInt64
    public let events: [GraphExecutionEventEnvelope]
    public let hasMore: Bool

    public init(
        runID: String,
        afterVersion: UInt64,
        currentVersion: UInt64,
        events: [GraphExecutionEventEnvelope],
        hasMore: Bool
    ) {
        self.runID = runID
        self.afterVersion = afterVersion
        self.currentVersion = currentVersion
        self.events = events
        self.hasMore = hasMore
    }

    public var nextAfterVersion: UInt64 {
        events.last?.streamSequence ?? afterVersion
    }
}

public protocol GraphExecutionReadStore: Sendable {
    func listStreams() async throws -> [GraphExecutionStreamDescriptor]

    func streamDescriptor(
        runID: String
    ) async throws -> GraphExecutionStreamDescriptor?

    func readPage(
        runID: String,
        afterVersion: UInt64,
        limit: Int
    ) async throws -> GraphExecutionEventPage
}

public protocol GraphExecutionSnapshotReadStore: Sendable {
    func loadLatest(
        runID: String,
        throughVersion: UInt64
    ) async throws -> GraphExecutionSnapshot?
}

extension InMemoryGraphExecutionEventStore: GraphExecutionReadStore {
    public func listStreams() -> [GraphExecutionStreamDescriptor] {
        streams
            .map { runID, events in
                GraphExecutionStreamDescriptor(
                    runID: runID,
                    currentVersion: events.last?.streamSequence ?? 0
                )
            }
            .sorted { $0.runID < $1.runID }
    }

    public func streamDescriptor(
        runID: String
    ) -> GraphExecutionStreamDescriptor? {
        guard let events = streams[runID] else {
            return nil
        }

        return GraphExecutionStreamDescriptor(
            runID: runID,
            currentVersion: events.last?.streamSequence ?? 0
        )
    }

    public func readPage(
        runID: String,
        afterVersion: UInt64,
        limit: Int
    ) throws -> GraphExecutionEventPage {
        let pageLimit = max(1, min(limit, 10_000))
        let stream = streams[runID] ?? []
        let currentVersion = stream.last?.streamSequence ?? 0
        let events = Array(
            stream
                .lazy
                .filter { $0.streamSequence > afterVersion }
                .prefix(pageLimit)
        )

        if afterVersion < currentVersion {
            guard let first = events.first,
                  first.streamSequence == afterVersion + 1 else {
                throw GraphExecutionPersistenceError.corruptRecord(
                    "Run \(runID) has a gap after sequence \(afterVersion)."
                )
            }
        }

        let nextVersion = events.last?.streamSequence ?? afterVersion
        return GraphExecutionEventPage(
            runID: runID,
            afterVersion: afterVersion,
            currentVersion: currentVersion,
            events: events,
            hasMore: nextVersion < currentVersion
        )
    }
}

extension InMemoryGraphExecutionSnapshotStore:
    GraphExecutionSnapshotReadStore
{
    public func loadLatest(
        runID: String,
        throughVersion: UInt64
    ) -> GraphExecutionSnapshot? {
        snapshots[runID]?
            .filter { $0.streamVersion <= throughVersion }
            .max {
                if $0.streamVersion != $1.streamVersion {
                    return $0.streamVersion < $1.streamVersion
                }

                return $0.createdAt < $1.createdAt
            }
    }
}
