import Foundation

public enum AntigravityHookEventName: String, Codable, Sendable {
    case preInvocation = "PreInvocation"
    case stop = "Stop"
}

/// Payload emitted by Antigravity 2.0 JSON hooks.
///
/// Antigravity does not include the hook name in stdin, so OpenIslandHooks
/// supplies `hookEventName` from its managed `--event` argument before the
/// payload crosses the local bridge.
public struct AntigravityHookPayload: Equatable, Codable, Sendable {
    public var conversationID: String
    public var workspacePaths: [String]
    public var transcriptPath: String?
    public var artifactDirectoryPath: String?
    public var modelName: String?
    public var invocationNum: Int?
    public var initialNumSteps: Int?
    public var executionNum: Int?
    public var terminationReason: String?
    public var error: String?
    public var fullyIdle: Bool?
    public var hookEventName: AntigravityHookEventName?

    private enum CodingKeys: String, CodingKey {
        case conversationID = "conversationId"
        case workspacePaths
        case transcriptPath
        case artifactDirectoryPath
        case modelName
        case invocationNum
        case initialNumSteps
        case executionNum
        case terminationReason
        case error
        case fullyIdle
        case hookEventName
    }

    public init(
        conversationID: String,
        workspacePaths: [String],
        transcriptPath: String? = nil,
        artifactDirectoryPath: String? = nil,
        modelName: String? = nil,
        invocationNum: Int? = nil,
        initialNumSteps: Int? = nil,
        executionNum: Int? = nil,
        terminationReason: String? = nil,
        error: String? = nil,
        fullyIdle: Bool? = nil,
        hookEventName: AntigravityHookEventName? = nil
    ) {
        self.conversationID = conversationID
        self.workspacePaths = workspacePaths
        self.transcriptPath = transcriptPath
        self.artifactDirectoryPath = artifactDirectoryPath
        self.modelName = modelName
        self.invocationNum = invocationNum
        self.initialNumSteps = initialNumSteps
        self.executionNum = executionNum
        self.terminationReason = terminationReason
        self.error = error
        self.fullyIdle = fullyIdle
        self.hookEventName = hookEventName
    }
}

public extension AntigravityHookPayload {
    var workingDirectory: String? {
        workspacePaths.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    var workspaceName: String {
        guard let workingDirectory else { return "Agent Manager" }
        return WorkspaceNameResolver.workspaceName(for: workingDirectory)
    }

    var sessionTitle: String {
        "Antigravity · \(workspaceName)"
    }

    var defaultJumpTarget: JumpTarget {
        JumpTarget(
            terminalApp: "Antigravity",
            workspaceName: workspaceName,
            paneTitle: "Antigravity \(conversationID.prefix(8))",
            workingDirectory: workingDirectory
        )
    }

    var runningSummary: String {
        "Antigravity is working in \(workspaceName)."
    }

    var stoppedSummary: String {
        if let error = error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            return "Antigravity stopped with an error in \(workspaceName)."
        }

        switch terminationReason?.lowercased() {
        case "max_steps_exceeded":
            return "Antigravity stopped after reaching its step limit in \(workspaceName)."
        case "error":
            return "Antigravity stopped with an error in \(workspaceName)."
        default:
            return "Antigravity completed the task in \(workspaceName)."
        }
    }

    func withHookEvent(_ event: AntigravityHookEventName) -> AntigravityHookPayload {
        var payload = self
        payload.hookEventName = event
        return payload
    }
}
