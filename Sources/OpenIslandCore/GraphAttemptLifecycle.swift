import Foundation

public enum GraphAttemptLifecyclePhase:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case created
    case claimed
    case startRequested = "start_requested"
    case started
    case running
    case cancellationRequested = "cancellation_requested"
    case terminal
    case claimReleased = "claim_released"
}

public struct GraphAttemptLifecycleRecord:
    Equatable,
    Codable,
    Sendable,
    Identifiable
{
    public var id: String { attemptID }

    public let attemptID: String
    public let nodeID: String
    public let ordinal: Int
    public var phase: GraphAttemptLifecyclePhase
    public var claimID: String?
    public var leaseGeneration: UInt64?
    public var executorID: String?
    public var updatedAt: Date

    public init(
        attemptID: String,
        nodeID: String,
        ordinal: Int,
        phase: GraphAttemptLifecyclePhase,
        claimID: String? = nil,
        leaseGeneration: UInt64? = nil,
        executorID: String? = nil,
        updatedAt: Date
    ) {
        self.attemptID = attemptID
        self.nodeID = nodeID
        self.ordinal = ordinal
        self.phase = phase
        self.claimID = claimID
        self.leaseGeneration = leaseGeneration
        self.executorID = executorID
        self.updatedAt = updatedAt
    }
}
