import Foundation

public struct SessionStarted: Equatable, Codable, Sendable {
    public var sessionID: String
    public var title: String
    public var tool: AgentTool
    public var origin: SessionOrigin?
    public var initialPhase: SessionPhase
    public var summary: String
    public var timestamp: Date
    public var jumpTarget: JumpTarget?
    public var codexMetadata: CodexSessionMetadata?
    public var claudeMetadata: ClaudeSessionMetadata?
    public var openCodeMetadata: OpenCodeSessionMetadata?
    public var isRemote: Bool

    public init(
        sessionID: String,
        title: String,
        tool: AgentTool,
        origin: SessionOrigin? = nil,
        initialPhase: SessionPhase = .running,
        summary: String,
        timestamp: Date,
        jumpTarget: JumpTarget? = nil,
        codexMetadata: CodexSessionMetadata? = nil,
        claudeMetadata: ClaudeSessionMetadata? = nil,
        openCodeMetadata: OpenCodeSessionMetadata? = nil,
        isRemote: Bool = false
    ) {
        self.sessionID = sessionID
        self.title = title
        self.tool = tool
        self.origin = origin
        self.initialPhase = initialPhase
        self.summary = summary
        self.timestamp = timestamp
        self.jumpTarget = jumpTarget
        self.codexMetadata = codexMetadata
        self.claudeMetadata = claudeMetadata
        self.openCodeMetadata = openCodeMetadata
        self.isRemote = isRemote
    }
}

public struct SessionActivityUpdated: Equatable, Codable, Sendable {
    public var sessionID: String
    public var summary: String
    public var phase: SessionPhase
    public var timestamp: Date

    public init(
        sessionID: String,
        summary: String,
        phase: SessionPhase,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.summary = summary
        self.phase = phase
        self.timestamp = timestamp
    }
}

public struct PermissionRequested: Equatable, Codable, Sendable {
    public var sessionID: String
    public var request: PermissionRequest
    public var timestamp: Date

    public init(
        sessionID: String,
        request: PermissionRequest,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.request = request
        self.timestamp = timestamp
    }
}

public struct QuestionAsked: Equatable, Codable, Sendable {
    public var sessionID: String
    public var prompt: QuestionPrompt
    public var timestamp: Date

    public init(
        sessionID: String,
        prompt: QuestionPrompt,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.prompt = prompt
        self.timestamp = timestamp
    }
}

public struct SessionCompleted: Equatable, Codable, Sendable {
    public var sessionID: String
    public var summary: String
    public var timestamp: Date
    public var isInterrupt: Bool?

    public init(
        sessionID: String,
        summary: String,
        timestamp: Date,
        isInterrupt: Bool? = nil
    ) {
        self.sessionID = sessionID
        self.summary = summary
        self.timestamp = timestamp
        self.isInterrupt = isInterrupt
    }
}

public struct JumpTargetUpdated: Equatable, Codable, Sendable {
    public var sessionID: String
    public var jumpTarget: JumpTarget
    public var timestamp: Date

    public init(
        sessionID: String,
        jumpTarget: JumpTarget,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.jumpTarget = jumpTarget
        self.timestamp = timestamp
    }
}

public struct SessionMetadataUpdated: Equatable, Codable, Sendable {
    public var sessionID: String
    public var codexMetadata: CodexSessionMetadata
    public var timestamp: Date

    public init(
        sessionID: String,
        codexMetadata: CodexSessionMetadata,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.codexMetadata = codexMetadata
        self.timestamp = timestamp
    }
}

public struct ClaudeSessionMetadataUpdated: Equatable, Codable, Sendable {
    public var sessionID: String
    public var claudeMetadata: ClaudeSessionMetadata
    public var timestamp: Date

    public init(
        sessionID: String,
        claudeMetadata: ClaudeSessionMetadata,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.claudeMetadata = claudeMetadata
        self.timestamp = timestamp
    }
}

public struct OpenCodeSessionMetadataUpdated: Equatable, Codable, Sendable {
    public var sessionID: String
    public var openCodeMetadata: OpenCodeSessionMetadata
    public var timestamp: Date

    public init(
        sessionID: String,
        openCodeMetadata: OpenCodeSessionMetadata,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.openCodeMetadata = openCodeMetadata
        self.timestamp = timestamp
    }
}

public struct ActionableStateResolved: Equatable, Codable, Sendable {
    public var sessionID: String
    public var summary: String
    public var timestamp: Date

    public init(
        sessionID: String,
        summary: String,
        timestamp: Date
    ) {
        self.sessionID = sessionID
        self.summary = summary
        self.timestamp = timestamp
    }
}

public enum AgentEvent: Equatable, Codable, Sendable {
    case sessionStarted(SessionStarted)
    case activityUpdated(SessionActivityUpdated)
    case permissionRequested(PermissionRequested)
    case questionAsked(QuestionAsked)
    case sessionCompleted(SessionCompleted)
    case jumpTargetUpdated(JumpTargetUpdated)
    case sessionMetadataUpdated(SessionMetadataUpdated)
    case claudeSessionMetadataUpdated(ClaudeSessionMetadataUpdated)
    case openCodeSessionMetadataUpdated(OpenCodeSessionMetadataUpdated)
    case actionableStateResolved(ActionableStateResolved)

