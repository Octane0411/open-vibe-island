import Foundation

public enum AgentTimelineEventKind: String, Codable, Sendable {
    case lifecycle
    case status
    case prompt
    case tool
    case permission
    case question
    case response
    case completion
    case system
}

public struct AgentTimelineEvent: Equatable, Identifiable, Codable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var kind: AgentTimelineEventKind
    public var title: String
    public var detail: String?
    public var toolName: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: AgentTimelineEventKind,
        title: String,
        detail: String? = nil,
        toolName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.detail = detail
        self.toolName = toolName
    }

    fileprivate var semanticKey: String {
        [kind.rawValue, title, detail ?? "", toolName ?? ""].joined(separator: "\u{1f}")
    }
}

public struct AgentSessionMetrics: Equatable, Codable, Sendable {
    public var startedAt: Date?
    public var lastEventAt: Date?
    public var eventCount: Int
    public var toolEventCount: Int
    public var attentionEventCount: Int
    public var completionCount: Int

    public init(
        startedAt: Date? = nil,
        lastEventAt: Date? = nil,
        eventCount: Int = 0,
        toolEventCount: Int = 0,
        attentionEventCount: Int = 0,
        completionCount: Int = 0
    ) {
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.eventCount = eventCount
        self.toolEventCount = toolEventCount
        self.attentionEventCount = attentionEventCount
        self.completionCount = completionCount
    }

    public func elapsed(at referenceDate: Date = .now) -> TimeInterval {
        guard let startedAt else {
            return 0
        }

        let endDate = max(lastEventAt ?? referenceDate, referenceDate)
        return max(0, endDate.timeIntervalSince(startedAt))
    }
}

public struct AgentSessionObservability: Equatable, Codable, Sendable {
    public static let defaultTimelineLimit = 250

    public var timeline: [AgentTimelineEvent]
    public var metrics: AgentSessionMetrics

    public init(
        timeline: [AgentTimelineEvent] = [],
        metrics: AgentSessionMetrics = AgentSessionMetrics()
    ) {
        self.timeline = timeline
        self.metrics = metrics
    }

    public mutating func record(
        _ event: AgentTimelineEvent,
        timelineLimit: Int = Self.defaultTimelineLimit
    ) {
        if let lastIndex = timeline.indices.last,
           timeline[lastIndex].semanticKey == event.semanticKey {
            timeline[lastIndex].timestamp = max(timeline[lastIndex].timestamp, event.timestamp)
            metrics.lastEventAt = max(metrics.lastEventAt ?? event.timestamp, event.timestamp)
            return
        }

        timeline.append(event)
        if timeline.count > max(1, timelineLimit) {
            timeline.removeFirst(timeline.count - max(1, timelineLimit))
        }

        metrics.startedAt = min(metrics.startedAt ?? event.timestamp, event.timestamp)
        metrics.lastEventAt = max(metrics.lastEventAt ?? event.timestamp, event.timestamp)
        metrics.eventCount += 1

        switch event.kind {
        case .tool:
            metrics.toolEventCount += 1
        case .permission, .question:
            metrics.attentionEventCount += 1
        case .completion:
            metrics.completionCount += 1
        case .lifecycle, .status, .prompt, .response, .system:
            break
        }
    }
}

public extension AgentEvent {
    var sessionID: String {
        switch self {
        case let .sessionStarted(payload): payload.sessionID
        case let .activityUpdated(payload): payload.sessionID
        case let .permissionRequested(payload): payload.sessionID
        case let .questionAsked(payload): payload.sessionID
        case let .sessionCompleted(payload): payload.sessionID
        case let .jumpTargetUpdated(payload): payload.sessionID
        case let .sessionMetadataUpdated(payload): payload.sessionID
        case let .claudeSessionMetadataUpdated(payload): payload.sessionID
        case let .geminiSessionMetadataUpdated(payload): payload.sessionID
        case let .openCodeSessionMetadataUpdated(payload): payload.sessionID
        case let .cursorSessionMetadataUpdated(payload): payload.sessionID
        case let .actionableStateResolved(payload): payload.sessionID
        }
    }

    var timestamp: Date {
        switch self {
        case let .sessionStarted(payload): payload.timestamp
        case let .activityUpdated(payload): payload.timestamp
        case let .permissionRequested(payload): payload.timestamp
        case let .questionAsked(payload): payload.timestamp
        case let .sessionCompleted(payload): payload.timestamp
        case let .jumpTargetUpdated(payload): payload.timestamp
        case let .sessionMetadataUpdated(payload): payload.timestamp
        case let .claudeSessionMetadataUpdated(payload): payload.timestamp
        case let .geminiSessionMetadataUpdated(payload): payload.timestamp
        case let .openCodeSessionMetadataUpdated(payload): payload.timestamp
        case let .cursorSessionMetadataUpdated(payload): payload.timestamp
        case let .actionableStateResolved(payload): payload.timestamp
        }
    }

