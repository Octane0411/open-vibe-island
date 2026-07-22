import CryptoKit
import Foundation

public enum GraphMutationStatus: String, Codable, Sendable {
    case proposed
    case applied
    case deduplicated
}

public struct GraphMutationReport: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let operation: String
    public let status: GraphMutationStatus
    public let runID: String
    public let nodeIDs: [String]
    public let previousVersion: UInt64
    public let streamVersion: UInt64
    public let eventTypes: [String]
    public let executorInvocationCount: Int

    public init(
        schemaVersion: Int = GraphCLIOutputSchema.currentVersion,
        operation: String,
        status: GraphMutationStatus,
        runID: String,
        nodeIDs: [String] = [],
        previousVersion: UInt64,
        streamVersion: UInt64,
        eventTypes: [String],
        executorInvocationCount: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.operation = operation
        self.status = status
        self.runID = runID
        self.nodeIDs = nodeIDs.sorted()
        self.previousVersion = previousVersion
        self.streamVersion = streamVersion
        self.eventTypes = eventTypes
        self.executorInvocationCount = executorInvocationCount
    }
}

public enum GraphMutationError: Error, Equatable, Sendable {
    case invalidRequest(String)
    case notFound(String)
    case optimisticConflict(expected: UInt64, actual: UInt64)
    case idempotencyConflict(String)
    case policyDenied(String)
    case persistence(String)
}

extension GraphMutationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidRequest(message):
            "Invalid graph mutation: \(message)"
        case let .notFound(runID):
            "Graph run \(runID) was not found."
        case let .optimisticConflict(expected, actual):
            "Expected stream version \(expected), found \(actual)."
        case let .idempotencyConflict(key):
            "Idempotency key \(key) was reused for conflicting content."
        case let .policyDenied(message):
            "Graph mutation denied by policy: \(message)"
        case let .persistence(message):
            "Graph mutation persistence failed: \(message)"
        }
    }
}

public struct GraphCreateRequest: Equatable, Sendable {
    public let runID: String
    public let definition: GraphExecutableDefinition
    public let idempotencyKey: String
    public let expectedVersion: UInt64?
    public let dryRun: Bool
    public let occurredAt: Date
    public let producer: GraphExecutionProducer

    public init(
        runID: String,
        definition: GraphExecutableDefinition,
        idempotencyKey: String,
        expectedVersion: UInt64? = nil,
        dryRun: Bool = false,
        occurredAt: Date,
        producer: GraphExecutionProducer
    ) {
        self.runID = runID
        self.definition = definition
        self.idempotencyKey = idempotencyKey
        self.expectedVersion = expectedVersion
        self.dryRun = dryRun
        self.occurredAt = occurredAt
        self.producer = producer
    }
}

public struct GraphStartRequest: Equatable, Sendable {
    public let runID: String
    public let idempotencyKey: String
    public let expectedVersion: UInt64?
    public let requestedBy: String
    public let dryRun: Bool
    public let occurredAt: Date
    public let producer: GraphExecutionProducer

    public init(
        runID: String,
        idempotencyKey: String,
        expectedVersion: UInt64? = nil,
        requestedBy: String,
        dryRun: Bool = false,
        occurredAt: Date,
        producer: GraphExecutionProducer
    ) {
        self.runID = runID
        self.idempotencyKey = idempotencyKey
        self.expectedVersion = expectedVersion
        self.requestedBy = requestedBy
        self.dryRun = dryRun
        self.occurredAt = occurredAt
        self.producer = producer
    }
}

public struct GraphRetryMutationRequest: Equatable, Sendable {
    public let runID: String
    public let nodeID: String
    public let idempotencyKey: String
    public let expectedVersion: UInt64?
    public let requestedBy: String
    public let dryRun: Bool
    public let occurredAt: Date
    public let producer: GraphExecutionProducer

    public init(
        runID: String,
        nodeID: String,
        idempotencyKey: String,
        expectedVersion: UInt64? = nil,
        requestedBy: String,
        dryRun: Bool = false,
        occurredAt: Date,
        producer: GraphExecutionProducer
    ) {
        self.runID = runID
        self.nodeID = nodeID
        self.idempotencyKey = idempotencyKey
        self.expectedVersion = expectedVersion
        self.requestedBy = requestedBy
        self.dryRun = dryRun
        self.occurredAt = occurredAt
        self.producer = producer
    }
}

