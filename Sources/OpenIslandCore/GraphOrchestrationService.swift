import Foundation

public enum GraphOrchestrationCycleStatus:
    String,
    Codable,
    Sendable
{
    case proposed
    case progressed
    case terminal
    case waitingForCancellation = "waiting_for_cancellation"
    case stalled
    case adapterUnavailable = "adapter_unavailable"
    case cycleLimitReached = "cycle_limit_reached"
}

public struct GraphOrchestrationCycleReport:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let runID: String
    public let status: GraphOrchestrationCycleStatus
    public let logicalTime: Date
    public let previousVersion: UInt64
    public let streamVersion: UInt64
    public let schedulerEvaluationID: String?
    public let claimedNodeID: String?
    public let claimID: String?
    public let executorOperation: GraphExecutorOperation?
    public let executorStatus: GraphExecutorResponseStatus?
    public let proposedEventTypes: [String]
    public let persistedEventCount: Int
    public let executorInvocationCount: Int
    public let runState: ReconciledExecutionState
    public let policyDenials: [GraphSchedulingReasonCode]

    public init(
        schemaVersion: Int = GraphCLIOutputSchema.currentVersion,
        runID: String,
        status: GraphOrchestrationCycleStatus,
        logicalTime: Date,
        previousVersion: UInt64,
        streamVersion: UInt64,
        schedulerEvaluationID: String? = nil,
        claimedNodeID: String? = nil,
        claimID: String? = nil,
        executorOperation: GraphExecutorOperation? = nil,
        executorStatus: GraphExecutorResponseStatus? = nil,
        proposedEventTypes: [String] = [],
        persistedEventCount: Int = 0,
        executorInvocationCount: Int = 0,
        runState: ReconciledExecutionState,
        policyDenials: [GraphSchedulingReasonCode] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.logicalTime = logicalTime
        self.previousVersion = previousVersion
        self.streamVersion = streamVersion
        self.schedulerEvaluationID = schedulerEvaluationID
        self.claimedNodeID = claimedNodeID
        self.claimID = claimID
        self.executorOperation = executorOperation
        self.executorStatus = executorStatus
        self.proposedEventTypes = proposedEventTypes
        self.persistedEventCount = persistedEventCount
        self.executorInvocationCount = executorInvocationCount
        self.runState = runState
        self.policyDenials = policyDenials.sorted {
            $0.rawValue < $1.rawValue
        }
    }

    public var madeProgress: Bool {
        persistedEventCount > 0 || executorInvocationCount > 0
    }
}

public struct GraphOrchestrationRunReport:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let runID: String
    public let status: GraphOrchestrationCycleStatus
    public let cycles: [GraphOrchestrationCycleReport]
    public let finalVersion: UInt64
    public let finalState: ReconciledExecutionState

    public init(
        schemaVersion: Int = GraphCLIOutputSchema.currentVersion,
        runID: String,
        status: GraphOrchestrationCycleStatus,
        cycles: [GraphOrchestrationCycleReport],
        finalVersion: UInt64,
        finalState: ReconciledExecutionState
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.status = status
        self.cycles = cycles
        self.finalVersion = finalVersion
        self.finalState = finalState
    }
}

public struct GraphOrchestrationStepRequest: Equatable, Sendable {
    public let runID: String
    public let logicalTime: Date
    public let expectedVersion: UInt64?
    public let dryRun: Bool

    public init(
        runID: String,
        logicalTime: Date,
        expectedVersion: UInt64? = nil,
        dryRun: Bool = false
    ) {
        self.runID = runID
        self.logicalTime = logicalTime
        self.expectedVersion = expectedVersion
        self.dryRun = dryRun
    }
}

public struct GraphOrchestrationRunRequest: Equatable, Sendable {
    public let runID: String
    public let cycleLimit: Int
    public let expectedVersion: UInt64?
    public let dryRun: Bool
    public let logicalTime: Date?

    public init(
        runID: String,
        cycleLimit: Int,
        expectedVersion: UInt64? = nil,
        dryRun: Bool = false,
        logicalTime: Date? = nil
    ) {
        self.runID = runID
        self.cycleLimit = max(1, cycleLimit)
        self.expectedVersion = expectedVersion
        self.dryRun = dryRun
        self.logicalTime = logicalTime
    }
}

public enum GraphOrchestrationError: Error, Equatable, Sendable {
    case notFound(String)
    case invalidDefinition(String)
    case optimisticConflict(expected: UInt64, actual: UInt64)
    case staleExecutor(GraphExecutorFencingReason)
    case adapterUnavailable(String)
    case persistence(String)
}

extension GraphOrchestrationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notFound(runID):
            "Graph run \(runID) was not found."
        case let .invalidDefinition(message):
            "Graph execution definition is invalid: \(message)"
        case let .optimisticConflict(expected, actual):
            "Expected stream version \(expected), found \(actual)."
        case let .staleExecutor(reason):
            "Executor fencing rejected the operation: \(reason.rawValue)."
        case let .adapterUnavailable(message):
            "Executor adapter is unavailable: \(message)"
        case let .persistence(message):
            "Graph orchestration persistence failed: \(message)"
        }
    }
}

public protocol GraphOrchestrationClock: Sendable {
    func now() -> Date
}

public struct SystemGraphOrchestrationClock:
    GraphOrchestrationClock,
    Sendable
{
    public init() {}
    public func now() -> Date { Date() }
}

public protocol GraphExecutionConfirmationPolicy: Sendable {
    func permits(
        operation: GraphExecutorOperation,
        context: GraphExecutorCommandContext
    ) -> Bool
}

