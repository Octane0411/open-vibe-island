import Foundation

public struct CursorTrackedSessionRecord: Equatable, Codable, Sendable {
    public var sessionID: String
    public var title: String
    public var origin: SessionOrigin?
    public var attachmentState: SessionAttachmentState
    public var summary: String
    public var phase: SessionPhase
    public var updatedAt: Date
    public var jumpTarget: JumpTarget?
    public var cursorMetadata: CursorSessionMetadata?
    public var isRemote: Bool
    public var lifecyclePolicy: SessionLifecyclePolicy
    public var isSessionEnded: Bool

    public init(
        sessionID: String,
        title: String,
        origin: SessionOrigin? = nil,
        attachmentState: SessionAttachmentState = .stale,
        summary: String,
        phase: SessionPhase,
        updatedAt: Date,
        jumpTarget: JumpTarget? = nil,
        cursorMetadata: CursorSessionMetadata? = nil,
        isRemote: Bool = false,
        lifecyclePolicy: SessionLifecyclePolicy = .hookDrivenWithProcessFallback,
        isSessionEnded: Bool = false
    ) {
        self.sessionID = sessionID
        self.title = title
        self.origin = origin
        self.attachmentState = attachmentState
        self.summary = summary
        self.phase = phase
        self.updatedAt = updatedAt
        self.jumpTarget = jumpTarget
        self.cursorMetadata = cursorMetadata
        self.isRemote = isRemote
        self.lifecyclePolicy = lifecyclePolicy
        self.isSessionEnded = isSessionEnded
    }

    public init(session: AgentSession) {
        self.init(
            sessionID: session.id,
            title: session.title,
            origin: session.origin,
            attachmentState: session.attachmentState,
            summary: session.summary,
            phase: session.phase,
            updatedAt: session.updatedAt,
            jumpTarget: session.jumpTarget,
            cursorMetadata: session.cursorMetadata,
            isRemote: session.isRemote,
            lifecyclePolicy: session.lifecyclePolicy,
            isSessionEnded: session.isSessionEnded
        )
    }

    public var session: AgentSession {
        AgentSession(
            id: sessionID,
            title: title,
            tool: .cursor,
            origin: origin,
            attachmentState: attachmentState,
            phase: phase,
            summary: summary,
            updatedAt: updatedAt,
            jumpTarget: jumpTarget,
            cursorMetadata: cursorMetadata,
            isRemote: isRemote,
            lifecyclePolicy: lifecyclePolicy,
            isSessionEnded: isSessionEnded
        )
    }

    public var restorableSession: AgentSession {
        var session = session
        session.attachmentState = .stale
        return session
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case title
        case origin
        case attachmentState
        case summary
        case phase
        case updatedAt
        case jumpTarget
        case cursorMetadata
        case isRemote
        case lifecyclePolicy
        case isSessionEnded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        title = try container.decode(String.self, forKey: .title)
        origin = try container.decodeIfPresent(SessionOrigin.self, forKey: .origin)
        attachmentState = try container.decodeIfPresent(SessionAttachmentState.self, forKey: .attachmentState) ?? .stale
        summary = try container.decode(String.self, forKey: .summary)
        phase = try container.decode(SessionPhase.self, forKey: .phase)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        jumpTarget = try container.decodeIfPresent(JumpTarget.self, forKey: .jumpTarget)
        cursorMetadata = try container.decodeIfPresent(CursorSessionMetadata.self, forKey: .cursorMetadata)
        isRemote = try container.decodeIfPresent(Bool.self, forKey: .isRemote) ?? false
        lifecyclePolicy = try container.decodeIfPresent(SessionLifecyclePolicy.self, forKey: .lifecyclePolicy)
            ?? AgentSession.inferredLifecyclePolicy(
                tool: .cursor,
                origin: origin,
                jumpTarget: jumpTarget
            )
        isSessionEnded = try container.decodeIfPresent(Bool.self, forKey: .isSessionEnded) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encode(attachmentState, forKey: .attachmentState)
        try container.encode(summary, forKey: .summary)
        try container.encode(phase, forKey: .phase)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(jumpTarget, forKey: .jumpTarget)
        try container.encodeIfPresent(cursorMetadata, forKey: .cursorMetadata)
        try container.encode(isRemote, forKey: .isRemote)
        try container.encode(lifecyclePolicy, forKey: .lifecyclePolicy)
        try container.encode(isSessionEnded, forKey: .isSessionEnded)
    }
}

public extension CursorTrackedSessionRecord {
    var shouldRestoreToLiveState: Bool {
        !isSessionEnded && origin != .demo
    }
}

public final class CursorSessionRegistry: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultDirectoryURL: URL {
        CodexSessionStore.defaultDirectoryURL
    }

    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("cursor-session-registry.json")
    }

    public init(
        fileURL: URL = CursorSessionRegistry.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> [CursorTrackedSessionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CursorTrackedSessionRecord].self, from: data)
    }

    public func save(_ records: [CursorTrackedSessionRecord]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }
}
