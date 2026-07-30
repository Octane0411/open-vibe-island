import Foundation

public enum ReconciledExecutionState: String, Codable, CaseIterable, Sendable {
    case pending
    case ready
    case running
    case completed
    case failed
    case interrupted
    case orphaned
    case blocked
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .interrupted, .orphaned, .blocked, .cancelled:
            return true
        case .pending, .ready, .running:
            return false
        }
    }

    public var preventsDependentExecution: Bool {
        switch self {
        case .failed, .interrupted, .orphaned, .blocked, .cancelled:
            return true
        case .pending, .ready, .running, .completed:
            return false
        }
    }
}

public struct GraphRun: Equatable, Identifiable, Codable, Sendable {
    public let id: String
    public let graphID: String
    public var state: ReconciledExecutionState
    public var nodeIDs: [String]
    public let createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        id: String,
        graphID: String,
        state: ReconciledExecutionState = .pending,
        nodeIDs: [String],
        createdAt: Date,
        updatedAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.graphID = graphID
        self.state = state
        self.nodeIDs = nodeIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct GraphNode: Equatable, Identifiable, Codable, Sendable {
    public let id: String
    public let graphRunID: String
    public var title: String
    public var dependencyNodeIDs: [String]
    public var executorID: String?
    public var state: ReconciledExecutionState
    public var activeAttemptID: String?
    public var updatedAt: Date

    public init(
        id: String,
        graphRunID: String,
        title: String,
        dependencyNodeIDs: [String] = [],
        executorID: String? = nil,
        state: ReconciledExecutionState = .pending,
        activeAttemptID: String? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.graphRunID = graphRunID
        self.title = title
        self.dependencyNodeIDs = dependencyNodeIDs
        self.executorID = executorID
        self.state = state
        self.activeAttemptID = activeAttemptID
        self.updatedAt = updatedAt
    }
}

public struct ProcessIdentity: Equatable, Codable, Sendable {
    public let hostID: String
    public let launchID: String
    public let processID: Int32?
    public let startedAt: Date?

    public init(
        hostID: String,
        launchID: String,
        processID: Int32? = nil,
        startedAt: Date? = nil
    ) {
        self.hostID = hostID
        self.launchID = launchID
        self.processID = processID
        self.startedAt = startedAt
    }
}

public struct ExecutionAttempt: Equatable, Identifiable, Codable, Sendable {
    public let id: String
    public let graphRunID: String
    public let nodeID: String
    public let ordinal: Int
    public var state: ReconciledExecutionState
    public var processIdentity: ProcessIdentity?
    public let createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var statusReason: String?

    public init(
        id: String,
        graphRunID: String,
        nodeID: String,
        ordinal: Int,
        state: ReconciledExecutionState = .pending,
        processIdentity: ProcessIdentity? = nil,
        createdAt: Date,
        updatedAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        statusReason: String? = nil
    ) {
        self.id = id
        self.graphRunID = graphRunID
        self.nodeID = nodeID
        self.ordinal = ordinal
        self.state = state
        self.processIdentity = processIdentity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.statusReason = statusReason
    }
}

public struct ProcessExit: Equatable, Codable, Sendable {
    public let attemptID: String
    public let processIdentity: ProcessIdentity
    public let observedAt: Date
    public let exitCode: Int32?
    public let signal: Int32?
    public let reason: String?

    public init(
        attemptID: String,
        processIdentity: ProcessIdentity,
        observedAt: Date,
        exitCode: Int32? = nil,
        signal: Int32? = nil,
        reason: String? = nil
    ) {
        self.attemptID = attemptID
        self.processIdentity = processIdentity
        self.observedAt = observedAt
        self.exitCode = exitCode
        self.signal = signal
        self.reason = reason
    }
}

public struct ExecutorHeartbeat: Equatable, Codable, Sendable {
    public let attemptID: String
    public let processIdentity: ProcessIdentity
    public let observedAt: Date
    public let validUntil: Date

    public init(
        attemptID: String,
        processIdentity: ProcessIdentity,
        observedAt: Date,
        validUntil: Date
    ) {
        self.attemptID = attemptID
        self.processIdentity = processIdentity
        self.observedAt = observedAt
        self.validUntil = validUntil
    }
}

public enum ExecutionEventKind: String, Codable, CaseIterable, Sendable {
    case runStarted
    case runCompleted
    case runFailed
    case runInterrupted
    case runCancelled
    case attemptStarted
    case attemptCompleted
    case attemptFailed
    case attemptInterrupted
    case attemptOrphaned
    case attemptCancelled
}

public struct ExecutionEvent: Equatable, Identifiable, Codable, Sendable {
    public let id: String
    public let graphRunID: String
    public let nodeID: String?
    public let attemptID: String?
    public let sequence: UInt64
    public let occurredAt: Date
    public let kind: ExecutionEventKind
    public let reason: String?