public struct GraphCancelMutationRequest: Equatable, Sendable {
    public let runID: String
    public let nodeID: String?
    public let idempotencyKey: String
    public let expectedVersion: UInt64?
    public let requestedBy: String
    public let reason: String?
    public let dryRun: Bool
    public let occurredAt: Date
    public let producer: GraphExecutionProducer

    public init(
        runID: String,
        nodeID: String? = nil,
        idempotencyKey: String,
        expectedVersion: UInt64? = nil,
        requestedBy: String,
        reason: String? = nil,
        dryRun: Bool = false,
        occurredAt: Date,
        producer: GraphExecutionProducer
    ) {
        self.runID = runID
        self.nodeID = nodeID
        self.idempotencyKey = idempotencyKey
        self.expectedVersion = expectedVersion
        self.requestedBy = requestedBy
        self.reason = reason
        self.dryRun = dryRun
        self.occurredAt = occurredAt
        self.producer = producer
    }
}

public protocol GraphMutating: Sendable {
    func create(_ request: GraphCreateRequest) async throws
        -> GraphMutationReport
    func start(_ request: GraphStartRequest) async throws
        -> GraphMutationReport
    func retry(_ request: GraphRetryMutationRequest) async throws
        -> GraphMutationReport
    func cancel(_ request: GraphCancelMutationRequest) async throws
        -> GraphMutationReport
}

public struct DefaultGraphMutationService: GraphMutating, Sendable {
    private let eventStore: any GraphExecutionEventStore
    private let readStore: any GraphExecutionReadStore

    public init(
        eventStore: any GraphExecutionEventStore,
        readStore: any GraphExecutionReadStore
    ) {
        self.eventStore = eventStore
        self.readStore = readStore
    }

    public func create(
        _ request: GraphCreateRequest
    ) async throws -> GraphMutationReport {
        guard !request.runID.isEmpty, !request.idempotencyKey.isEmpty else {
            throw GraphMutationError.invalidRequest(
                "run ID and idempotency key are required."
            )
        }
        try request.definition.validate()
        let fingerprint = try Self.fingerprint(request.definition)

        if let existing = try await findCreate(
            idempotencyKey: request.idempotencyKey
        ) {
            guard existing.runID == request.runID,
                  existing.fingerprint == fingerprint else {
                throw GraphMutationError.idempotencyConflict(
                    request.idempotencyKey
                )
            }
            return GraphMutationReport(
                operation: "graph.create",
                status: .deduplicated,
                runID: request.runID,
                nodeIDs: request.definition.scheduling.nodes.map(\.id),
                previousVersion: existing.streamVersion,
                streamVersion: existing.streamVersion,
                eventTypes: []
            )
        }

        let current = try await readStore.streamDescriptor(
            runID: request.runID
        )?.currentVersion ?? 0
        let expected = request.expectedVersion ?? 0
        guard current == expected else {
            throw GraphMutationError.optimisticConflict(
                expected: expected,
                actual: current
            )
        }
        guard current == 0 else {
            throw GraphMutationError.invalidRequest(
                "run ID already exists."
            )
        }
        let events = createEvents(request, fingerprint: fingerprint)
        if request.dryRun {
            return report(
                operation: "graph.create",
                status: .proposed,
                runID: request.runID,
                nodeIDs: request.definition.scheduling.nodes.map(\.id),
                previousVersion: current,
                streamVersion: current,
                events: events
            )
        }
        let append = try await append(
            events,
            runID: request.runID,
            expectedVersion: expected
        )
        return report(
            operation: "graph.create",
            status: .applied,
            runID: request.runID,
            nodeIDs: request.definition.scheduling.nodes.map(\.id),
            previousVersion: append.previousVersion,
            streamVersion: append.newVersion,
            events: events
        )
    }