    var timelineEvent: AgentTimelineEvent? {
        switch self {
        case let .sessionStarted(payload):
            return AgentTimelineEvent(
                timestamp: payload.timestamp,
                kind: .lifecycle,
                title: "Session started",
                detail: payload.summary
            )
        case let .activityUpdated(payload):
            return AgentTimelineEvent(
                timestamp: payload.timestamp,
                kind: payload.phase == .completed ? .completion : .status,
                title: payload.phase.displayName,
                detail: payload.summary
            )
        case let .permissionRequested(payload):
            return AgentTimelineEvent(
                timestamp: payload.timestamp,
                kind: .permission,
                title: payload.request.title,
                detail: nonEmpty(payload.request.affectedPath) ?? payload.request.summary,
                toolName: payload.request.toolName
            )
        case let .questionAsked(payload):
            return AgentTimelineEvent(
                timestamp: payload.timestamp,
                kind: .question,
                title: "Question asked",
                detail: payload.prompt.title
            )
        case let .sessionCompleted(payload):
            return AgentTimelineEvent(
                timestamp: payload.timestamp,
                kind: .completion,
                title: payload.isInterrupt == true ? "Interrupted" : "Completed",
                detail: payload.summary
            )
        case let .jumpTargetUpdated(payload):
            return AgentTimelineEvent(
                timestamp: payload.timestamp,
                kind: .system,
                title: "Jump target updated",
                detail: "\(payload.jumpTarget.terminalApp) · \(payload.jumpTarget.workspaceName)"
            )
        case let .sessionMetadataUpdated(payload):
            return metadataTimelineEvent(
                timestamp: payload.timestamp,
                currentTool: payload.codexMetadata.currentTool,
                toolPreview: payload.codexMetadata.currentCommandPreview,
                userPrompt: payload.codexMetadata.lastUserPrompt,
                assistantMessage: payload.codexMetadata.lastAssistantMessage
            )
        case let .claudeSessionMetadataUpdated(payload):
            return metadataTimelineEvent(
                timestamp: payload.timestamp,
                currentTool: payload.claudeMetadata.currentTool,
                toolPreview: payload.claudeMetadata.currentToolInputPreview,
                userPrompt: payload.claudeMetadata.lastUserPrompt,
                assistantMessage: payload.claudeMetadata.lastAssistantMessage
            )
        case let .geminiSessionMetadataUpdated(payload):
            return metadataTimelineEvent(
                timestamp: payload.timestamp,
                currentTool: nil,
                toolPreview: nil,
                userPrompt: payload.geminiMetadata.lastUserPrompt,
                assistantMessage: payload.geminiMetadata.lastAssistantMessage
            )
        case let .openCodeSessionMetadataUpdated(payload):
            return metadataTimelineEvent(
                timestamp: payload.timestamp,
                currentTool: payload.openCodeMetadata.currentTool,
                toolPreview: payload.openCodeMetadata.currentToolInputPreview,
                userPrompt: payload.openCodeMetadata.lastUserPrompt,
                assistantMessage: payload.openCodeMetadata.lastAssistantMessage
            )
        case let .cursorSessionMetadataUpdated(payload):
            return metadataTimelineEvent(
                timestamp: payload.timestamp,
                currentTool: payload.cursorMetadata.currentTool,
                toolPreview: payload.cursorMetadata.currentCommandPreview
                    ?? payload.cursorMetadata.currentToolInputPreview,
                userPrompt: payload.cursorMetadata.lastUserPrompt,
                assistantMessage: payload.cursorMetadata.lastAssistantMessage
            )
        case let .actionableStateResolved(payload):
            return AgentTimelineEvent(
                timestamp: payload.timestamp,
                kind: .status,
                title: "Interaction resolved",
                detail: payload.summary
            )
        }
    }
}

private func metadataTimelineEvent(
    timestamp: Date,
    currentTool: String?,
    toolPreview: String?,
    userPrompt: String?,
    assistantMessage: String?
) -> AgentTimelineEvent? {
    if let currentTool = nonEmpty(currentTool) {
        return AgentTimelineEvent(
            timestamp: timestamp,
            kind: .tool,
            title: "Using \(currentTool)",
            detail: clipped(nonEmpty(toolPreview)),
            toolName: currentTool
        )
    }

    if let assistantMessage = clipped(nonEmpty(assistantMessage)) {
        return AgentTimelineEvent(
            timestamp: timestamp,
            kind: .response,
            title: "Assistant replied",
            detail: assistantMessage
        )
    }

    if let userPrompt = clipped(nonEmpty(userPrompt)) {
        return AgentTimelineEvent(
            timestamp: timestamp,
            kind: .prompt,
            title: "Prompt received",
            detail: userPrompt
        )
    }

    return nil
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        return nil
    }
    return value
}

private func clipped(_ value: String?, limit: Int = 240) -> String? {
    guard let value else {
        return nil
    }
    guard value.count > limit else {
        return value
    }
    return "\(value.prefix(limit))…"
}