    public init(
        id: String,
        graphRunID: String,
        nodeID: String? = nil,
        attemptID: String? = nil,
        sequence: UInt64,
        occurredAt: Date,
        kind: ExecutionEventKind,
        reason: String? = nil
    ) {
        self.id = id
        self.graphRunID = graphRunID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.sequence = sequence
        self.occurredAt = occurredAt
        self.kind = kind
        self.reason = reason
    }
}

public struct ExecutionReconciliationInput: Equatable, Codable, Sendable {
    public var run: GraphRun
    public var nodes: [GraphNode]
    public var attempts: [ExecutionAttempt]
    public var processExits: [ProcessExit]
    public var heartbeats: [ExecutorHeartbeat]
    public var events: [ExecutionEvent]
    public let observedAt: Date

    public init(
        run: GraphRun,
        nodes: [GraphNode],
        attempts: [ExecutionAttempt],
        processExits: [ProcessExit] = [],
        heartbeats: [ExecutorHeartbeat] = [],
        events: [ExecutionEvent] = [],
        observedAt: Date
    ) {
        self.run = run
        self.nodes = nodes
        self.attempts = attempts
        self.processExits = processExits
        self.heartbeats = heartbeats
        self.events = events
        self.observedAt = observedAt
    }
}

public struct ExecutionReconciliationResult: Equatable, Codable, Sendable {
    public var run: GraphRun
    public var nodes: [GraphNode]
    public var attempts: [ExecutionAttempt]

    public init(
        run: GraphRun,
        nodes: [GraphNode],
        attempts: [ExecutionAttempt]
    ) {
        self.run = run
        self.nodes = nodes
        self.attempts = attempts
    }
}

public enum GraphExecutionReconciler {
    public static func reconcile(
        _ input: ExecutionReconciliationInput
    ) -> ExecutionReconciliationResult {
        let reconciledAttempts = input.attempts.map {
            reconcileAttempt($0, input: input)
        }
        let latestAttempts = Dictionary(
            grouping: reconciledAttempts.filter {
                $0.graphRunID == input.run.id
            },
            by: \.nodeID
        ).compactMapValues(latestAttempt)
        var reconciledNodes = input.nodes.map { node in
            var reconciledNode = node

            if let attempt = latestAttempts[node.id] {
                if reconciledNode.activeAttemptID != attempt.id {
                    reconciledNode.updatedAt = input.observedAt
                }

                reconciledNode.activeAttemptID = attempt.id

                if attempt.state != .pending {
                    if reconciledNode.state != attempt.state {
                        reconciledNode.updatedAt = input.observedAt
                    }

                    reconciledNode.state = attempt.state
                }
            }

            return reconciledNode
        }

        reconcileDependencyStates(
            nodes: &reconciledNodes,
            latestAttempts: latestAttempts,
            observedAt: input.observedAt
        )

        var run = input.run
        let state = reconcileRunState(
            runID: run.id,
            nodes: reconciledNodes,
            events: input.events
        )

        if run.state != state {
            run.state = state
            run.updatedAt = input.observedAt
            run.finishedAt = state.isTerminal ? input.observedAt : nil
        }

        return ExecutionReconciliationResult(
            run: run,
            nodes: reconciledNodes,
            attempts: reconciledAttempts
        )
    }

    private static func reconcileAttempt(
        _ attempt: ExecutionAttempt,
        input: ExecutionReconciliationInput
    ) -> ExecutionAttempt {
        var result = attempt
        let attemptEvents = input.events.filter {
            $0.graphRunID == attempt.graphRunID
                && $0.attemptID == attempt.id
        }

        if let event = latestTerminalAttemptEvent(attemptEvents) {
            apply(
                state: event.kind.attemptTerminalState!,
                at: event.occurredAt,
                reason: event.reason,
                to: &result
            )
            return result
        }

        if let exit = latestMatchingExit(for: attempt, exits: input.processExits) {
            result.processIdentity = exit.processIdentity
            apply(
                state: .interrupted,
                at: exit.observedAt,
                reason: exit.reason ?? processExitReason(exit),
                to: &result
            )
            return result
        }

        if let heartbeat = latestValidHeartbeat(
            for: attempt,
            heartbeats: input.heartbeats,
            observedAt: input.observedAt
        ) {
            result.processIdentity = heartbeat.processIdentity
            apply(
                state: .running,
                at: heartbeat.observedAt,
                reason: nil,
                to: &result
            )
            result.finishedAt = nil
            return result
        }

        let hasStartedEvent = attemptEvents.contains {
            $0.kind == .attemptStarted
        }

        if attempt.state == .running || hasStartedEvent {
            let unsupportedState: ReconciledExecutionState =
                attempt.processIdentity == nil ? .interrupted : .orphaned
            let reason = unsupportedState == .orphaned
                ? "No current executor evidence matches the recorded process."
                : "The attempt was running without recoverable process identity."
            apply(
                state: unsupportedState,
                at: input.observedAt,
                reason: reason,
                to: &result
            )
        }

        return result
    }