    public func start(
        _ request: GraphStartRequest
    ) async throws -> GraphMutationReport {
        let loaded = try await load(request.runID)
        if let requestID = loaded.projection.runStartRequestID {
            let expectedID = Self.stableID(
                "start|\(request.idempotencyKey)"
            )
            guard requestID == expectedID else {
                return GraphMutationReport(
                    operation: "graph.start",
                    status: .deduplicated,
                    runID: request.runID,
                    previousVersion: loaded.version,
                    streamVersion: loaded.version,
                    eventTypes: []
                )
            }
            return GraphMutationReport(
                operation: "graph.start",
                status: .deduplicated,
                runID: request.runID,
                previousVersion: loaded.version,
                streamVersion: loaded.version,
                eventTypes: []
            )
        }
        try requireExpected(request.expectedVersion, actual: loaded.version)
        guard loaded.projection.run?.state.isTerminal != true else {
            throw GraphMutationError.policyDenied(
                "terminal runs cannot be started."
            )
        }
        let requestID = Self.stableID("start|\(request.idempotencyKey)")
        let event = GraphExecutionEventEnvelope(
            id: "start-\(requestID)",
            runID: request.runID,
            streamSequence: loaded.version + 1,
            occurredAt: request.occurredAt,
            recordedAt: request.occurredAt,
            producer: request.producer,
            correlationID: requestID,
            payload: .runStartRequested(
                GraphRunStartRequestedPayload(
                    requestID: requestID,
                    clientIdempotencyKey: request.idempotencyKey,
                    requestedBy: request.requestedBy
                )
            )
        )
        if request.dryRun {
            return report(
                operation: "graph.start",
                status: .proposed,
                runID: request.runID,
                previousVersion: loaded.version,
                streamVersion: loaded.version,
                events: [event]
            )
        }
        let append = try await append(
            [event],
            runID: request.runID,
            expectedVersion: loaded.version
        )
        return report(
            operation: "graph.start",
            status: .applied,
            runID: request.runID,
            previousVersion: append.previousVersion,
            streamVersion: append.newVersion,
            events: [event]
        )
    }

    public func retry(
        _ request: GraphRetryMutationRequest
    ) async throws -> GraphMutationReport {
        let loaded = try await load(request.runID)
        try requireExpected(request.expectedVersion, actual: loaded.version)
        let requestID = Self.stableID("retry|\(request.idempotencyKey)")
        if loaded.projection.retryRequestIDs.contains(requestID) {
            return GraphMutationReport(
                operation: "graph.retry",
                status: .deduplicated,
                runID: request.runID,
                nodeIDs: [request.nodeID],
                previousVersion: loaded.version,
                streamVersion: loaded.version,
                eventTypes: []
            )
        }
        guard let definition = loaded.projection.executableDefinition,
              definition.scheduling.nodes.contains(where: {
                $0.id == request.nodeID
              }) else {
            throw GraphMutationError.invalidRequest(
                "node \(request.nodeID) is not executable."
            )
        }
        guard let latest = loaded.projection.attempts
            .filter({ $0.nodeID == request.nodeID })
            .max(by: { $0.ordinal < $1.ordinal }),
            [.failed, .interrupted, .orphaned].contains(latest.state)
        else {
            throw GraphMutationError.policyDenied(
                "retry requires a failed, interrupted, or orphaned attempt."
            )
        }
        let policy = definition.schedulerPolicy.retryPolicy
        let category = latest.statusReason ?? "execution_failure"
        guard latest.ordinal < policy.maximumAttempts,
              !policy.nonRetryableFailureCategories.contains(category),
              policy.retryableFailureCategories.isEmpty
                || policy.retryableFailureCategories.contains(category)
        else {
            throw GraphMutationError.policyDenied(
                "retry policy does not permit category \(category)."
            )
        }
        let event = GraphExecutionEventEnvelope(
            id: "retry-request-\(requestID)",
            runID: request.runID,
            nodeID: request.nodeID,
            attemptID: latest.id,
            streamSequence: loaded.version + 1,
            occurredAt: request.occurredAt,
            recordedAt: request.occurredAt,
            producer: request.producer,
            correlationID: requestID,
            payload: .retryRequested(
                GraphRetryRequestedPayload(
                    requestID: requestID,
                    clientIdempotencyKey: request.idempotencyKey,
                    requestedBy: request.requestedBy
                )
            )
        )
        if request.dryRun {
            return report(
                operation: "graph.retry",
                status: .proposed,
                runID: request.runID,
                nodeIDs: [request.nodeID],
                previousVersion: loaded.version,
                streamVersion: loaded.version,
                events: [event]
            )
        }
        let append = try await append(
            [event],
            runID: request.runID,
            expectedVersion: loaded.version
        )
        return report(
            operation: "graph.retry",
            status: .applied,
            runID: request.runID,
            nodeIDs: [request.nodeID],
            previousVersion: append.previousVersion,
            streamVersion: append.newVersion,
            events: [event]
        )
    }