    private enum CodingKeys: String, CodingKey {
        case type
        case sessionStarted
        case activityUpdated
        case permissionRequested
        case questionAsked
        case sessionCompleted
        case jumpTargetUpdated
        case sessionMetadataUpdated
        case claudeSessionMetadataUpdated
        case openCodeSessionMetadataUpdated
        case actionableStateResolved
    }

    private enum EventType: String, Codable {
        case sessionStarted
        case activityUpdated
        case permissionRequested
        case questionAsked
        case sessionCompleted
        case jumpTargetUpdated
        case sessionMetadataUpdated
        case claudeSessionMetadataUpdated
        case openCodeSessionMetadataUpdated
        case actionableStateResolved
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)

        switch type {
        case .sessionStarted:
            self = .sessionStarted(try container.decode(SessionStarted.self, forKey: .sessionStarted))
        case .activityUpdated:
            self = .activityUpdated(try container.decode(SessionActivityUpdated.self, forKey: .activityUpdated))
        case .permissionRequested:
            self = .permissionRequested(try container.decode(PermissionRequested.self, forKey: .permissionRequested))
        case .questionAsked:
            self = .questionAsked(try container.decode(QuestionAsked.self, forKey: .questionAsked))
        case .sessionCompleted:
            self = .sessionCompleted(try container.decode(SessionCompleted.self, forKey: .sessionCompleted))
        case .jumpTargetUpdated:
            self = .jumpTargetUpdated(try container.decode(JumpTargetUpdated.self, forKey: .jumpTargetUpdated))
        case .sessionMetadataUpdated:
            self = .sessionMetadataUpdated(try container.decode(SessionMetadataUpdated.self, forKey: .sessionMetadataUpdated))
        case .claudeSessionMetadataUpdated:
            self = .claudeSessionMetadataUpdated(
                try container.decode(ClaudeSessionMetadataUpdated.self, forKey: .claudeSessionMetadataUpdated)
            )
        case .openCodeSessionMetadataUpdated:
            self = .openCodeSessionMetadataUpdated(
                try container.decode(OpenCodeSessionMetadataUpdated.self, forKey: .openCodeSessionMetadataUpdated)
            )
        case .actionableStateResolved:
            self = .actionableStateResolved(
                try container.decode(ActionableStateResolved.self, forKey: .actionableStateResolved)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .sessionStarted(payload):
            try container.encode(EventType.sessionStarted, forKey: .type)
            try container.encode(payload, forKey: .sessionStarted)
        case let .activityUpdated(payload):
            try container.encode(EventType.activityUpdated, forKey: .type)
            try container.encode(payload, forKey: .activityUpdated)
        case let .permissionRequested(payload):
            try container.encode(EventType.permissionRequested, forKey: .type)
            try container.encode(payload, forKey: .permissionRequested)
        case let .questionAsked(payload):
            try container.encode(EventType.questionAsked, forKey: .type)
            try container.encode(payload, forKey: .questionAsked)
        case let .sessionCompleted(payload):
            try container.encode(EventType.sessionCompleted, forKey: .type)
            try container.encode(payload, forKey: .sessionCompleted)
        case let .jumpTargetUpdated(payload):
            try container.encode(EventType.jumpTargetUpdated, forKey: .type)
            try container.encode(payload, forKey: .jumpTargetUpdated)
        case let .sessionMetadataUpdated(payload):
            try container.encode(EventType.sessionMetadataUpdated, forKey: .type)
            try container.encode(payload, forKey: .sessionMetadataUpdated)
        case let .claudeSessionMetadataUpdated(payload):
            try container.encode(EventType.claudeSessionMetadataUpdated, forKey: .type)
            try container.encode(payload, forKey: .claudeSessionMetadataUpdated)
        case let .openCodeSessionMetadataUpdated(payload):
            try container.encode(EventType.openCodeSessionMetadataUpdated, forKey: .type)
            try container.encode(payload, forKey: .openCodeSessionMetadataUpdated)
        case let .actionableStateResolved(payload):
            try container.encode(EventType.actionableStateResolved, forKey: .type)
            try container.encode(payload, forKey: .actionableStateResolved)
        }
    }
}

public extension AgentEvent {
    func extractSessionID() -> String {
        switch self {
        case let .sessionStarted(p): p.sessionID
        case let .activityUpdated(p): p.sessionID
        case let .permissionRequested(p): p.sessionID
        case let .questionAsked(p): p.sessionID
        case let .sessionCompleted(p): p.sessionID
        case let .jumpTargetUpdated(p): p.sessionID
        case let .sessionMetadataUpdated(p): p.sessionID
        case let .claudeSessionMetadataUpdated(p): p.sessionID
        case let .openCodeSessionMetadataUpdated(p): p.sessionID
        case let .actionableStateResolved(p): p.sessionID
        }
    }
}

public struct ScheduledAgentEvent: Equatable, Sendable {
    public var delay: TimeInterval
    public var event: AgentEvent

    public init(delay: TimeInterval, event: AgentEvent) {
        self.delay = delay
        self.event = event
    }
}