public struct DeterministicExecutionConfirmationPolicy:
    GraphExecutionConfirmationPolicy,
    Sendable
{
    public init() {}

    public func permits(
        operation: GraphExecutorOperation,
        context: GraphExecutorCommandContext
    ) -> Bool {
        context.specification.adapterKind == "deterministic"
    }
}

public protocol GraphOrchestrating: Sendable {
    func step(_ request: GraphOrchestrationStepRequest) async throws
        -> GraphOrchestrationCycleReport
    func run(_ request: GraphOrchestrationRunRequest) async throws
        -> GraphOrchestrationRunReport
}

public enum GraphArtifactInputResolver {
    public static func resolve(
        nodeID: String,
        definition: GraphExecutableDefinition,
        projection: GraphExecutionProjection
    ) throws -> [GraphArtifactReference] {
        guard let execution = definition.execution(for: nodeID),
              let node = definition.scheduling.nodes.first(where: {
                $0.id == nodeID
              }) else {
            throw GraphOrchestrationError.invalidDefinition(
                "node \(nodeID) is missing."
            )
        }
        let ancestorIDs = ancestors(
            of: node,
            nodes: definition.scheduling.nodes
        )
        let roles = Set(execution.inputArtifactRoles.map(\.rawValue))
        return try projection.artifacts.filter { artifact in
            guard ancestorIDs.contains(artifact.producingNodeID),
                  roles.contains(artifact.logicalRole) else {
                return false
            }
            guard artifact.producingRunID == projection.runID,
                  let ordinal = artifact.producingAttemptOrdinal,
                  let claimID = artifact.producingClaimID,
                  projection.attempts.contains(where: {
                    $0.id == artifact.producingAttemptID
                        && $0.nodeID == artifact.producingNodeID
                        && $0.ordinal == ordinal
                        && $0.state == .completed
                  }),
                  projection.scheduling.claims.contains(where: {
                    $0.claim.id == claimID
                        && $0.claim.nodeID == artifact.producingNodeID
                        && $0.claim.attemptOrdinal == ordinal
                  }) else {
                throw GraphOrchestrationError.invalidDefinition(
                    "artifact \(artifact.id) has invalid provenance."
                )
            }
            return true
        }.sorted { $0.id < $1.id }
    }

    private static func ancestors(
        of node: GraphSchedulingDefinitionNode,
        nodes: [GraphSchedulingDefinitionNode]
    ) -> Set<String> {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var result = Set<String>()
        var pending = node.dependencyNodeIDs
        while let next = pending.popLast() {
            guard result.insert(next).inserted else { continue }
            pending.append(contentsOf: byID[next]?.dependencyNodeIDs ?? [])
        }
        return result
    }
}