    public func cancel(
        _ request: GraphCancelMutationRequest
    ) async throws -> GraphMutationReport {
        let loaded = try await load(request.runID)
        try requireExpected(request.expectedVersion, actual: loaded.version)
        guard loaded.projection.run?.state.isTerminal != true else {
            throw GraphMutationError.policyDenied(
                "terminal runs cannot be cancelled."
            )
        }
        let candidates = loaded.projection.nodes.filter { node in
            request.nodeID == nil || request.nodeID == node.id
        }
        guard !candidates.isEmpty else {
            throw GraphMutationError.invalidRequest(
                "cancellation node was not found."
            )
        }
        let latestByNode = Dictionary(
            grouping: loaded.projection.attempts,
            by: \.nodeID
        ).mapValues { attempts in
            attempts.max { $0.ordinal < $1.ordinal }!
        }
        let activeClaimByNode = Dictionary(
            uniqueKeysWithValues: loaded.projection.scheduling.claims
                .filter { $0.status == .active }
                .map { ($0.claim.nodeID, $0.claim) }
        )
        var events: [GraphExecutionEventEnvelope] = []
        for node in candidates.sorted(by: { $0.id < $1.id }) {
            let attempt = latestByNode[node.id]
            if attempt?.state.isTerminal == true {
                continue
            }
            let requestID = Self.stableID(
                "cancel|\(request.idempotencyKey)|\(node.id)"
            )
            if loaded.projection.scheduling.cancellations.contains(
                where: { $0.id == requestID }
            ) {
                continue
            }
            let claim = activeClaimByNode[node.id]
            let cancellation = GraphCancellationRecord(
                requestID: requestID,
                runID: request.runID,
                nodeID: node.id,
                attemptID: attempt?.id,
                claimID: claim?.id,
                requestedBy: request.requestedBy,
                requestedAt: request.occurredAt,
                reason: request.reason
            )
            events.append(
                GraphExecutionEventEnvelope(
                    id: "cancellation-request-\(requestID)",
                    runID: request.runID,
                    nodeID: node.id,
                    attemptID: attempt?.id,
                    streamSequence: loaded.version
                        + UInt64(events.count) + 1,
                    occurredAt: request.occurredAt,
                    recordedAt: request.occurredAt,
                    producer: request.producer,
                    correlationID: requestID,
                    payload: .cancellationRequested(
                        GraphCancellationRequestedPayload(
                            cancellation: cancellation
                        )
                    )
                )
            )
        }
        if events.isEmpty {
            return GraphMutationReport(
                operation: "graph.cancel",
                status: .deduplicated,
                runID: request.runID,
                nodeIDs: candidates.map(\.id),
                previousVersion: loaded.version,
                streamVersion: loaded.version,
                eventTypes: []
            )
        }
        if request.dryRun {
            return report(
                operation: "graph.cancel",
                status: .proposed,
                runID: request.runID,
                nodeIDs: candidates.map(\.id),
                previousVersion: loaded.version,
                streamVersion: loaded.version,
                events: events
            )
        }
        let append = try await append(
            events,
            runID: request.runID,
            expectedVersion: loaded.version
        )
        return report(
            operation: "graph.cancel",
            status: .applied,
            runID: request.runID,
            nodeIDs: candidates.map(\.id),
            previousVersion: append.previousVersion,
            streamVersion: append.newVersion,
            events: events
        )
    }

    private struct Loaded {
        let version: UInt64
        let projection: GraphExecutionProjection
    }

    private struct ExistingCreate {
        let runID: String
        let fingerprint: GraphContentDigest?
        let streamVersion: UInt64
    }

    private func load(_ runID: String) async throws -> Loaded {
        let stream: GraphExecutionEventStream
        do {
            stream = try await eventStore.read(
                runID: runID,
                afterVersion: 0
            )
        } catch {
            throw GraphMutationError.persistence(error.localizedDescription)
        }
        guard !stream.events.isEmpty else {
            throw GraphMutationError.notFound(runID)
        }
        do {
            return Loaded(
                version: stream.currentVersion,
                projection: try GraphExecutionProjector.replay(
                    runID: runID,
                    events: stream.events
                ).projection
            )
        } catch {
            throw GraphMutationError.persistence(error.localizedDescription)
        }
    }

