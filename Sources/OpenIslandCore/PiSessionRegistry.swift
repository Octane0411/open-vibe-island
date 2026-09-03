import Foundation

public struct PiTrackedSessionRecord: Equatable, Codable, Sendable {
    public var sessionID: String
    public var title: String
    public var tool: AgentTool
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var summary: String
    public var phase: SessionPhase
    public var updatedAt: Date
    public var firstSeenAt: Date?
    public var jumpTarget: JumpTarget?
    public var piMetadata: PiSessionMetadata?

    public init(session: AgentSession) {
        sessionID = session.id
        title = session.title
        tool = session.tool
        origin = session.origin
        attachmentState = session.attachmentState
        summary = session.summary
        phase = session.phase
        updatedAt = session.updatedAt
        firstSeenAt = session.firstSeenAt
        jumpTarget = session.jumpTarget
        piMetadata = session.piMetadata
    }

    public var session: AgentSession {
        AgentSession(
            id: sessionID,
            title: title,
            tool: tool,
            origin: origin,
            attachmentState: attachmentState,
            phase: phase,
            summary: summary,
            updatedAt: updatedAt,
            firstSeenAt: firstSeenAt,
            jumpTarget: jumpTarget,
            piMetadata: piMetadata
        )
    }

    public func restorableSession(at restoredAt: Date) -> AgentSession {
        var restored = session
        restored.attachmentState = .stale

        if restored.origin != .demo {
            restored.isHookManaged = true
            restored.heartbeatReconnectStartedAt = restoredAt
        }

        return restored
    }
}

public final class PiSessionRegistry: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultFileURL: URL {
        CodexSessionStore.defaultDirectoryURL.appendingPathComponent("pi-session-registry.json")
    }

    public init(
        fileURL: URL = PiSessionRegistry.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> [PiTrackedSessionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PiTrackedSessionRecord].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ records: [PiTrackedSessionRecord]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: .atomic)
    }
}