    private static func apply(
        state: ReconciledExecutionState,
        at timestamp: Date,
        reason: String?,
        to attempt: inout ExecutionAttempt
    ) {
        if attempt.state != state {
            attempt.state = state
            attempt.updatedAt = timestamp
        }

        if state == .running {
            attempt.startedAt = attempt.startedAt ?? timestamp
        }

        if state.isTerminal {
            attempt.finishedAt = timestamp
        }

        attempt.statusReason = reason
    }

    private static func latestMatchingExit(
        for attempt: ExecutionAttempt,
        exits: [ProcessExit]
    ) -> ProcessExit? {
        exits
            .filter {
                $0.attemptID == attempt.id
                    && evidenceMatches(
                        recorded: attempt.processIdentity,
                        observed: $0.processIdentity
                    )
            }
            .max {
                if $0.observedAt != $1.observedAt {
                    return $0.observedAt < $1.observedAt
                }

                if $0.processIdentity != $1.processIdentity {
                    return processIdentityIsOrderedBefore(
                        $0.processIdentity,
                        $1.processIdentity
                    )
                }

                if $0.exitCode != $1.exitCode {
                    return optionalIsOrderedBefore(
                        $0.exitCode,
                        $1.exitCode
                    )
                }

                if $0.signal != $1.signal {
                    return optionalIsOrderedBefore(
                        $0.signal,
                        $1.signal
                    )
                }

                return optionalIsOrderedBefore($0.reason, $1.reason)
            }
    }

    private static func latestValidHeartbeat(
        for attempt: ExecutionAttempt,
        heartbeats: [ExecutorHeartbeat],
        observedAt: Date
    ) -> ExecutorHeartbeat? {
        heartbeats
            .filter {
                $0.attemptID == attempt.id
                    && $0.observedAt <= observedAt
                    && observedAt <= $0.validUntil
                    && evidenceMatches(
                        recorded: attempt.processIdentity,
                        observed: $0.processIdentity
                    )
            }
            .max {
                if $0.observedAt != $1.observedAt {
                    return $0.observedAt < $1.observedAt
                }

                if $0.validUntil != $1.validUntil {
                    return $0.validUntil < $1.validUntil
                }

                return processIdentityIsOrderedBefore(
                    $0.processIdentity,
                    $1.processIdentity
                )
            }
    }

    private static func evidenceMatches(
        recorded: ProcessIdentity?,
        observed: ProcessIdentity
    ) -> Bool {
        recorded == nil || recorded == observed
    }

    private static func latestTerminalAttemptEvent(
        _ events: [ExecutionEvent]
    ) -> ExecutionEvent? {
        events
            .filter { $0.kind.attemptTerminalState != nil }
            .max(by: eventIsOrderedBefore)
    }

    private static func latestTerminalRunEvent(
        runID: String,
        events: [ExecutionEvent]
    ) -> ExecutionEvent? {
        events
            .filter {
                $0.graphRunID == runID
                    && $0.kind.runTerminalState != nil
            }
            .max(by: eventIsOrderedBefore)
    }

    private static func eventIsOrderedBefore(
        _ lhs: ExecutionEvent,
        _ rhs: ExecutionEvent
    ) -> Bool {
        if lhs.sequence != rhs.sequence {
            return lhs.sequence < rhs.sequence
        }

        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt < rhs.occurredAt
        }

        if lhs.id != rhs.id {
            return lhs.id < rhs.id
        }

        if lhs.kind != rhs.kind {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }

        if lhs.nodeID != rhs.nodeID {
            return optionalIsOrderedBefore(lhs.nodeID, rhs.nodeID)
        }

        if lhs.attemptID != rhs.attemptID {
            return optionalIsOrderedBefore(
                lhs.attemptID,
                rhs.attemptID
            )
        }

        return optionalIsOrderedBefore(lhs.reason, rhs.reason)
    }

