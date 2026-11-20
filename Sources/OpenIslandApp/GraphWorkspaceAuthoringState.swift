import CryptoKit
import Foundation
import OpenIslandCore

enum GraphWorkspaceTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank = "blank"
    case linearPipeline = "linear_pipeline"
    case fanOutFanIn = "fan_out_fan_in"
    case reviewLoop = "review_loop"
    case compendiumFill = "compendium_fill"
    case localProcessExample = "local_process_example"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .blank: "Blank Graph"
        case .linearPipeline: "Linear Pipeline"
        case .fanOutFanIn: "Fan-Out/Fan-In"
        case .reviewLoop: "Review Loop"
        case .compendiumFill: "Compendium Fill"
        case .localProcessExample: "Local Process Example"
        }
    }

    var summary: String {
        switch self {
        case .blank: "Start with an empty editable canvas."
        case .linearPipeline: "Three deterministic stages in sequence."
        case .fanOutFanIn: "Parallel branches joined by a final stage."
        case .reviewLoop: "Draft, parallel review, revision, and final review as a DAG."
        case .compendiumFill: "Architect, researcher, graph, and reviewer local processes."
        case .localProcessExample: "Generate, transform, and verify using supervised processes."
        }
    }
}

struct GraphDocumentFileState: Equatable, Sendable {
    let contentDigest: String
    let modificationDate: Date?
    let byteCount: Int

    init(data: Data, modificationDate: Date?) {
        contentDigest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        self.modificationDate = modificationDate
        byteCount = data.count
    }
}

enum GraphDocumentStoreError: Error, Equatable {
    case externallyModified(URL)
}

extension GraphDocumentStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .externallyModified(url):
            "The graph changed on disk after it was opened: \(url.path). Use Revert or Save As."
        }
    }
}

struct GraphNewDocumentRequest: Equatable, Sendable {
    var template: GraphWorkspaceTemplate
    var name: String
    var graphID: String
    var definitionVersion: String
    var description: String
    var defaultRetryMaximumAttempts: Int
    var defaultExecutionTimeoutSeconds: UInt64
    var defaultExecutorKind: String
    var workspaceDirectory: String?

    init(
        template: GraphWorkspaceTemplate = .blank,
        name: String,
        graphID: String,
        definitionVersion: String,
        description: String = "",
        defaultRetryMaximumAttempts: Int = 2,
        defaultExecutionTimeoutSeconds: UInt64 = 300,
        defaultExecutorKind: String = "local_process",
        workspaceDirectory: String? = nil
    ) {
        self.template = template
        self.name = name
        self.graphID = graphID
        self.definitionVersion = definitionVersion
        self.description = description
        self.defaultRetryMaximumAttempts = max(1, defaultRetryMaximumAttempts)
        self.defaultExecutionTimeoutSeconds = max(1, defaultExecutionTimeoutSeconds)
        self.defaultExecutorKind = defaultExecutorKind
        self.workspaceDirectory = workspaceDirectory
    }

    static func defaults(
        id: String = UUID().uuidString.lowercased()
    ) -> GraphNewDocumentRequest {
        GraphNewDocumentRequest(
            template: .blank,
            name: "Untitled Graph",
            graphID: id,
            definitionVersion: "1",
            description: "",
            defaultRetryMaximumAttempts: 2,
            defaultExecutionTimeoutSeconds: 300,
            defaultExecutorKind: "local_process",
            workspaceDirectory: nil
        )
    }
}

enum GraphUnsavedCloseChoice: Equatable, Sendable {
    case save
    case discard
    case cancel
}

enum GraphDocumentCloseState: Equatable, Sendable {
    case idle
    case confirmationRequired
}

struct GraphAuthoringUndoSnapshot: Equatable, Sendable {
    let document: GraphDefinitionDocument
    let selectedNodeIDs: Set<String>
    let selectedEdgeID: String?
}

enum GraphAuthoringMutationKind: Equatable, Sendable {
    case semantic
    case layout
}

enum GraphDefinitionVersioning {
    static func nextVersion(after current: String) -> String {
        if let number = Int(current) {
            return String(number + 1)
        }
        return "\(current).1"
    }
}

enum GraphWorkspaceExecutionBackend: String, CaseIterable, Identifiable, Sendable {
    case supervisedLocalProcess = "Supervised Local Process"
    case deterministicTest = "Deterministic Test Executor"
    case codex = "Codex - not configured"
    case qwen = "Qwen - not configured"
    case ollama = "Ollama - not configured"
    case openClaw = "OpenClaw - not configured"

    var id: String { rawValue }

    var isConfigured: Bool {
        self == .supervisedLocalProcess || self == .deterministicTest
    }
}

struct GraphRunCreationDraft: Equatable, Sendable {
    var backend: GraphWorkspaceExecutionBackend
    var inputValues: [String: String]
    var secretReferences: [String: String]
    var workspaceDirectory: String?

    init(
        backend: GraphWorkspaceExecutionBackend = .supervisedLocalProcess,
        inputValues: [String: String] = [:],
        secretReferences: [String: String] = [:],
        workspaceDirectory: String? = nil
    ) {
        self.backend = backend
        self.inputValues = inputValues
        self.secretReferences = secretReferences
        self.workspaceDirectory = workspaceDirectory
    }

    var resolvedInputIDs: Set<String> {
        Set(inputValues.filter { !$0.value.isEmpty }.map(\.key))
            .union(secretReferences.filter { !$0.value.isEmpty }.map(\.key))
    }
}
