import Foundation

public enum GraphExecutionPersistenceError: Error, Equatable, Sendable {
    case invalidRunID(expected: String, actual: String)
    case expectedVersionConflict(
        runID: String,
        expected: UInt64,
        actual: UInt64
    )
    case eventIDCollision(eventID: String)
    case sequenceGap(expected: UInt64, actual: UInt64)
    case sequenceConflict(runID: String, sequence: UInt64)
    case unsupportedSchemaVersion(
        artifact: String,
        found: Int,
        supported: Int
    )
    case corruptRecord(String)
    case storageFailure(String)
}

extension GraphExecutionPersistenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidRunID(expected, actual):
            return "Expected run \(expected), found \(actual)."
        case let .expectedVersionConflict(runID, expected, actual):
            return "Run \(runID) expected stream version \(expected), found \(actual)."
        case let .eventIDCollision(eventID):
            return "Event ID \(eventID) was reused with different content."
        case let .sequenceGap(expected, actual):
            return "Expected stream sequence \(expected), found \(actual)."
        case let .sequenceConflict(runID, sequence):
            return "Run \(runID) already contains a different event at sequence \(sequence)."
        case let .unsupportedSchemaVersion(artifact, found, supported):
            return "\(artifact) schema version \(found) exceeds supported version \(supported)."
        case let .corruptRecord(message):
            return "Corrupt graph execution record: \(message)"
        case let .storageFailure(message):
            return "Graph execution storage failed: \(message)"
        }
    }
}

public struct GraphExecutionAppendResult: Equatable, Sendable {
    public let previousVersion: UInt64
    public let newVersion: UInt64
    public let appendedCount: Int
    public let deduplicatedCount: Int

    public init(
        previousVersion: UInt64,
        newVersion: UInt64,
        appendedCount: Int,
        deduplicatedCount: Int
    ) {
        self.previousVersion = previousVersion
        self.newVersion = newVersion
        self.appendedCount = appendedCount
        self.deduplicatedCount = deduplicatedCount
    }
}

public struct GraphExecutionEventStream: Equatable, Sendable {
    public let runID: String
    public let afterVersion: UInt64
    public let currentVersion: UInt64
    public let events: [GraphExecutionEventEnvelope]

    public init(
        runID: String,
        afterVersion: UInt64,
        currentVersion: UInt64,
        events: [GraphExecutionEventEnvelope]
    ) {
        self.runID = runID
        self.afterVersion = afterVersion
        self.currentVersion = currentVersion
        self.events = events
    }
}

public protocol GraphExecutionEventStore: Sendable {
    func append(
        _ events: [GraphExecutionEventEnvelope],
        to runID: String,
        expectedVersion: UInt64
    ) async throws -> GraphExecutionAppendResult

    func read(
        runID: String,
        afterVersion: UInt64
    ) async throws -> GraphExecutionEventStream
}

public actor InMemoryGraphExecutionEventStore:
    GraphExecutionEventStore
{
    package var streams: [String: [GraphExecutionEventEnvelope]] = [:]
    private var eventsByID: [String: GraphExecutionEventEnvelope] = [:]

    public init() {}

    public func append(
        _ events: [GraphExecutionEventEnvelope],
        to runID: String,
        expectedVersion: UInt64
    ) throws -> GraphExecutionAppendResult {
        let normalized = try Self.normalize(events)
        let current = streams[runID] ?? []
        let currentVersion = current.last?.streamSequence ?? 0

        for event in normalized where event.runID != runID {
            throw GraphExecutionPersistenceError.invalidRunID(
                expected: runID,
                actual: event.runID
            )
        }

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

            if let existing = eventsByID[event.id],
               existing != event {
                throw GraphExecutionPersistenceError.eventIDCollision(
                    eventID: event.id
                )
            }
        }

        let newEvents = normalized.filter {
            eventsByID[$0.id] == nil
        }
        let duplicateCount = events.count - newEvents.count

        if newEvents.isEmpty {
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
                if current.contains(where: {
                    $0.streamSequence == event.streamSequence
                }) {
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

            expectedSequence += 1
        }

        var updated = current
        updated.append(contentsOf: newEvents)
        streams[runID] = updated

        for event in newEvents {
            eventsByID[event.id] = event
        }

        return GraphExecutionAppendResult(
            previousVersion: currentVersion,
            newVersion: updated.last?.streamSequence ?? currentVersion,
            appendedCount: newEvents.count,
            deduplicatedCount: duplicateCount
        )
    }

    public func read(
        runID: String,
        afterVersion: UInt64
    ) throws -> GraphExecutionEventStream {
        let stream = streams[runID] ?? []
        let currentVersion = stream.last?.streamSequence ?? 0
        let events = stream.filter {
            $0.streamSequence > afterVersion
        }

        if afterVersion < currentVersion,
           let first = events.first,
           first.streamSequence != afterVersion + 1 {
            throw GraphExecutionPersistenceError.corruptRecord(
                "Run \(runID) has a gap after sequence \(afterVersion)."
            )
        }

        return GraphExecutionEventStream(
            runID: runID,
            afterVersion: afterVersion,
            currentVersion: currentVersion,
            events: events
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
}