public struct DefaultGraphOrchestrationService:
    GraphOrchestrating,
    Sendable
{
    private let eventStore: any GraphExecutionEventStore
    private let schedulingRepository: any GraphSchedulingRepository
    private let executorRepository: any GraphExecutorPersisting
    private let executor: any GraphExecutorAdapter
    private let confirmationPolicy: any GraphExecutionConfirmationPolicy
    private let clock: any GraphOrchestrationClock
    private let producer: GraphExecutionProducer

    public init(
        eventStore: any GraphExecutionEventStore,
        schedulingRepository: any GraphSchedulingRepository,
        executorRepository: any GraphExecutorPersisting,
        executor: any GraphExecutorAdapter,
        confirmationPolicy: any GraphExecutionConfirmationPolicy =
            DeterministicExecutionConfirmationPolicy(),
        clock: any GraphOrchestrationClock =
            SystemGraphOrchestrationClock(),
        producer: GraphExecutionProducer = GraphExecutionProducer(
            id: "openisland.orchestrator",
            kind: .application
        )
    ) {
        self.eventStore = eventStore
        self.schedulingRepository = schedulingRepository
        self.executorRepository = executorRepository
        self.executor = executor
        self.confirmationPolicy = confirmationPolicy
        self.clock = clock
        self.producer = producer
    }

    public func step(
        _ request: GraphOrchestrationStepRequest
    ) async throws -> GraphOrchestrationCycleReport {
        let initial = try await load(request.runID)
        if let expected = request.expectedVersion,
           expected != initial.version {
            throw GraphOrchestrationError.optimisticConflict(
                expected: expected,
                actual: initial.version
            )
        }
        guard let definition = initial.projection.executableDefinition else {
            throw GraphOrchestrationError.invalidDefinition(
                "run has no durable executable definition."
            )
        }
        try definition.validate()
        if initial.projection.run?.state.isTerminal == true {
            return report(
                loaded: initial,
                initialVersion: initial.version,
                status: .terminal,
                logicalTime: request.logicalTime
            )
        }
        guard initial.projection.runStartRequestedAt != nil else {
            return report(
                loaded: initial,
                initialVersion: initial.version,
                status: .stalled,
                logicalTime: request.logicalTime,
                denials: [.runNotStarted]
            )
        }
        if request.dryRun {
            return try dryRunReport(
                loaded: initial,
                definition: definition,
                logicalTime: request.logicalTime
            )
        }

        if let cancellation = pendingUnclaimedCancellation(
            initial.projection
        ) {
            let result = try await schedulingRepository
                .declareCancellationTerminal(
                    GraphCancellationTerminalRequest(
                        runID: request.runID,
                        requestID: cancellation.id,
                        expectedVersion: initial.version,
                        logicalTime: request.logicalTime,
                        reason: cancellation.reason,
                        producer: producer,
                        recordedAt: request.logicalTime
                    )
                )
            let loaded = try await load(request.runID)
            let terminal = try await recordRunTerminalIfJustified(
                loaded: loaded,
                definition: definition,
                logicalTime: request.logicalTime
            )
            return report(
                loaded: terminal,
                initialVersion: initial.version,
                status: terminal.projection.run?.state.isTerminal == true
                    ? .terminal : .progressed,
                logicalTime: request.logicalTime,
                persistedCount: result.appendResult.appendedCount
                    + Int(terminal.version - loaded.version)
            )
        }

        var current = initial
        let evaluation = try await schedulingRepository.evaluateAndAppend(
            GraphSchedulerEvaluationRequest(
                runID: request.runID,
                expectedVersion: current.version,
                definition: definition.scheduling,
                policy: definition.schedulerPolicy,
                logicalTime: request.logicalTime,
                availableExecutors: [executor.capabilities],
                failureCategoriesByAttemptID: failureCategories(
                    current.projection
                ),
                producer: producer,
                recordedAt: request.logicalTime
            )
        )
        current = try await load(request.runID)
        let evaluationID = current.projection.scheduling.records.last(where: {
            $0.eventType == GraphExecutionEventType
                .schedulerCycleCompleted.rawValue
        })?.evaluationID
        var persisted = evaluation.appendResult.appendedCount

        if let terminal = try await terminalAfterScheduling(
            current,
            definition: definition,
            logicalTime: request.logicalTime
        ) {
            return report(
                loaded: terminal,
                initialVersion: initial.version,
                status: .terminal,
                logicalTime: request.logicalTime,
                evaluationID: evaluationID,
                persistedCount: persisted
                    + Int(terminal.version - current.version)
            )
        }

        var claim = current.projection.scheduling.activeClaim(
            nodeID: current.projection.scheduling.claims
                .filter { $0.status == .active }
                .map(\.claim.nodeID)
                .sorted().first ?? "",
            at: request.logicalTime
        )
        if claim == nil,
           let nodeID = claimableNode(
            projection: current.projection,
            evaluationID: evaluationID
           ), let evaluationID {
            let claimMaterial = [
                evaluationID,
                nodeID,
                executor.capabilities.executorID,
            ].joined(separator: "|")
            let claimDigest = DefaultGraphMutationService.stableID(
                claimMaterial
            )
            let claimID = "claim-\(claimDigest)"
            let durableEligibility = current.projection.scheduling.retries
                .filter { $0.nodeID == nodeID }
                .map(\.eligibleAt)
                .max() ?? request.logicalTime
            let claimLogicalTime = max(
                request.logicalTime,
                durableEligibility
            )
            let claimed = try await schedulingRepository.attemptClaim(
                GraphExecutorClaimRequest(
                    runID: request.runID,
                    nodeID: nodeID,
                    claimID: claimID,
                    executor: executor.capabilities,
                    evaluationID: evaluationID,
                    expectedVersion: current.version,
                    logicalTime: claimLogicalTime,
                    leaseDurationSeconds: definition.schedulerPolicy
                        .defaultLeaseDurationSeconds,
                    producer: producer,
                    recordedAt: claimLogicalTime
                )
            )
            persisted += claimed.appendResult.appendedCount
            current = try await load(request.runID)
            guard let grantedClaimID = claimed.claim?.id else {
                throw GraphOrchestrationError.persistence(
                    "claim grant did not return an executor claim."
                )
            }
            guard let persistedClaim = current.projection.scheduling.claims
                .first(where: {
                    $0.claim.id == grantedClaimID
                        && $0.status == .active
                })?.claim else {
                throw GraphOrchestrationError.persistence(
                    "granted executor claim is missing from durable history."
                )
            }
            claim = persistedClaim
        }

        guard var claim else {
            return report(
                loaded: current,
                initialVersion: initial.version,
                status: persisted > 0 ? .progressed : .stalled,
                logicalTime: request.logicalTime,
                evaluationID: evaluationID,
                persistedCount: persisted,
                denials: schedulingDenials(current.projection)
            )
        }
        if shouldRenew(
            claim: claim,
            logicalTime: request.logicalTime,
            leaseDurationSeconds: definition.schedulerPolicy
                .defaultLeaseDurationSeconds
        ) {
            let renewed = try await schedulingRepository.renewLease(
                GraphExecutorLeaseRenewalRequest(
                    runID: request.runID,
                    claimID: claim.id,
                    executorID: claim.executorID,
                    expectedGeneration: claim.leaseGeneration,
                    expectedVersion: current.version,
                    logicalTime: request.logicalTime,
                    leaseDurationSeconds: definition.schedulerPolicy
                        .defaultLeaseDurationSeconds,
                    producer: producer,
                    recordedAt: request.logicalTime
                )
            )
            persisted += renewed.appendResult.appendedCount
            current = try await load(request.runID)
            guard let renewedClaim = current.projection.scheduling.claims
                .first(where: {
                    $0.claim.id == claim.id && $0.status == .active
                })?.claim else {
                throw GraphOrchestrationError.persistence(
                    "renewed executor claim is not active."
                )
            }
            claim = renewedClaim
        }
        let execution = try executionContext(
            claim: claim,
            definition: definition,
            projection: current.projection,
            logicalTime: max(request.logicalTime, claim.leaseStart)
        )

        if let timeout = timeoutKind(
            context: execution,
            projection: current.projection
        ) {
            return try await timeOutExecution(
                kind: timeout,
                context: execution,
                initial: initial,
                current: current,
                definition: definition,
                evaluationID: evaluationID,
                persisted: persisted
            )
        }

        if let cancellation = current.projection.scheduling
            .pendingCancellation(nodeID: claim.nodeID),
           cancellation.state == .requested {
            return try await cancelClaimedExecution(
                cancellation: cancellation,
                context: execution,
                initial: initial,
                current: current,
                definition: definition,
                evaluationID: evaluationID,
                persisted: persisted
            )
        }

        return try await executeOneOperation(
            context: execution,
            initial: initial,
            current: current,
            definition: definition,
            evaluationID: evaluationID,
            persisted: persisted
        )
    }

    public func run(
        _ request: GraphOrchestrationRunRequest
    ) async throws -> GraphOrchestrationRunReport {
        var cycles: [GraphOrchestrationCycleReport] = []
        var expected = request.expectedVersion
        for _ in 0..<request.cycleLimit {
            let cycle = try await step(
                GraphOrchestrationStepRequest(
                    runID: request.runID,
                    logicalTime: request.logicalTime ?? clock.now(),
                    expectedVersion: expected,
                    dryRun: request.dryRun
                )
            )
            cycles.append(cycle)
            expected = nil
            if cycle.status == .terminal
                || cycle.status == .waitingForCancellation
                || cycle.status == .adapterUnavailable
                || !cycle.madeProgress
                || request.dryRun {
                return GraphOrchestrationRunReport(
                    runID: request.runID,
                    status: cycle.status,
                    cycles: cycles,
                    finalVersion: cycle.streamVersion,
                    finalState: cycle.runState
                )
            }
        }
        let last = cycles.last!
        return GraphOrchestrationRunReport(
            runID: request.runID,
            status: .cycleLimitReached,
            cycles: cycles,
            finalVersion: last.streamVersion,
            finalState: last.runState
        )
    }

    private struct Loaded {
        let version: UInt64
        let events: [GraphExecutionEventEnvelope]
        let projection: GraphExecutionProjection
    }

    private func load(_ runID: String) async throws -> Loaded {
        do {
            let stream = try await eventStore.read(
                runID: runID,
                afterVersion: 0
            )
            guard !stream.events.isEmpty else {
                throw GraphOrchestrationError.notFound(runID)
            }
            return Loaded(
                version: stream.currentVersion,
                events: stream.events,
                projection: try GraphExecutionProjector.replay(
                    runID: runID,
                    events: stream.events
                ).projection
            )
        } catch let error as GraphOrchestrationError {
            throw error
        } catch {
            throw GraphOrchestrationError.persistence(
                error.localizedDescription
            )
        }
    }

    private func dryRunReport(
        loaded: Loaded,
        definition: GraphExecutableDefinition,
        logicalTime: Date
    ) throws -> GraphOrchestrationCycleReport {
        guard let reconciled = GraphExecutionProjectionReconciler.reconcile(
                projection: loaded.projection,
                evidenceOutcome: .available(GraphProcessEvidence()),
                observedAt: logicalTime
        ) else {
            throw GraphOrchestrationError.invalidDefinition(
                "run projection cannot be reconciled."
            )
        }
        let decision = GraphScheduler.evaluate(
            GraphSchedulingInput(
                definition: definition.scheduling,
                projectedState: loaded.projection,
                reconciledState: reconciled,
                policy: definition.schedulerPolicy,
                logicalTime: logicalTime,
                availableExecutors: [executor.capabilities],
                failureCategoriesByAttemptID: failureCategories(
                    loaded.projection
                )
            )
        )
        let nodeID = decision.phasesByNodeID.keys.sorted().first {
            decision.phasesByNodeID[$0] == .claimable
        }
        var eventTypes = decision.proposedEvents.map {
            $0.payload.eventType
        }
        if nodeID != nil {
            eventTypes += [
                GraphExecutionEventType.executorClaimRequested.rawValue,
                GraphExecutionEventType.executorClaimGranted.rawValue,
                GraphExecutionEventType.attemptStarting.rawValue,
                GraphExecutionEventType.executorObservationRecorded.rawValue,
            ]
        }
        return GraphOrchestrationCycleReport(
            runID: loaded.projection.runID,
            status: .proposed,
            logicalTime: logicalTime,
            previousVersion: loaded.version,
            streamVersion: loaded.version,
            schedulerEvaluationID: decision.evaluationID,
            claimedNodeID: nodeID,
            executorOperation: nodeID == nil ? nil : .prepare,
            proposedEventTypes: eventTypes,
            runState: loaded.projection.run?.state ?? .pending,
            policyDenials: Array(decision.reasonsByNodeID.values)
                .filter { $0 != .dependenciesSatisfied }
        )
    }

    private func executeOneOperation(
        context: GraphExecutorCommandContext,
        initial: Loaded,
        current: Loaded,
        definition: GraphExecutableDefinition,
        evaluationID: String?,
        persisted: Int
    ) async throws -> GraphOrchestrationCycleReport {
        var current = current
        var persisted = persisted
        let lifecycle = current.projection.attemptLifecycles.first {
            $0.attemptID == context.identity.attemptID
        }
        let operation: GraphExecutorOperation
        let observation: GraphExecutorObservation
        var invocations = 0

        do {
            if lifecycle?.phase == .claimed || lifecycle?.phase == .created {
                let started = try await executorRepository.recordStartRequest(
                    GraphExecutorStartCommand(
                        identity: context.identity,
                        expectedVersion: current.version,
                        logicalTime: context.logicalTime,
                        producer: producer,
                        correlationID: context.correlation.correlationID
                    )
                )
                persisted += started.appendResult.appendedCount
                current = try await load(context.identity.runID)
                let prepared = try await invokePrepare(context)
                invocations += 1
                let persistedPrepare = try await persistObservation(
                    prepared,
                    current: current,
                    correlationID: context.correlation.correlationID
                )
                persisted += persistedPrepare.appendResult.appendedCount
                current = try await load(context.identity.runID)
                if prepared.status.isTerminalObservation {
                    operation = .prepare
                    observation = prepared
                } else {
                    let refreshed = try executionContext(
                        claim: currentClaim(context.identity, current.projection),
                        definition: definition,
                        projection: current.projection,
                        logicalTime: context.logicalTime
                    )
                    operation = .start
                    observation = try await invokeStart(refreshed)
                    invocations += 1
                }
            } else if lifecycle?.phase == .startRequested {
                operation = .recover
                observation = try await invokeRecover(context)
                invocations += 1
            } else {
                operation = .observe
                observation = try await invokeObserve(context)
                invocations += 1
            }
        } catch is GraphExecutorAdapterError {
            let loaded = try await load(context.identity.runID)
            return report(
                loaded: loaded,
                initialVersion: initial.version,
                status: .adapterUnavailable,
                logicalTime: context.logicalTime,
                evaluationID: evaluationID,
                claim: currentClaim(context.identity, loaded.projection),
                persistedCount: persisted,
                executorOperation: lifecycle?.phase == .startRequested
                    ? .recover : .start,
                executorInvocations: invocations + 1,
                denials: [],
                adapterStatus: .transientAdapterFailure
            )
        }
        let observationResult = try await persistObservation(
            observation,
            current: current,
            correlationID: context.correlation.correlationID
        )
        persisted += observationResult.appendResult.appendedCount
        current = try await load(context.identity.runID)

        if observation.status.isTerminalObservation {
            return try await finishTerminalObservation(
                observation,
                operation: operation,
                context: context,
                initial: initial,
                current: current,
                definition: definition,
                evaluationID: evaluationID,
                persisted: persisted,
                invocations: invocations
            )
        }
        return report(
            loaded: current,
            initialVersion: initial.version,
            status: .progressed,
            logicalTime: context.logicalTime,
            evaluationID: evaluationID,
            claim: currentClaim(context.identity, current.projection),
            persistedCount: persisted,
            executorOperation: operation,
            executorInvocations: invocations,
            adapterStatus: observation.status
        )
    }

    private func finishTerminalObservation(
        _ initialObservation: GraphExecutorObservation,
        operation: GraphExecutorOperation,
        context: GraphExecutorCommandContext,
        initial: Loaded,
        current: Loaded,
        definition: GraphExecutableDefinition,
        evaluationID: String?,
        persisted: Int,
        invocations: Int
    ) async throws -> GraphOrchestrationCycleReport {
        var current = current
        var persisted = persisted
        var invocations = invocations
        var terminalObservation = initialObservation
        let shouldCollectResult = initialObservation.status == .succeeded
            || (initialObservation.status == .failed
                && context.specification.adapterKind
                    == GraphLocalProcessSpecification.adapterKind)
        if shouldCollectResult,
           operation != .collectResult {
            let refreshed = try refreshedContext(context, loaded: current)
            terminalObservation = try await invokeCollect(refreshed)
            invocations += 1
            let result = try await persistObservation(
                terminalObservation,
                current: current,
                correlationID: context.correlation.correlationID
            )
            persisted += result.appendResult.appendedCount
            current = try await load(context.identity.runID)
        }
        let refreshed = try refreshedContext(context, loaded: current)
        let cleanup = try await invokeCleanup(refreshed)
        invocations += 1
        let cleanupResult = try await persistObservation(
            cleanup,
            current: current,
            correlationID: context.correlation.correlationID
        )
        persisted += cleanupResult.appendResult.appendedCount
        current = try await load(context.identity.runID)
        let state = terminalState(terminalObservation.status)
        let terminal = try await executorRepository.declareTerminal(
            GraphExecutorTerminalDeclaration(
                identity: context.identity,
                observationID: terminalObservation.id,
                state: state,
                reason: terminalObservation.failure?.category,
                expectedVersion: current.version,
                logicalTime: context.logicalTime,
                producer: producer,
                correlationID: context.correlation.correlationID
            )
        )
        persisted += terminal.appendResult.appendedCount
        current = try await load(context.identity.runID)
        let aggregate = try await recordRunTerminalIfJustified(
            loaded: current,
            definition: definition,
            logicalTime: context.logicalTime
        )
        persisted += Int(aggregate.version - current.version)
        return report(
            loaded: aggregate,
            initialVersion: initial.version,
            status: aggregate.projection.run?.state.isTerminal == true
                ? .terminal : .progressed,
            logicalTime: context.logicalTime,
            evaluationID: evaluationID,
            claim: nil,
            persistedCount: persisted,
            executorOperation: operation,
            executorInvocations: invocations,
            adapterStatus: terminalObservation.status
        )
    }

    private func cancelClaimedExecution(
        cancellation: GraphCancellationRecord,
        context: GraphExecutorCommandContext,
        initial: Loaded,
        current: Loaded,
        definition: GraphExecutableDefinition,
        evaluationID: String?,
        persisted: Int
    ) async throws -> GraphOrchestrationCycleReport {
        var current = current
        var persisted = persisted
        let observation = try await invokeCancellation(
            context,
            requestID: cancellation.id
        )
        let result = try await persistObservation(
            observation,
            current: current,
            correlationID: cancellation.id
        )
        persisted += result.appendResult.appendedCount
        current = try await load(context.identity.runID)
        guard observation.status == .cancelled else {
            return report(
                loaded: current,
                initialVersion: initial.version,
                status: .waitingForCancellation,
                logicalTime: context.logicalTime,
                evaluationID: evaluationID,
                claim: currentClaim(context.identity, current.projection),
                persistedCount: persisted,
                executorOperation: .requestCancellation,
                executorInvocations: 1,
                adapterStatus: observation.status
            )
        }
        let acknowledged = try await executorRepository
            .acknowledgeCancellation(
                GraphExecutorCancellationAcknowledgement(
                    identity: context.identity,
                    requestID: cancellation.id,
                    expectedVersion: current.version,
                    logicalTime: context.logicalTime,
                    producer: producer
                )
            )
        persisted += acknowledged.appendResult.appendedCount
        current = try await load(context.identity.runID)
        return try await finishTerminalObservation(
            observation,
            operation: .requestCancellation,
            context: context,
            initial: initial,
            current: current,
            definition: definition,
            evaluationID: evaluationID,
            persisted: persisted,
            invocations: 1
        )
    }

    private func timeOutExecution(
        kind: GraphTimeoutKind,
        context: GraphExecutorCommandContext,
        initial: Loaded,
        current: Loaded,
        definition: GraphExecutableDefinition,
        evaluationID: String?,
        persisted: Int
    ) async throws -> GraphOrchestrationCycleReport {
        let deadline = timeoutDeadline(
            kind: kind,
            context: context,
            projection: current.projection
        )
        let timeoutID = DefaultGraphMutationService.stableID(
            "\(context.identity.claimID)|\(kind.rawValue)|\(deadline.timeIntervalSince1970)"
        )
        let timeout = try await schedulingRepository.recordTimeout(
            GraphTimeoutCommandRequest(
                decision: GraphTimeoutDecision(
                    timeoutID: timeoutID,
                    runID: context.identity.runID,
                    nodeID: context.identity.nodeID,
                    attemptID: context.identity.attemptID,
                    claimID: context.identity.claimID,
                    kind: kind,
                    deadline: deadline,
                    declaredAt: context.logicalTime
                ),
                expectedVersion: current.version,
                producer: producer,
                recordedAt: context.logicalTime
            )
        )
        var persisted = persisted + timeout.appendResult.appendedCount
        var loaded = try await load(context.identity.runID)
        let observation = GraphExecutorObservation(
            id: "timeout-observation-\(timeoutID)",
            operation: .observe,
            identity: context.identity,
            status: .interrupted,
            observedAt: context.logicalTime,
            failure: GraphExecutorFailure(
                category: "timeout",
                retryable: true
            )
        )
        let observed = try await persistObservation(
            observation,
            current: loaded,
            correlationID: timeoutID
        )
        persisted += observed.appendResult.appendedCount
        loaded = try await load(context.identity.runID)
        return try await finishTerminalObservation(
            observation,
            operation: .observe,
            context: context,
            initial: initial,
            current: loaded,
            definition: definition,
            evaluationID: evaluationID,
            persisted: persisted,
            invocations: 0
        )
    }

    private func persistObservation(
        _ observation: GraphExecutorObservation,
        current: Loaded,
        correlationID: String
    ) async throws -> GraphExecutorPersistenceResult {
        do {
            return try await executorRepository.recordObservation(
                GraphExecutorObservationCommand(
                    observation: observation,
                    expectedVersion: current.version,
                    producer: producer,
                    correlationID: correlationID
                )
            )
        } catch let error as GraphExecutorRepositoryError {
            if case let .rejected(reason, _) = error {
                throw GraphOrchestrationError.staleExecutor(reason)
            }
            throw GraphOrchestrationError.persistence(
                error.localizedDescription
            )
        }
    }

    private func executionContext(
        claim: GraphExecutorClaim,
        definition: GraphExecutableDefinition,
        projection: GraphExecutionProjection,
        logicalTime: Date
    ) throws -> GraphExecutorCommandContext {
        guard let attempt = projection.attempts.first(where: {
            $0.nodeID == claim.nodeID
                && $0.ordinal == claim.attemptOrdinal
        }), let execution = definition.execution(for: claim.nodeID) else {
            throw GraphOrchestrationError.invalidDefinition(
                "claim target has no attempt or execution specification."
            )
        }
        let identity = GraphExecutorInteractionIdentity(
            runID: claim.runID,
            nodeID: claim.nodeID,
            attemptID: attempt.id,
            attemptOrdinal: attempt.ordinal,
            claimID: claim.id,
            leaseGeneration: claim.leaseGeneration,
            executorID: claim.executorID
        )
        let observations = projection.executorObservations.filter {
            $0.identity == identity
        }
        return GraphExecutorCommandContext(
            identity: identity,
            capabilityRequirement: execution.capabilityRequirement,
            specification: execution.specification,
            workspace: execution.workspace,
            environmentAllowlist: execution.environmentAllowlist,
            inputArtifacts: try GraphArtifactInputResolver.resolve(
                nodeID: claim.nodeID,
                definition: definition,
                projection: projection
            ),
            cancellation: projection.scheduling.pendingCancellation(
                nodeID: claim.nodeID
            ),
            timeoutPolicy: execution.timeoutPolicy,
            correlation: GraphExecutorCorrelationMetadata(
                correlationID: claim.id
            ),
            priorObservationCount: observations.filter {
                $0.operation == .observe
            }.count,
            logicalTime: max(logicalTime, claim.leaseStart)
        )
    }

    private func refreshedContext(
        _ context: GraphExecutorCommandContext,
        loaded: Loaded
    ) throws -> GraphExecutorCommandContext {
        guard let definition = loaded.projection.executableDefinition else {
            throw GraphOrchestrationError.invalidDefinition(
                "executable definition disappeared."
            )
        }
        return try executionContext(
            claim: currentClaim(context.identity, loaded.projection),
            definition: definition,
            projection: loaded.projection,
            logicalTime: context.logicalTime
        )
    }

    private func invokePrepare(
        _ context: GraphExecutorCommandContext
    ) async throws -> GraphExecutorObservation {
        try requireConfirmation(.prepare, context)
        return try await executor.prepare(
            GraphExecutorPrepareRequest(context: context)
        ).observation
    }

    private func invokeStart(
        _ context: GraphExecutorCommandContext
    ) async throws -> GraphExecutorObservation {
        try requireConfirmation(.start, context)
        return try await executor.start(
            GraphExecutorStartRequest(context: context)
        ).observation
    }

    private func invokeObserve(
        _ context: GraphExecutorCommandContext
    ) async throws -> GraphExecutorObservation {
        try requireConfirmation(.observe, context)
        return try await executor.observe(
            GraphExecutorObserveRequest(context: context)
        ).observation
    }

    private func invokeRecover(
        _ context: GraphExecutorCommandContext
    ) async throws -> GraphExecutorObservation {
        try requireConfirmation(.recover, context)
        return try await executor.recover(
            GraphExecutorRecoverRequest(context: context)
        ).observation
    }

    private func invokeCollect(
        _ context: GraphExecutorCommandContext
    ) async throws -> GraphExecutorObservation {
        try requireConfirmation(.collectResult, context)
        return try await executor.collectResult(
            GraphExecutorCollectResultRequest(context: context)
        ).observation
    }

    private func invokeCleanup(
        _ context: GraphExecutorCommandContext
    ) async throws -> GraphExecutorObservation {
        try requireConfirmation(.cleanup, context)
        return try await executor.cleanup(
            GraphExecutorCleanupRequest(context: context)
        ).observation
    }

    private func invokeCancellation(
        _ context: GraphExecutorCommandContext,
        requestID: String
    ) async throws -> GraphExecutorObservation {
        try requireConfirmation(.requestCancellation, context)
        return try await executor.requestCancellation(
            GraphExecutorCancellationRequest(
                context: context,
                cancellationRequestID: requestID
            )
        ).observation
    }

    private func requireConfirmation(
        _ operation: GraphExecutorOperation,
        _ context: GraphExecutorCommandContext
    ) throws {
        guard confirmationPolicy.permits(
            operation: operation,
            context: context
        ) else {
            throw GraphOrchestrationError.adapterUnavailable(
                "execution confirmation policy denied \(operation.rawValue)."
            )
        }
    }

    private func claimableNode(
        projection: GraphExecutionProjection,
        evaluationID: String?
    ) -> String? {
        projection.scheduling.records.filter {
            $0.evaluationID == evaluationID
                && $0.eventType == GraphExecutionEventType
                    .nodeBecameRunnable.rawValue
                && $0.reason == .dependenciesSatisfied
        }.compactMap(\.nodeID).sorted().first
    }

    private func currentClaim(
        _ identity: GraphExecutorInteractionIdentity,
        _ projection: GraphExecutionProjection
    ) -> GraphExecutorClaim {
        projection.scheduling.claims.first {
            $0.claim.id == identity.claimID
                && $0.claim.leaseGeneration == identity.leaseGeneration
        }!.claim
    }

    private func pendingUnclaimedCancellation(
        _ projection: GraphExecutionProjection
    ) -> GraphCancellationRecord? {
        projection.scheduling.cancellations.filter {
            $0.state == .requested && $0.claimID == nil
        }.sorted { $0.id < $1.id }.first
    }

    private func shouldRenew(
        claim: GraphExecutorClaim,
        logicalTime: Date,
        leaseDurationSeconds: UInt64
    ) -> Bool {
        let remaining = claim.leaseExpiry.timeIntervalSince(logicalTime)
        return remaining > 0
            && remaining <= TimeInterval(leaseDurationSeconds) / 2
    }

    private func timeoutKind(
        context: GraphExecutorCommandContext,
        projection: GraphExecutionProjection
    ) -> GraphTimeoutKind? {
        guard let attempt = projection.attempts.first(where: {
            $0.id == context.identity.attemptID
        }), let startedAt = attempt.startedAt else {
            return nil
        }
        if let cancellation = context.cancellation,
           context.logicalTime >= cancellation.requestedAt
            .addingTimeInterval(
                TimeInterval(
                    context.timeoutPolicy
                        .cancellationAcknowledgementSeconds
                )
            ) {
            return .cancellationAcknowledgement
        }
        if context.logicalTime >= startedAt.addingTimeInterval(
            TimeInterval(context.timeoutPolicy.executionSeconds)
        ) {
            return .attemptExecution
        }
        return nil
    }

    private func timeoutDeadline(
        kind: GraphTimeoutKind,
        context: GraphExecutorCommandContext,
        projection: GraphExecutionProjection
    ) -> Date {
        if kind == .cancellationAcknowledgement,
           let cancellation = context.cancellation {
            return cancellation.requestedAt.addingTimeInterval(
                TimeInterval(
                    context.timeoutPolicy
                        .cancellationAcknowledgementSeconds
                )
            )
        }
        let startedAt = projection.attempts.first {
            $0.id == context.identity.attemptID
        }?.startedAt ?? context.logicalTime
        return startedAt.addingTimeInterval(
            TimeInterval(context.timeoutPolicy.executionSeconds)
        )
    }

    private func failureCategories(
        _ projection: GraphExecutionProjection
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: projection.attempts.compactMap {
            guard let reason = $0.statusReason else { return nil }
            return ($0.id, reason)
        })
    }

    private func schedulingDenials(
        _ projection: GraphExecutionProjection
    ) -> [GraphSchedulingReasonCode] {
        guard let evaluationID = projection.scheduling.records.last(where: {
            $0.eventType == GraphExecutionEventType
                .schedulerCycleCompleted.rawValue
        })?.evaluationID else {
            return []
        }
        return projection.scheduling.records.filter {
            $0.evaluationID == evaluationID
        }.compactMap(\.reason).filter {
            $0 != .dependenciesSatisfied
        }
    }

    private func terminalAfterScheduling(
        _ loaded: Loaded,
        definition: GraphExecutableDefinition,
        logicalTime: Date
    ) async throws -> Loaded? {
        let result = try await recordRunTerminalIfJustified(
            loaded: loaded,
            definition: definition,
            logicalTime: logicalTime
        )
        return result.version == loaded.version ? nil : result
    }

    private func recordRunTerminalIfJustified(
        loaded: Loaded,
        definition: GraphExecutableDefinition,
        logicalTime: Date
    ) async throws -> Loaded {
        guard loaded.projection.run?.state.isTerminal != true,
              let state = aggregateTerminalState(
                projection: loaded.projection,
                definition: definition
              ) else {
            return loaded
        }
        let terminalMaterial = [
            loaded.projection.runID,
            state.rawValue,
        ].joined(separator: "|")
        let terminalDigest = DefaultGraphMutationService.stableID(
            terminalMaterial
        )
        let event = GraphExecutionEventEnvelope(
            id: "run-terminal-\(terminalDigest)",
            runID: loaded.projection.runID,
            streamSequence: loaded.version + 1,
            occurredAt: logicalTime,
            recordedAt: logicalTime,
            producer: producer,
            payload: .runTerminalStateRecorded(
                GraphRunTerminalPayload(
                    state: state,
                    reason: "graph_terminal_aggregation"
                )
            )
        )
        do {
            _ = try await eventStore.append(
                [event],
                to: loaded.projection.runID,
                expectedVersion: loaded.version
            )
            return try await load(loaded.projection.runID)
        } catch {
            throw GraphOrchestrationError.persistence(
                error.localizedDescription
            )
        }
    }

    private func aggregateTerminalState(
        projection: GraphExecutionProjection,
        definition: GraphExecutableDefinition
    ) -> ReconciledExecutionState? {
        let latest = Dictionary(
            grouping: projection.attempts,
            by: \.nodeID
        ).mapValues { attempts in
            attempts.max { $0.ordinal < $1.ordinal }!
        }
        let nodeIDs = definition.scheduling.nodes.map(\.id)
        if nodeIDs.allSatisfy({ latest[$0]?.state == .completed }) {
            return .completed
        }
        for nodeID in nodeIDs {
            guard let attempt = latest[nodeID] else { continue }
            if [.failed, .interrupted, .orphaned].contains(attempt.state) {
                let policy = definition.schedulerPolicy.retryPolicy(for: nodeID)
                let category = attempt.statusReason ?? "execution_failure"
                let retryAllowed = attempt.ordinal < policy.maximumAttempts
                    && !policy.nonRetryableFailureCategories.contains(category)
                    && (policy.retryableFailureCategories.isEmpty
                        || policy.retryableFailureCategories.contains(category))
                if !retryAllowed {
                    let suppressionExists = projection.scheduling.records
                        .contains {
                            $0.attemptID == attempt.id
                                && $0.eventType
                                    == GraphExecutionEventType
                                        .retrySuppressed.rawValue
                        }
                    guard suppressionExists else { return nil }
                    return .failed
                }
            }
        }
        let cancelled = latest.values.filter { $0.state == .cancelled }
        if !cancelled.isEmpty,
           nodeIDs.allSatisfy({
            latest[$0]?.state == .completed
                || latest[$0]?.state == .cancelled
                || projection.scheduling.pendingCancellation(nodeID: $0)
                    != nil
           }) {
            return .cancelled
        }
        return nil
    }

    private func terminalState(
        _ status: GraphExecutorResponseStatus
    ) -> ReconciledExecutionState {
        switch status {
        case .succeeded:
            .completed
        case .failed:
            .failed
        case .cancelled:
            .cancelled
        case .interrupted:
            .interrupted
        default:
            .failed
        }
    }

    private func report(
        loaded: Loaded,
        initialVersion: UInt64,
        status: GraphOrchestrationCycleStatus,
        logicalTime: Date,
        evaluationID: String? = nil,
        claim: GraphExecutorClaim? = nil,
        persistedCount: Int = 0,
        executorOperation: GraphExecutorOperation? = nil,
        executorInvocations: Int = 0,
        denials: [GraphSchedulingReasonCode] = [],
        adapterStatus: GraphExecutorResponseStatus? = nil
    ) -> GraphOrchestrationCycleReport {
        GraphOrchestrationCycleReport(
            runID: loaded.projection.runID,
            status: status,
            logicalTime: logicalTime,
            previousVersion: initialVersion,
            streamVersion: loaded.version,
            schedulerEvaluationID: evaluationID,
            claimedNodeID: claim?.nodeID,
            claimID: claim?.id,
            executorOperation: executorOperation,
            executorStatus: adapterStatus,
            persistedEventCount: persistedCount,
            executorInvocationCount: executorInvocations,
            runState: loaded.projection.run?.state ?? .pending,
            policyDenials: denials
        )
    }
}