    private static func latestAttempt(
        _ attempts: [ExecutionAttempt]
    ) -> ExecutionAttempt? {
        attempts.max {
            if $0.ordinal != $1.ordinal {
                return $0.ordinal < $1.ordinal
            }

            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }

            return $0.id < $1.id
        }
    }

    private static func reconcileDependencyStates(
        nodes: inout [GraphNode],
        latestAttempts: [String: ExecutionAttempt],
        observedAt: Date
    ) {
        let orderedIndices = nodes.indices.sorted {
            nodes[$0].id < nodes[$1].id
        }

        for _ in 0..<nodes.count {
            let previousStates = Dictionary(
                uniqueKeysWithValues: nodes.map { ($0.id, $0.state) }
            )
            var changed = false

            for index in orderedIndices {
                let node = nodes[index]
                let latestState = latestAttempts[node.id]?.state

                guard latestState == nil
                        || latestState == .pending
                        || latestState == .ready
                        || latestState == .blocked else {
                    continue
                }

                let dependencyStates = node.dependencyNodeIDs.map {
                    previousStates[$0]
                }
                let state: ReconciledExecutionState

                if dependencyStates.contains(where: { $0 == nil })
                    || dependencyStates.contains(where: {
                        $0?.preventsDependentExecution == true
                    }) {
                    state = .blocked
                } else if dependencyStates.allSatisfy({ $0 == .completed }) {
                    state = .ready
                } else {
                    state = .pending
                }

                if nodes[index].state != state {
                    nodes[index].state = state
                    nodes[index].updatedAt = observedAt
                    changed = true
                }
            }

            if !changed {
                break
            }
        }
    }

    private static func reconcileRunState(
        runID: String,
        nodes: [GraphNode],
        events: [ExecutionEvent]
    ) -> ReconciledExecutionState {
        if let event = latestTerminalRunEvent(
            runID: runID,
            events: events
        ) {
            return event.kind.runTerminalState!
        }

        let states = nodes.map(\.state)

        if !states.isEmpty && states.allSatisfy({ $0 == .completed }) {
            return .completed
        }

        if states.contains(.running) {
            return .running
        }

        for state in [
            ReconciledExecutionState.failed,
            .interrupted,
            .orphaned,
            .cancelled,
            .blocked,
            .ready,
        ] where states.contains(state) {
            return state
        }

        return .pending
    }

    private static func processExitReason(_ exit: ProcessExit) -> String {
        if let signal = exit.signal {
            return "Process exited after signal \(signal)."
        }

        if let exitCode = exit.exitCode {
            return "Process exited with code \(exitCode) without a terminal execution event."
        }

        return "Process exited without a terminal execution event."
    }

    private static func processIdentityIsOrderedBefore(
        _ lhs: ProcessIdentity,
        _ rhs: ProcessIdentity
    ) -> Bool {
        if lhs.hostID != rhs.hostID {
            return lhs.hostID < rhs.hostID
        }

        if lhs.launchID != rhs.launchID {
            return lhs.launchID < rhs.launchID
        }

        if lhs.processID != rhs.processID {
            return optionalIsOrderedBefore(
                lhs.processID,
                rhs.processID
            )
        }

        return optionalIsOrderedBefore(lhs.startedAt, rhs.startedAt)
    }

    private static func optionalIsOrderedBefore<Value: Comparable>(
        _ lhs: Value?,
        _ rhs: Value?
    ) -> Bool {
        switch (lhs, rhs) {
        case (.none, .some):
            return true
        case (.some, .none), (.none, .none):
            return false
        case let (.some(lhs), .some(rhs)):
            return lhs < rhs
        }
    }
}

private extension ExecutionEventKind {
    var attemptTerminalState: ReconciledExecutionState? {
        switch self {
        case .attemptCompleted:
            return .completed
        case .attemptFailed:
            return .failed
        case .attemptInterrupted:
            return .interrupted
        case .attemptOrphaned:
            return .orphaned
        case .attemptCancelled:
            return .cancelled
        case .runStarted,
             .runCompleted,
             .runFailed,
             .runInterrupted,
             .runCancelled,
             .attemptStarted:
            return nil
        }
    }

    var runTerminalState: ReconciledExecutionState? {
        switch self {
        case .runCompleted:
            return .completed
        case .runFailed:
            return .failed
        case .runInterrupted:
            return .interrupted
        case .runCancelled:
            return .cancelled
        case .runStarted,
             .attemptStarted,
             .attemptCompleted,
             .attemptFailed,
             .attemptInterrupted,
             .attemptOrphaned,
             .attemptCancelled:
            return nil
        }
    }
}