    private func findCreate(
        idempotencyKey: String
    ) async throws -> ExistingCreate? {
        do {
            for descriptor in try await readStore.listStreams() {
                let page = try await readStore.readPage(
                    runID: descriptor.runID,
                    afterVersion: 0,
                    limit: 1
                )
                guard let event = page.events.first,
                      case let .runCreated(payload) = event.payload,
                      payload.clientIdempotencyKey == idempotencyKey else {
                    continue
                }
                return ExistingCreate(
                    runID: descriptor.runID,
                    fingerprint: payload.requestFingerprint,
                    streamVersion: descriptor.currentVersion
                )
            }
            return nil
        } catch {
            throw GraphMutationError.persistence(error.localizedDescription)
        }
    }

    private func createEvents(
        _ request: GraphCreateRequest,
        fingerprint: GraphContentDigest
    ) -> [GraphExecutionEventEnvelope] {
        let scheduling = request.definition.scheduling
        var events = [
            GraphExecutionEventEnvelope(
                id: "create-\(Self.stableID(request.idempotencyKey))",
                runID: request.runID,
                streamSequence: 1,
                occurredAt: request.occurredAt,
                recordedAt: request.occurredAt,
                producer: request.producer,
                correlationID: request.idempotencyKey,
                payload: .runCreated(
                    GraphRunCreatedPayload(
                        graphID: scheduling.graphID,
                        graphDefinitionVersion: scheduling.version,
                        graphDefinitionDigest: scheduling.digest,
                        nodeIDs: scheduling.nodes.map(\.id),
                        clientIdempotencyKey: request.idempotencyKey,
                        requestFingerprint: fingerprint,
                        executableDefinition: request.definition
                    )
                )
            ),
        ]
        for node in scheduling.nodes {
            events.append(
                GraphExecutionEventEnvelope(
                    id: "create-node-\(Self.stableID("\(request.runID)|\(node.id)"))",
                    runID: request.runID,
                    nodeID: node.id,
                    streamSequence: UInt64(events.count + 1),
                    occurredAt: request.occurredAt,
                    recordedAt: request.occurredAt,
                    producer: request.producer,
                    correlationID: request.idempotencyKey,
                    payload: .nodeRegistered(
                        GraphNodeRegisteredPayload(
                            title: node.title,
                            dependencyNodeIDs: node.dependencyNodeIDs,
                            definitionVersion: scheduling.version
                        )
                    )
                )
            )
        }
        return events
    }

    private func requireExpected(
        _ expected: UInt64?,
        actual: UInt64
    ) throws {
        guard expected == nil || expected == actual else {
            throw GraphMutationError.optimisticConflict(
                expected: expected!,
                actual: actual
            )
        }
    }

    private func append(
        _ events: [GraphExecutionEventEnvelope],
        runID: String,
        expectedVersion: UInt64
    ) async throws -> GraphExecutionAppendResult {
        do {
            return try await eventStore.append(
                events,
                to: runID,
                expectedVersion: expectedVersion
            )
        } catch let error as GraphExecutionPersistenceError {
            switch error {
            case let .expectedVersionConflict(_, expected, actual):
                throw GraphMutationError.optimisticConflict(
                    expected: expected,
                    actual: actual
                )
            case .eventIDCollision:
                throw GraphMutationError.idempotencyConflict(
                    events.first?.correlationID ?? "unknown"
                )
            default:
                throw GraphMutationError.persistence(
                    error.localizedDescription
                )
            }
        } catch {
            throw GraphMutationError.persistence(error.localizedDescription)
        }
    }

    private func report(
        operation: String,
        status: GraphMutationStatus,
        runID: String,
        nodeIDs: [String] = [],
        previousVersion: UInt64,
        streamVersion: UInt64,
        events: [GraphExecutionEventEnvelope]
    ) -> GraphMutationReport {
        GraphMutationReport(
            operation: operation,
            status: status,
            runID: runID,
            nodeIDs: nodeIDs,
            previousVersion: previousVersion,
            streamVersion: streamVersion,
            eventTypes: events.map(\.eventType)
        )
    }

    private static func fingerprint(
        _ definition: GraphExecutableDefinition
    ) throws -> GraphContentDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(definition)
        return GraphContentDigest(
            algorithm: "sha256",
            value: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }

    package static func stableID(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(24)
            .description
    }
}
