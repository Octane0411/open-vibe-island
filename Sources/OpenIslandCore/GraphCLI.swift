import Darwin
import Foundation

public enum GraphCLIOutputMode: String, Codable, CaseIterable, Sendable {
    case text
    case json
    case jsonl
}

public enum GraphCLIExitCode: Int32, Codable, CaseIterable, Sendable {
    case success = 0
    case invalidArguments = 2
    case notFound = 3
    case incompatibleSchema = 4
    case corruptHistory = 5
    case persistenceFailure = 6
    case evidenceUnavailable = 7
    case partialResult = 8
    case interrupted = 130

    public var category: String {
        switch self {
        case .success:
            "success"
        case .invalidArguments:
            "invalid_arguments"
        case .notFound:
            "not_found"
        case .incompatibleSchema:
            "incompatible_schema"
        case .corruptHistory:
            "corrupt_history"
        case .persistenceFailure:
            "persistence_failure"
        case .evidenceUnavailable:
            "evidence_unavailable"
        case .partialResult:
            "partial_result"
        case .interrupted:
            "interrupted"
        }
    }
}

public enum GraphCLIWriteResult: Equatable, Sendable {
    case written
    case brokenPipe
    case failed(String)
}

public protocol GraphCLIOutputSink: Sendable {
    func write(_ data: Data) -> GraphCLIWriteResult
}

public struct GraphCLIFileDescriptorSink:
    GraphCLIOutputSink,
    Sendable
{
    public let fileDescriptor: Int32

    public init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    public func write(_ data: Data) -> GraphCLIWriteResult {
        guard fcntl(fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            return .failed("Unable to configure output descriptor.")
        }

        return data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else {
                return .written
            }
            var offset = 0

            while offset < buffer.count {
                let count = Darwin.write(
                    fileDescriptor,
                    base.advanced(by: offset),
                    buffer.count - offset
                )

                if count > 0 {
                    offset += count
                } else if count == -1, errno == EINTR {
                    continue
                } else if count == -1, errno == EPIPE {
                    return .brokenPipe
                } else {
                    return .failed(
                        String(cString: strerror(errno))
                    )
                }
            }

            return .written
        }
    }
}

public enum GraphCLIExportFormat: String, Codable, Sendable {
    case json
    case jsonl
    case mermaid
    case terminalWorkspacePlan = "terminal-workspace-plan"
}

public enum GraphCLICommand: Equatable, Sendable {
    case list
    case inspect(runID: String)
    case history(runID: String)
    case explain(runID: String, nodeID: String?)
    case checkpointList(runID: String)
    case replay(runID: String)
    case diff(left: GraphTemporalReference, right: GraphTemporalReference)
    case export(runID: String)

    public var name: String {
        switch self {
        case .list:
            "graph.list"
        case .inspect:
            "graph.inspect"
        case .history:
            "graph.history"
        case .explain:
            "graph.explain"
        case .checkpointList:
            "graph.checkpoint.list"
        case .replay:
            "graph.replay"
        case .diff:
            "graph.diff"
        case .export:
            "graph.export"
        }
    }
}

public struct GraphCLIInvocation: Equatable, Sendable {
    public let command: GraphCLICommand
    public let output: GraphCLIOutputMode
    public let quiet: Bool
    public let noColor: Bool
    public let schemaVersion: Int
    public let nodeID: String?
    public let attemptID: String?
    public let state: ReconciledExecutionState?
    public let eventTypes: Set<String>
    public let since: Date?
    public let until: Date?
    public let afterSequence: UInt64
    public let limit: Int
    public let includeDiagnostics: Bool
    public let includeArtifacts: Bool
    public let toSequence: UInt64?
    public let checkpointID: String?
    public let withoutLiveEvidence: Bool
    public let requireLiveEvidence: Bool
    public let exportFormat: GraphCLIExportFormat
    public let emitCompletionRecord: Bool

    public init(
        command: GraphCLICommand,
        output: GraphCLIOutputMode = .text,
        quiet: Bool = false,
        noColor: Bool = false,
        schemaVersion: Int = GraphCLIOutputSchema.currentVersion,
        nodeID: String? = nil,
        attemptID: String? = nil,
        state: ReconciledExecutionState? = nil,
        eventTypes: Set<String> = [],
        since: Date? = nil,
        until: Date? = nil,
        afterSequence: UInt64 = 0,
        limit: Int = 100,
        includeDiagnostics: Bool = false,
        includeArtifacts: Bool = false,
        toSequence: UInt64? = nil,
        checkpointID: String? = nil,
        withoutLiveEvidence: Bool = false,
        requireLiveEvidence: Bool = false,
        exportFormat: GraphCLIExportFormat = .json,
        emitCompletionRecord: Bool = false
    ) {
        self.command = command
        self.output = output
        self.quiet = quiet
        self.noColor = noColor
        self.schemaVersion = schemaVersion
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.state = state
        self.eventTypes = eventTypes
        self.since = since
        self.until = until
        self.afterSequence = afterSequence
        self.limit = limit
        self.includeDiagnostics = includeDiagnostics
        self.includeArtifacts = includeArtifacts
        self.toSequence = toSequence
        self.checkpointID = checkpointID
        self.withoutLiveEvidence = withoutLiveEvidence
        self.requireLiveEvidence = requireLiveEvidence
        self.exportFormat = exportFormat
        self.emitCompletionRecord = emitCompletionRecord
    }
}

public enum GraphCLIOutputSchema {
    public static let minimumSupportedVersion = 1
    public static let currentVersion = 2
}

public enum GraphCLIArgumentError: Error, Equatable, Sendable {
    case invalid(String)
    case unsupportedSchema(found: Int, supported: Int)
}

extension GraphCLIArgumentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalid(message):
            message
        case let .unsupportedSchema(found, supported):
            "Output schema version \(found) is unsupported; current version is \(supported)."
        }
    }
}

public enum GraphCLIParseResult: Equatable, Sendable {
    case invocation(GraphCLIInvocation)
    case help(String)
}

public enum GraphCLIParser {
    public static func parse(
        _ arguments: [String]
    ) throws -> GraphCLIParseResult {
        if arguments.isEmpty || arguments == ["--help"]
            || arguments == ["help"] {
            return .help(usage)
        }
        guard arguments.first == "graph" else {
            throw GraphCLIArgumentError.invalid(
                "Expected the read-only `graph` command."
            )
        }
        if arguments.count == 1 || arguments[1] == "--help"
            || arguments[1] == "help" {
            return .help(usage)
        }

        let tokens = Array(arguments.dropFirst(2))
        let commandToken = arguments[1]
        var positional: [String] = []
        var values: [String: [String]] = [:]
        var flags = Set<String>()
        var outputWasExplicit = false
        let valueOptions = Set([
            "--output",
            "--schema-version",
            "--node",
            "--attempt",
            "--state",
            "--event-type",
            "--since",
            "--until",
            "--after-sequence",
            "--limit",
            "--to-sequence",
            "--checkpoint",
            "--format",
        ])
        let flagOptions = Set([
            "--no-color",
            "--quiet",
            "--include-diagnostics",
            "--include-artifacts",
            "--dry-run",
            "--without-live-evidence",
            "--require-live-evidence",
            "--emit-completion-record",
        ])
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if valueOptions.contains(token) {
                guard index + 1 < tokens.count else {
                    throw GraphCLIArgumentError.invalid(
                        "Option \(token) requires a value."
                    )
                }
                values[token, default: []].append(tokens[index + 1])
                outputWasExplicit = outputWasExplicit || token == "--output"
                index += 2
            } else if flagOptions.contains(token) {
                flags.insert(token)
                index += 1
            } else if token == "--help" {
                return .help(usage)
            } else if token.hasPrefix("--") {
                throw GraphCLIArgumentError.invalid(
                    "Unknown option \(token)."
                )
            } else {
                positional.append(token)
                index += 1
            }
        }

        let output = try singleValue("--output", values).map {
            guard let mode = GraphCLIOutputMode(rawValue: $0) else {
                throw GraphCLIArgumentError.invalid(
                    "Output must be text, json, or jsonl."
                )
            }
            return mode
        }
        let optionNodeID = try singleValue("--node", values)
        let requestedSchema = try parseInt(
            singleValue("--schema-version", values),
            option: "--schema-version"
        ) ?? GraphCLIOutputSchema.currentVersion
        guard requestedSchema
                >= GraphCLIOutputSchema.minimumSupportedVersion,
              requestedSchema
                <= GraphCLIOutputSchema.currentVersion else {
            throw GraphCLIArgumentError.unsupportedSchema(
                found: requestedSchema,
                supported: GraphCLIOutputSchema.currentVersion
            )
        }
        let state = try singleValue("--state", values).map {
            guard let state = ReconciledExecutionState(rawValue: $0) else {
                throw GraphCLIArgumentError.invalid(
                    "Unknown graph state \($0)."
                )
            }
            return state
        }
        let since = try parseDate(
            singleValue("--since", values),
            option: "--since"
        )
        let until = try parseDate(
            singleValue("--until", values),
            option: "--until"
        )
        if let since, let until, since > until {
            throw GraphCLIArgumentError.invalid(
                "--since must not be later than --until."
            )
        }
        let afterSequence = try parseUInt64(
            singleValue("--after-sequence", values),
            option: "--after-sequence"
        ) ?? 0
        let toSequence = try parseUInt64(
            singleValue("--to-sequence", values),
            option: "--to-sequence"
        )
        let limit = try parseInt(
            singleValue("--limit", values),
            option: "--limit"
        ) ?? 100
        guard (1...1_000_000).contains(limit) else {
            throw GraphCLIArgumentError.invalid(
                "--limit must be between 1 and 1000000."
            )
        }
        let exportFormat = try singleValue("--format", values).map {
            guard let format = GraphCLIExportFormat(rawValue: $0) else {
                throw GraphCLIArgumentError.invalid(
                    "Export format must be json, jsonl, mermaid, or terminal-workspace-plan."
                )
            }
            return format
        } ?? .json
        let command: GraphCLICommand

        switch commandToken {
        case "list":
            try requirePositionals(positional, count: 0, command: "list")
            command = .list
        case "inspect":
            try requirePositionals(
                positional,
                count: 1,
                command: "inspect"
            )
            command = .inspect(runID: positional[0])
        case "history":
            try requirePositionals(
                positional,
                count: 1,
                command: "history"
            )
            command = .history(runID: positional[0])
        case "explain":
            guard (1...2).contains(positional.count) else {
                throw GraphCLIArgumentError.invalid(
                    "Usage: openisland graph explain <run-id> [node-id]"
                )
            }
            if positional.count == 2, optionNodeID != nil {
                throw GraphCLIArgumentError.invalid(
                    "Specify the explanation node either positionally or with --node, not both."
                )
            }
            command = .explain(
                runID: positional[0],
                nodeID: positional.count == 2
                    ? positional[1]
                    : optionNodeID
            )
        case "checkpoint":
            guard positional.count == 2, positional[0] == "list" else {
                throw GraphCLIArgumentError.invalid(
                    "Usage: openisland graph checkpoint list <run-id>"
                )
            }
            command = .checkpointList(runID: positional[1])
        case "replay":
            try requirePositionals(
                positional,
                count: 1,
                command: "replay"
            )
            guard flags.contains("--dry-run") else {
                throw GraphCLIArgumentError.invalid(
                    "`graph replay` requires --dry-run."
                )
            }
            if toSequence != nil,
               try singleValue("--checkpoint", values) != nil {
                throw GraphCLIArgumentError.invalid(
                    "Use either --to-sequence or --checkpoint, not both."
                )
            }
            command = .replay(runID: positional[0])
        case "diff":
            try requirePositionals(
                positional,
                count: 2,
                command: "diff"
            )
            command = .diff(
                left: try parseReference(positional[0]),
                right: try parseReference(positional[1])
            )
        case "export":
            try requirePositionals(
                positional,
                count: 1,
                command: "export"
            )
            command = .export(runID: positional[0])
        default:
            throw GraphCLIArgumentError.invalid(
                "Unknown graph command \(commandToken)."
            )
        }

        var resolvedOutput = output ?? .text
        if case .export = command, !outputWasExplicit {
            switch exportFormat {
            case .json:
                resolvedOutput = .json
            case .jsonl:
                resolvedOutput = .jsonl
            case .mermaid:
                resolvedOutput = .text
            case .terminalWorkspacePlan:
                resolvedOutput = .json
            }
        }
        if flags.contains("--emit-completion-record"),
           resolvedOutput != .jsonl {
            throw GraphCLIArgumentError.invalid(
                "--emit-completion-record requires --output jsonl."
            )
        }
        if flags.contains("--without-live-evidence"),
           flags.contains("--require-live-evidence") {
            throw GraphCLIArgumentError.invalid(
                "--without-live-evidence and --require-live-evidence are mutually exclusive."
            )
        }

        return .invocation(
            GraphCLIInvocation(
                command: command,
                output: resolvedOutput,
                quiet: flags.contains("--quiet"),
                noColor: flags.contains("--no-color"),
                schemaVersion: requestedSchema,
                nodeID: optionNodeID,
                attemptID: try singleValue("--attempt", values),
                state: state,
                eventTypes: Set(values["--event-type"] ?? []),
                since: since,
                until: until,
                afterSequence: afterSequence,
                limit: limit,
                includeDiagnostics:
                    flags.contains("--include-diagnostics"),
                includeArtifacts:
                    flags.contains("--include-artifacts"),
                toSequence: toSequence,
                checkpointID:
                    try singleValue("--checkpoint", values),
                withoutLiveEvidence:
                    flags.contains("--without-live-evidence"),
                requireLiveEvidence:
                    flags.contains("--require-live-evidence"),
                exportFormat: exportFormat,
                emitCompletionRecord:
                    flags.contains("--emit-completion-record")
            )
        )
    }

    public static let usage = """
    Usage:
      openisland graph list [options]
      openisland graph inspect <run-id> [options]
      openisland graph history <run-id> [options]
      openisland graph explain <run-id> [node-id] [options]
      openisland graph checkpoint list <run-id> [options]
      openisland graph replay <run-id> --dry-run [options]
      openisland graph diff <run|run@sequence|run#checkpoint> <reference> [options]
      openisland graph export <run-id> --format json|jsonl|mermaid|terminal-workspace-plan [options]

    Stable output: --output text|json|jsonl --schema-version 1
    Filters: --node --attempt --state --event-type --since --until
             --after-sequence --limit
    Safety: --no-color --quiet --include-diagnostics --include-artifacts
            --without-live-evidence --require-live-evidence
            --emit-completion-record
    """

    private static func singleValue(
        _ option: String,
        _ values: [String: [String]]
    ) throws -> String? {
        guard let found = values[option] else {
            return nil
        }
        guard found.count == 1 else {
            throw GraphCLIArgumentError.invalid(
                "Option \(option) may only be provided once."
            )
        }
        return found[0]
    }

    private static func requirePositionals(
        _ positional: [String],
        count: Int,
        command: String
    ) throws {
        guard positional.count == count else {
            throw GraphCLIArgumentError.invalid(
                "Command \(command) expected \(count) positional argument(s)."
            )
        }
    }

    private static func parseInt(
        _ value: String?,
        option: String
    ) throws -> Int? {
        guard let value else {
            return nil
        }
        guard let result = Int(value) else {
            throw GraphCLIArgumentError.invalid(
                "\(option) requires an integer."
            )
        }
        return result
    }

    private static func parseUInt64(
        _ value: String?,
        option: String
    ) throws -> UInt64? {
        guard let value else {
            return nil
        }
        guard let result = UInt64(value) else {
            throw GraphCLIArgumentError.invalid(
                "\(option) requires a nonnegative integer."
            )
        }
        return result
    }

    private static func parseDate(
        _ value: String?,
        option: String
    ) throws -> Date? {
        guard let value else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]

        guard let result = fractional.date(from: value)
                ?? standard.date(from: value) else {
            throw GraphCLIArgumentError.invalid(
                "\(option) requires an ISO 8601 UTC date."
            )
        }
        return result
    }

    private static func parseReference(
        _ value: String
    ) throws -> GraphTemporalReference {
        if let marker = value.lastIndex(of: "#") {
            let runID = String(value[..<marker])
            let checkpoint = String(value[value.index(after: marker)...])
            guard !runID.isEmpty, !checkpoint.isEmpty else {
                throw GraphCLIArgumentError.invalid(
                    "Invalid checkpoint reference \(value)."
                )
            }
            return GraphTemporalReference(
                runID: runID,
                boundary: .checkpoint(checkpoint)
            )
        }
        if let marker = value.lastIndex(of: "@") {
            let runID = String(value[..<marker])
            let sequenceText = String(
                value[value.index(after: marker)...]
            )
            guard !runID.isEmpty,
                  let sequence = UInt64(sequenceText) else {
                throw GraphCLIArgumentError.invalid(
                    "Invalid stream reference \(value)."
                )
            }
            return GraphTemporalReference(
                runID: runID,
                boundary: .sequence(sequence)
            )
        }
        guard !value.isEmpty else {
            throw GraphCLIArgumentError.invalid(
                "Run reference may not be empty."
            )
        }
        return GraphTemporalReference(runID: value)
    }
}

public struct GraphCLICompletionRecord:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let recordType: String
    public let command: String
    public let status: String
    public let exitCode: Int32
    public let resultCount: Int
    public let eventCount: Int
    public let lastSequence: UInt64?
    public let context: GraphCLIExecutionContext?

    public init(
        schemaVersion: Int = GraphCLIOutputSchema.currentVersion,
        command: String,
        status: String,
        exitCode: Int32,
        resultCount: Int,
        eventCount: Int,
        lastSequence: UInt64?,
        context: GraphCLIExecutionContext? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.recordType = "completion"
        self.command = command
        self.status = status
        self.exitCode = exitCode
        self.resultCount = resultCount
        self.eventCount = eventCount
        self.lastSequence = lastSequence
        self.context = context
    }
}

public struct GraphCLIOutputDiagnostic:
    Equatable,
    Codable,
    Sendable
{
    public let category: String
    public let severity: String
    public let message: String
}

public struct GraphCLIOutputDocument<Payload: Encodable>: Encodable {
    public let schemaVersion: Int
    public let command: String
    public let resultCount: Int
    public let eventCount: Int
    public let result: Payload
    public let diagnostics: [GraphCLIOutputDiagnostic]?
    public let context: GraphCLIExecutionContext?

    public init(
        schemaVersion: Int = GraphCLIOutputSchema.currentVersion,
        command: String,
        resultCount: Int,
        eventCount: Int,
        result: Payload,
        diagnostics: [GraphCLIOutputDiagnostic]? = nil,
        context: GraphCLIExecutionContext? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.resultCount = resultCount
        self.eventCount = eventCount
        self.result = result
        self.diagnostics = diagnostics
        self.context = context
    }
}

public struct GraphCLIJSONLRecord<Payload: Encodable>: Encodable {
    public let schemaVersion: Int
    public let command: String
    public let recordType: String
    public let ordinal: Int
    public let payload: Payload
    public let context: GraphCLIExecutionContext?

    public init(
        schemaVersion: Int = GraphCLIOutputSchema.currentVersion,
        command: String,
        recordType: String,
        ordinal: Int,
        payload: Payload,
        context: GraphCLIExecutionContext? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.recordType = recordType
        self.ordinal = ordinal
        self.payload = payload
        self.context = context
    }
}

public struct GraphReplayOutput:
    Equatable,
    Codable,
    Sendable
{
    public let runID: String
    public let boundary: UInt64
    public let headVersion: UInt64
    public let snapshotDisposition: GraphSnapshotDisposition
    public let snapshotStreamVersion: UInt64?
    public let replayedEventCount: Int
    public let projectedRunState: ReconciledExecutionState
    public let reconciledRunState: ReconciledExecutionState
    public let projectedNodes: [GraphStateOutput]
    public let reconciledNodes: [GraphStateOutput]
    public let projectedAttempts: [GraphStateOutput]
    public let reconciledAttempts: [GraphStateOutput]
    public let evidence: GraphEvidenceInspection
    public let unknownEvents: [GraphUnknownEventOutput]
    public let replayDiagnostics: [GraphReplayDiagnostic]
    public let repositoryDiagnostics: [GraphRepositoryDiagnostic]
}

public struct GraphUnknownEventOutput:
    Equatable,
    Codable,
    Sendable
{
    public let eventID: String
    public let eventType: String
    public let streamSequence: UInt64
    public let payloadVersion: Int
    public let redactions: [GraphRedactionRecord]
}

public struct GraphStateOutput:
    Equatable,
    Codable,
    Sendable
{
    public let id: String
    public let state: ReconciledExecutionState
}

public struct GraphMermaidExport:
    Equatable,
    Codable,
    Sendable
{
    public let format: String
    public let content: String

    public init(content: String) {
        self.format = "mermaid"
        self.content = content
    }
}

public enum GraphMermaidExporter {
    public static func render(_ inspection: GraphRunInspection) -> String {
        let nodes = inspection.nodes.sorted { $0.id < $1.id }
        let attempts = inspection.attempts.sorted {
            if $0.nodeID != $1.nodeID {
                return $0.nodeID < $1.nodeID
            }
            if $0.ordinal != $1.ordinal {
                return $0.ordinal < $1.ordinal
            }
            return $0.id < $1.id
        }
        let artifacts = inspection.artifacts.sorted { $0.id < $1.id }
        let nodeNames = Dictionary(
            uniqueKeysWithValues: nodes.enumerated().map {
                ($0.element.id, "node_\($0.offset)")
            }
        )
        let attemptNames = Dictionary(
            uniqueKeysWithValues: attempts.enumerated().map {
                ($0.element.id, "attempt_\($0.offset)")
            }
        )
        var lines = ["flowchart TD"]

        for node in nodes {
            guard let identifier = nodeNames[node.id] else {
                continue
            }
            lines.append(
                "  \(identifier)[\"\(escape(node.title))\\n\(escape(node.reconciledState.rawValue))\"]"
            )
            lines.append(
                "  class \(identifier) state_\(node.reconciledState.rawValue)"
            )
        }
        for node in nodes {
            guard let target = nodeNames[node.id] else {
                continue
            }
            for dependency in node.dependencyNodeIDs.sorted() {
                if let source = nodeNames[dependency] {
                    lines.append(
                        "  \(source) -->|dependency| \(target)"
                    )
                }
            }
        }
        for attempt in attempts {
            guard let identifier = attemptNames[attempt.id] else {
                continue
            }
            lines.append(
                "  \(identifier)((\"\(escape(attempt.id))\\n\(escape(attempt.reconciledState.rawValue))\"))"
            )
            lines.append(
                "  class \(identifier) state_\(attempt.reconciledState.rawValue)"
            )
            if let node = nodeNames[attempt.nodeID] {
                lines.append("  \(node) -.->|attempt| \(identifier)")
            }
        }
        for (index, artifact) in artifacts.enumerated() {
            let identifier = "artifact_\(index)"
            lines.append(
                "  \(identifier)[/\"\(escape(artifact.logicalRole))\"/]"
            )
            if let attempt = attemptNames[artifact.producingAttemptID] {
                lines.append(
                    "  \(attempt) ==>|provenance| \(identifier)"
                )
            }
        }
        for state in ReconciledExecutionState.allCases {
            lines.append(
                "  classDef state_\(state.rawValue) stroke-width:2px"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public struct GraphCLICommandRunner: Sendable {
    private let inspector: any GraphTemporalInspecting
    private let stdout: any GraphCLIOutputSink
    private let stderr: any GraphCLIOutputSink
    private let context: GraphCLIExecutionContext?
    private let telemetry: any GraphCLITelemetrySink
    private let clock: any GraphCLIMonotonicClock
    private let isOutputTTY: Bool

    public init(
        inspector: any GraphTemporalInspecting,
        stdout: any GraphCLIOutputSink,
        stderr: any GraphCLIOutputSink,
        context: GraphCLIExecutionContext? = nil,
        telemetry: any GraphCLITelemetrySink =
            NoopGraphCLITelemetrySink(),
        clock: any GraphCLIMonotonicClock =
            SystemGraphCLIMonotonicClock(),
        isOutputTTY: Bool = true
    ) {
        self.inspector = inspector
        self.stdout = stdout
        self.stderr = stderr
        self.context = context
        self.telemetry = telemetry
        self.clock = clock
        self.isOutputTTY = isOutputTTY
    }

    public func run(arguments: [String]) async -> GraphCLIExitCode {
        let started = clock.nowNanoseconds()
        let parsed: GraphCLIParseResult

        do {
            parsed = try GraphCLIParser.parse(arguments)
        } catch let error as GraphCLIArgumentError {
            let code: GraphCLIExitCode
            if case .unsupportedSchema = error {
                code = .incompatibleSchema
            } else {
                code = .invalidArguments
            }
            writeError(error.localizedDescription, code: code)
            recordTelemetry(
                command: "graph.invalid",
                output: .text,
                outcome: GraphCLICommandOutcome(exitCode: code),
                started: started
            )
            return code
        } catch {
            writeError(
                error.localizedDescription,
                code: .invalidArguments
            )
            recordTelemetry(
                command: "graph.invalid",
                output: .text,
                outcome: GraphCLICommandOutcome(
                    exitCode: .invalidArguments
                ),
                started: started
            )
            return .invalidArguments
        }

        switch parsed {
        case let .help(text):
            _ = stdout.write(Data((text + "\n").utf8))
            recordTelemetry(
                command: "graph.help",
                output: .text,
                outcome: GraphCLICommandOutcome(exitCode: .success),
                started: started
            )
            return .success
        case let .invocation(invocation):
            do {
                let outcome = invocation.quiet
                    ? try await execute(
                        invocation,
                        suppressOutput: true
                    )
                    : try await execute(invocation)
                recordTelemetry(
                    command: invocation.command.name,
                    output: invocation.output,
                    outcome: outcome,
                    started: started
                )
                return outcome.exitCode
            } catch {
                let code = exitCode(for: error)
                writeError(error.localizedDescription, code: code)
                recordTelemetry(
                    command: invocation.command.name,
                    output: invocation.output,
                    outcome: GraphCLICommandOutcome(
                        exitCode: code
                    ),
                    started: started
                )
                return code
            }
        }
    }

    private func execute(
        _ invocation: GraphCLIInvocation,
        suppressOutput: Bool = false
    ) async throws -> GraphCLICommandOutcome {
        switch invocation.command {
        case .list:
            var summaries = try await inspector.listRuns(
                state: invocation.state,
                limit: invocation.limit
            )
            summaries = filterSummaries(summaries, invocation)
            let code = try emit(
                summaries,
                recordType: "run",
                text: renderSummaries(summaries),
                invocation: invocation,
                resultCount: summaries.count,
                eventCount: 0,
                suppressOutput: suppressOutput
            )
            return GraphCLICommandOutcome(
                exitCode: code,
                resultCount: summaries.count
            )
        case let .inspect(runID):
            let inspection = try await inspector.inspect(
                runID: runID,
                includeArtifacts: invocation.includeArtifacts,
                includeDiagnostics: invocation.includeDiagnostics
            )
            let filtered = filterInspection(inspection, invocation)
            let code = try emit(
                filtered,
                records: [filtered],
                recordType: "inspection",
                text: renderInspection(filtered),
                invocation: invocation,
                resultCount: 1,
                eventCount: 0,
                suppressOutput: suppressOutput,
                diagnostics: diagnostics(filtered)
            )
            return GraphCLICommandOutcome(
                exitCode: code,
                resultCount: 1,
                replayBoundary: filtered.summary.streamVersion,
                snapshotDisposition:
                    filtered.summary.snapshotDisposition,
                reconciliationOutcome:
                    filtered.summary.reconciledState.rawValue
            )
        case let .history(runID):
            return try await emitHistory(
                runID: runID,
                invocation: invocation,
                suppressOutput: suppressOutput
            )
        case let .explain(runID, positionalNodeID):
            let inspectedExplanation = try await inspector.explain(
                runID: runID,
                nodeID: invocation.nodeID ?? positionalNodeID
            )
            let explanation = filterExplanation(
                inspectedExplanation,
                invocation
            )
            let code = try emit(
                explanation,
                records: [explanation],
                recordType: "explanation",
                text: renderExplanation(explanation),
                invocation: invocation,
                resultCount: 1,
                eventCount: 0,
                suppressOutput: suppressOutput
            )
            return GraphCLICommandOutcome(
                exitCode: code,
                resultCount: 1,
                reconciliationOutcome: explanation.state.rawValue
            )
        case let .checkpointList(runID):
            let checkpoints = try await inspector.checkpoints(
                runID: runID
            )
            let code = try emit(
                checkpoints,
                recordType: "checkpoint",
                text: renderCheckpoints(checkpoints),
                invocation: invocation,
                resultCount: checkpoints.count,
                eventCount: 0,
                suppressOutput: suppressOutput
            )
            return GraphCLICommandOutcome(
                exitCode: code,
                resultCount: checkpoints.count
            )
        case let .replay(runID):
            let boundary: GraphReplayBoundary
            if let sequence = invocation.toSequence {
                boundary = .sequence(sequence)
            } else if let checkpoint = invocation.checkpointID {
                boundary = .checkpoint(checkpoint)
            } else {
                boundary = .head
            }
            let replay = try await inspector.replay(
                reference: GraphTemporalReference(
                    runID: runID,
                    boundary: boundary
                ),
                evidenceMode: invocation.withoutLiveEvidence
                    ? .withoutLiveEvidence
                    : invocation.requireLiveEvidence
                        ? .requireAvailable
                        : .configured
            )
            let output = try replayOutput(replay)
            let code = try emit(
                output,
                records: [output],
                recordType: "replay",
                text: renderReplay(output),
                invocation: invocation,
                resultCount: 1,
                eventCount: replay.replayedEventCount,
                suppressOutput: suppressOutput,
                diagnostics: invocation.includeDiagnostics
                    ? diagnostics(replay)
                    : []
            )
            return GraphCLICommandOutcome(
                exitCode: code,
                resultCount: 1,
                eventCount: replay.replayedEventCount,
                replayBoundary: replay.boundary,
                snapshotDisposition: replay.snapshotDisposition,
                reconciliationOutcome:
                    output.reconciledRunState.rawValue
            )
        case let .diff(left, right):
            let diff = filterDiff(
                try await inspector.diff(left: left, right: right),
                invocation
            )
            let code = try emit(
                diff,
                records: diff.changes,
                recordType: "change",
                text: renderDiff(diff),
                invocation: invocation,
                resultCount: diff.changes.count,
                eventCount: 0,
                suppressOutput: suppressOutput
            )
            return GraphCLICommandOutcome(
                exitCode: code,
                resultCount: diff.changes.count
            )
        case let .export(runID):
            let inspection = filterInspection(
                try await inspector.inspect(
                    runID: runID,
                    includeArtifacts: true,
                    includeDiagnostics: invocation.includeDiagnostics
                ),
                invocation
            )
            let code = try emitExport(
                inspection,
                invocation: invocation,
                suppressOutput: suppressOutput
            )
            return GraphCLICommandOutcome(
                exitCode: code,
                resultCount:
                    inspection.nodes.count
                        + inspection.attempts.count
                        + inspection.artifacts.count,
                replayBoundary: inspection.summary.streamVersion,
                snapshotDisposition:
                    inspection.summary.snapshotDisposition,
                reconciliationOutcome:
                    inspection.summary.reconciledState.rawValue
            )
        }
    }

    private func emitHistory(
        runID: String,
        invocation: GraphCLIInvocation,
        suppressOutput: Bool
    ) async throws -> GraphCLICommandOutcome {
        var cursor = invocation.afterSequence
        var remaining = invocation.limit
        var records: [GraphInspectionEventRecord] = []
        var emitted = 0
        var ordinal = 0
        var hasMore = true

        while remaining > 0, hasMore {
            let page = try await inspector.eventPage(
                runID: runID,
                filter: GraphInspectionEventFilter(
                    nodeID: invocation.nodeID,
                    attemptID: invocation.attemptID,
                    eventTypes: invocation.eventTypes,
                    since: invocation.since,
                    until: invocation.until,
                    afterSequence: cursor,
                    limit: min(remaining, 256)
                )
            )
            cursor = page.scannedThroughSequence
            hasMore = page.hasMore
            remaining -= page.events.count

            if suppressOutput {
                emitted += page.events.count
                continue
            }

            switch invocation.output {
            case .json:
                records.append(contentsOf: page.events)
            case .text:
                for event in page.events {
                    let result = writeLine(renderEvent(event))
                    if result == .brokenPipe {
                        return GraphCLICommandOutcome(
                            exitCode: .success,
                            resultCount: emitted,
                            eventCount: emitted,
                            replayBoundary: cursor
                        )
                    }
                    try requireWrite(result)
                    emitted += 1
                }
            case .jsonl:
                for event in page.events {
                    ordinal += 1
                    let record = GraphCLIJSONLRecord(
                        schemaVersion: invocation.schemaVersion,
                        command: invocation.command.name,
                        recordType: "event",
                        ordinal: ordinal,
                        payload: event,
                        context: context
                    )
                    let result = writeLine(
                        try encodeString(record)
                    )
                    if result == .brokenPipe {
                        return GraphCLICommandOutcome(
                            exitCode: .success,
                            resultCount: emitted,
                            eventCount: emitted,
                            replayBoundary: cursor
                        )
                    }
                    try requireWrite(result)
                    emitted += 1
                }
            }

            if page.events.isEmpty, !page.hasMore {
                break
            }
        }

        if suppressOutput {
            return GraphCLICommandOutcome(
                exitCode: .success,
                resultCount: emitted,
                eventCount: emitted,
                replayBoundary: cursor
            )
        }
        if invocation.output == .json {
            emitted = records.count
            let document = GraphCLIOutputDocument(
                schemaVersion: invocation.schemaVersion,
                command: invocation.command.name,
                resultCount: records.count,
                eventCount: records.count,
                result: records,
                context: context
            )
            let result = writeLine(try encodeString(document))
            if result == .brokenPipe {
                return GraphCLICommandOutcome(
                    exitCode: .success,
                    resultCount: emitted,
                    eventCount: emitted,
                    replayBoundary: cursor
                )
            }
            try requireWrite(result)
        }
        if invocation.output == .jsonl,
           invocation.emitCompletionRecord {
            let completion = GraphCLICompletionRecord(
                schemaVersion: invocation.schemaVersion,
                command: invocation.command.name,
                status: GraphCLIExitCode.success.category,
                exitCode: GraphCLIExitCode.success.rawValue,
                resultCount: emitted,
                eventCount: emitted,
                lastSequence: cursor,
                context: context
            )
            let result = writeLine(try encodeString(completion))
            if result != .brokenPipe {
                try requireWrite(result)
            }
        }
        return GraphCLICommandOutcome(
            exitCode: .success,
            resultCount: emitted,
            eventCount: emitted,
            replayBoundary: cursor
        )
    }

    private func emit<Payload: Encodable, Record: Encodable>(
        _ payload: Payload,
        records: [Record],
        recordType: String,
        text: String,
        invocation: GraphCLIInvocation,
        resultCount: Int,
        eventCount: Int,
        suppressOutput: Bool,
        diagnostics: [GraphCLIOutputDiagnostic] = []
    ) throws -> GraphCLIExitCode {
        guard !suppressOutput else {
            return .success
        }
        let result: GraphCLIWriteResult

        switch invocation.output {
        case .text:
            result = stdout.write(Data(text.utf8))
        case .json:
            result = writeLine(
                try encodeString(
                    GraphCLIOutputDocument(
                        schemaVersion: invocation.schemaVersion,
                        command: invocation.command.name,
                        resultCount: resultCount,
                        eventCount: eventCount,
                        result: payload,
                        diagnostics: diagnostics.isEmpty
                            ? nil
                            : diagnostics,
                        context: context
                    )
                )
            )
        case .jsonl:
            var ordinal = 0
            for recordPayload in records {
                ordinal += 1
                let line = try encodeString(
                    GraphCLIJSONLRecord(
                        schemaVersion: invocation.schemaVersion,
                        command: invocation.command.name,
                        recordType: recordType,
                        ordinal: ordinal,
                        payload: recordPayload,
                        context: context
                    )
                )
                let writeResult = writeLine(line)
                if writeResult == .brokenPipe {
                    return .success
                }
                try requireWrite(writeResult)
            }
            if invocation.emitCompletionRecord {
                let completion = GraphCLICompletionRecord(
                    schemaVersion: invocation.schemaVersion,
                    command: invocation.command.name,
                    status: GraphCLIExitCode.success.category,
                    exitCode: GraphCLIExitCode.success.rawValue,
                    resultCount: resultCount,
                    eventCount: eventCount,
                    lastSequence: nil,
                    context: context
                )
                let writeResult = writeLine(
                    try encodeString(completion)
                )
                if writeResult != .brokenPipe {
                    try requireWrite(writeResult)
                }
            }
            return .success
        }

        if result == .brokenPipe {
            return .success
        }
        try requireWrite(result)
        return .success
    }

    private func emit<Payload: Encodable>(
        _ payload: [Payload],
        recordType: String,
        text: String,
        invocation: GraphCLIInvocation,
        resultCount: Int,
        eventCount: Int,
        suppressOutput: Bool
    ) throws -> GraphCLIExitCode {
        try emit(
            payload,
            records: payload,
            recordType: recordType,
            text: text,
            invocation: invocation,
            resultCount: resultCount,
            eventCount: eventCount,
            suppressOutput: suppressOutput
        )
    }

    private func emitExport(
        _ inspection: GraphRunInspection,
        invocation: GraphCLIInvocation,
        suppressOutput: Bool
    ) throws -> GraphCLIExitCode {
        switch invocation.exportFormat {
        case .json, .jsonl:
            let records: [GraphExportEntity] =
                inspection.nodes.map {
                    GraphExportEntity(
                        kind: "node",
                        id: $0.id,
                        state: $0.reconciledState.rawValue,
                        role: nil
                    )
                }
                + inspection.attempts.map {
                    GraphExportEntity(
                        kind: "attempt",
                        id: $0.id,
                        state: $0.reconciledState.rawValue,
                        role: nil
                    )
                }
                + inspection.artifacts.map {
                    GraphExportEntity(
                        kind: "artifact",
                        id: $0.id,
                        state: nil,
                        role: $0.logicalRole
                    )
                }
            return try emit(
                inspection,
                records: records,
                recordType: "graph_entity",
                text: renderInspection(inspection),
                invocation: invocation,
                resultCount: records.count,
                eventCount: 0,
                suppressOutput: suppressOutput,
                diagnostics: diagnostics(inspection)
            )
        case .mermaid:
            let mermaid = GraphMermaidExporter.render(inspection)
            return try emit(
                GraphMermaidExport(content: mermaid),
                records: [GraphMermaidExport(content: mermaid)],
                recordType: "mermaid",
                text: mermaid,
                invocation: invocation,
                resultCount: 1,
                eventCount: 0,
                suppressOutput: suppressOutput
            )
        case .terminalWorkspacePlan:
            let plan = GraphTerminalWorkspacePlanBuilder.build(
                inspection: inspection,
                workspaceContext: context?.workspace
            )
            return try emit(
                plan,
                records: [plan],
                recordType: "terminal_workspace_plan",
                text: renderWorkspacePlan(plan),
                invocation: invocation,
                resultCount:
                    plan.terminals.count + plan.connections.count,
                eventCount: 0,
                suppressOutput: suppressOutput
            )
        }
    }

    private func filterSummaries(
        _ summaries: [GraphRunInspectionSummary],
        _ invocation: GraphCLIInvocation
    ) -> [GraphRunInspectionSummary] {
        summaries.filter {
            invocation.state == nil
                || $0.reconciledState == invocation.state
        }
    }

    private func filterInspection(
        _ inspection: GraphRunInspection,
        _ invocation: GraphCLIInvocation
    ) -> GraphRunInspection {
        let nodes = inspection.nodes.filter {
            (invocation.nodeID == nil || $0.id == invocation.nodeID)
                && (invocation.state == nil
                    || $0.reconciledState == invocation.state)
        }
        let attempts = inspection.attempts.filter {
            (invocation.nodeID == nil
                || $0.nodeID == invocation.nodeID)
                && (invocation.attemptID == nil
                    || $0.id == invocation.attemptID)
                && (invocation.state == nil
                    || $0.reconciledState == invocation.state)
        }
        let artifacts = inspection.artifacts.filter {
            invocation.nodeID == nil
                || $0.producingNodeID == invocation.nodeID
        }
        let scheduling = invocation.schemaVersion >= 2
            ? filteredScheduling(
                inspection.scheduling,
                nodeID: invocation.nodeID,
                attemptID: invocation.attemptID
            )
            : nil
        return GraphRunInspection(
            summary: inspection.summary,
            nodes: nodes,
            attempts: attempts,
            checkpoints: inspection.checkpoints,
            artifacts: artifacts,
            artifactsIncluded: inspection.artifactsIncluded,
            parentRunID: inspection.parentRunID,
            parentCheckpoint: inspection.parentCheckpoint,
            checkpointNamespace: inspection.checkpointNamespace,
            graphDefinitionVersion:
                inspection.graphDefinitionVersion,
            graphDefinitionDigest:
                inspection.graphDefinitionDigest,
            scheduling: scheduling,
            replayDiagnostics: inspection.replayDiagnostics,
            repositoryDiagnostics: inspection.repositoryDiagnostics
        )
    }

    private func filteredScheduling(
        _ scheduling: GraphSchedulingInspection?,
        nodeID: String?,
        attemptID: String?
    ) -> GraphSchedulingInspection? {
        guard let scheduling else { return nil }
        guard nodeID != nil || attemptID != nil else { return scheduling }
        let nodeMatches: (String) -> Bool = {
            nodeID == nil || $0 == nodeID
        }
        let attemptMatches: (String?) -> Bool = {
            attemptID == nil || $0 == attemptID
        }
        return GraphSchedulingInspection(
            schemaVersion: scheduling.schemaVersion,
            latestEvaluation: scheduling.latestEvaluation,
            currentPolicy: scheduling.currentPolicy,
            activeClaims: scheduling.activeClaims.filter {
                nodeMatches($0.nodeID)
            },
            claimHistory: scheduling.claimHistory.filter {
                nodeMatches($0.nodeID)
            },
            retries: scheduling.retries.filter {
                nodeMatches($0.nodeID)
                    && attemptMatches($0.failedAttemptID)
            },
            pendingCancellations:
                scheduling.pendingCancellations.filter {
                    nodeMatches($0.nodeID)
                        && attemptMatches($0.attemptID)
                },
            cancellationHistory:
                scheduling.cancellationHistory.filter {
                    nodeMatches($0.nodeID)
                        && attemptMatches($0.attemptID)
                },
            timeouts: scheduling.timeouts.filter {
                nodeMatches($0.nodeID)
                    && attemptMatches($0.attemptID)
            },
            reasonCodes: scheduling.reasonCodes,
            records: scheduling.records.filter {
                ($0.nodeID == nil || nodeMatches($0.nodeID!))
                    && attemptMatches($0.attemptID)
            }
        )
    }

    private func filterExplanation(
        _ explanation: GraphCausalExplanation,
        _ invocation: GraphCLIInvocation
    ) -> GraphCausalExplanation {
        guard invocation.schemaVersion == 1 else { return explanation }
        return GraphCausalExplanation(
            runID: explanation.runID,
            nodeID: explanation.nodeID,
            state: explanation.state,
            summary: explanation.summary,
            reasons: explanation.reasons,
            edges: explanation.edges,
            shortestCausalChain: explanation.shortestCausalChain,
            causalPredecessorNodeIDs:
                explanation.causalPredecessorNodeIDs,
            blockingDependencyNodeIDs:
                explanation.blockingDependencyNodeIDs,
            readinessRequirements: explanation.readinessRequirements,
            schedulerReasons: nil,
            ignoredInputs: explanation.ignoredInputs
        )
    }

    private func filterDiff(
        _ diff: GraphTemporalDiffResult,
        _ invocation: GraphCLIInvocation
    ) -> GraphTemporalDiffResult {
        guard invocation.schemaVersion == 1 else { return diff }
        let schedulingCategories: Set<GraphTemporalChangeCategory> = [
            .scheduler,
            .claim,
            .retry,
            .cancellation,
            .timeout,
        ]
        return GraphTemporalDiffResult(
            left: diff.left,
            right: diff.right,
            leftBoundary: diff.leftBoundary,
            rightBoundary: diff.rightBoundary,
            changes: diff.changes.filter {
                !schedulingCategories.contains($0.category)
            }
        )
    }

    private func replayOutput(
        _ replay: GraphTemporalReplayResult
    ) throws -> GraphReplayOutput {
        guard let projectedRun = replay.projected.run else {
            throw GraphInspectionError.corruptHistory(
                "Run \(replay.runID) has no run projection."
            )
        }
        return GraphReplayOutput(
            runID: replay.runID,
            boundary: replay.boundary,
            headVersion: replay.headVersion,
            snapshotDisposition: replay.snapshotDisposition,
            snapshotStreamVersion: replay.snapshotStreamVersion,
            replayedEventCount: replay.replayedEventCount,
            projectedRunState: projectedRun.state,
            reconciledRunState:
                replay.reconciled?.run.state
                    ?? projectedRun.state,
            projectedNodes: replay.projected.nodes.map {
                GraphStateOutput(id: $0.id, state: $0.state)
            }.sorted { $0.id < $1.id },
            reconciledNodes: (replay.reconciled?.nodes ?? []).map {
                GraphStateOutput(id: $0.id, state: $0.state)
            }.sorted { $0.id < $1.id },
            projectedAttempts: replay.projected.attempts.map {
                GraphStateOutput(id: $0.id, state: $0.state)
            }.sorted { $0.id < $1.id },
            reconciledAttempts:
                (replay.reconciled?.attempts ?? []).map {
                    GraphStateOutput(id: $0.id, state: $0.state)
                }.sorted { $0.id < $1.id },
            evidence: replay.evidence,
            unknownEvents: replay.projected.unknownEvents.map {
                GraphUnknownEventOutput(
                    eventID: $0.id,
                    eventType: $0.eventType,
                    streamSequence: $0.streamSequence,
                    payloadVersion: $0.payloadVersion,
                    redactions: [
                        GraphRedactionRecord(
                            field: "payload",
                            reason: .unsupportedPayload
                        ),
                    ]
                )
            }.sorted {
                if $0.streamSequence != $1.streamSequence {
                    return $0.streamSequence < $1.streamSequence
                }
                return $0.eventID < $1.eventID
            },
            replayDiagnostics: replay.replayDiagnostics,
            repositoryDiagnostics: replay.repositoryDiagnostics
        )
    }

    private func diagnostics(
        _ inspection: GraphRunInspection
    ) -> [GraphCLIOutputDiagnostic] {
        inspection.replayDiagnostics.map {
            GraphCLIOutputDiagnostic(
                category: $0.category.rawValue,
                severity: $0.severity.rawValue,
                message: $0.message
            )
        } + inspection.repositoryDiagnostics.map {
            GraphCLIOutputDiagnostic(
                category: $0.category.rawValue,
                severity: "information",
                message: $0.message
            )
        }
    }

    private func diagnostics(
        _ replay: GraphTemporalReplayResult
    ) -> [GraphCLIOutputDiagnostic] {
        replay.replayDiagnostics.map {
            GraphCLIOutputDiagnostic(
                category: $0.category.rawValue,
                severity: $0.severity.rawValue,
                message: $0.message
            )
        } + replay.repositoryDiagnostics.map {
            GraphCLIOutputDiagnostic(
                category: $0.category.rawValue,
                severity: "information",
                message: $0.message
            )
        }
    }

    private func renderSummaries(
        _ summaries: [GraphRunInspectionSummary]
    ) -> String {
        guard !summaries.isEmpty else {
            return "No graph runs.\n"
        }
        return summaries.map {
            "\($0.runID)  \($0.reconciledState.rawValue)  v\($0.streamVersion)  \($0.nodeCount) nodes"
        }.joined(separator: "\n") + "\n"
    }

    private func renderInspection(
        _ inspection: GraphRunInspection
    ) -> String {
        var lines = [
            "\(inspection.summary.runID)  \(inspection.summary.reconciledState.rawValue)  v\(inspection.summary.streamVersion)",
        ]
        for node in inspection.nodes {
            lines.append(
                "  \(node.id)  \(node.reconciledState.rawValue)  \(node.title)"
            )
        }
        for attempt in inspection.attempts {
            lines.append(
                "    \(attempt.id)  attempt \(attempt.ordinal)  \(attempt.reconciledState.rawValue)"
            )
        }
        if let scheduling = inspection.scheduling {
            for claim in scheduling.activeClaims {
                lines.append(
                    "    claim \(claim.id)  \(claim.nodeID)  generation \(claim.leaseGeneration)  expires \(graphCLIISO8601(claim.leaseExpiry))"
                )
            }
            for retry in scheduling.retries {
                lines.append(
                    "    retry \(retry.nodeID)#\(retry.nextAttemptOrdinal)  eligible \(graphCLIISO8601(retry.eligibleAt))"
                )
            }
            for cancellation in scheduling.pendingCancellations {
                lines.append(
                    "    cancellation \(cancellation.id)  \(cancellation.state.rawValue)"
                )
            }
            for timeout in scheduling.timeouts {
                lines.append(
                    "    timeout \(timeout.id)  \(timeout.kind.rawValue)"
                )
            }
        }
        if inspection.artifactsIncluded {
            for artifact in inspection.artifacts {
                lines.append(
                    "    artifact \(artifact.id)  \(artifact.logicalRole)"
                )
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderEvent(
        _ event: GraphInspectionEventRecord
    ) -> String {
        "\(event.streamSequence)  \(event.eventType)  \(event.id)"
    }

    private func renderExplanation(
        _ explanation: GraphCausalExplanation
    ) -> String {
        var lines = [explanation.summary]
        for reason in explanation.reasons {
            lines.append("  \(reason.code.rawValue): \(reason.message)")
        }
        for requirement in explanation.readinessRequirements {
            lines.append("  requires: \(requirement)")
        }
        for reason in explanation.schedulerReasons ?? [] {
            lines.append("  scheduler: \(reason.rawValue)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderCheckpoints(
        _ checkpoints: [GraphCheckpointReference]
    ) -> String {
        guard !checkpoints.isEmpty else {
            return "No checkpoints.\n"
        }
        return checkpoints.map {
            "\($0.checkpointID)  v\($0.streamVersion)  \($0.namespace)"
        }.joined(separator: "\n") + "\n"
    }

    private func renderReplay(_ replay: GraphReplayOutput) -> String {
        "\(replay.runID)  boundary v\(replay.boundary)/\(replay.headVersion)  projected \(replay.projectedRunState.rawValue)  reconciled \(replay.reconciledRunState.rawValue)  snapshot \(replay.snapshotDisposition.rawValue)\n"
    }

    private func renderDiff(_ diff: GraphTemporalDiffResult) -> String {
        guard !diff.changes.isEmpty else {
            return "No semantic changes.\n"
        }
        return diff.changes.map {
            "\($0.category.rawValue) \($0.entityID).\($0.field): \($0.left ?? "<absent>") -> \($0.right ?? "<absent>")"
        }.joined(separator: "\n") + "\n"
    }

    private func renderWorkspacePlan(
        _ plan: GraphTerminalWorkspacePlan
    ) -> String {
        "\(plan.planID)  \(plan.terminals.count) terminals  \(plan.connections.count) connections  authority \(plan.authority)\n"
    }

    private func writeLine(_ string: String) -> GraphCLIWriteResult {
        stdout.write(Data((string + (string.hasSuffix("\n") ? "" : "\n")).utf8))
    }

    private func requireWrite(
        _ result: GraphCLIWriteResult
    ) throws {
        if case let .failed(message) = result {
            throw GraphInspectionError.persistence(
                "Unable to write command output: \(message)"
            )
        }
    }

    private func writeError(
        _ message: String?,
        code: GraphCLIExitCode
    ) {
        let safe = (message ?? "Unknown error")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        _ = stderr.write(
            Data("error[\(code.category)]: \(safe)\n".utf8)
        )
    }

    private func exitCode(for error: Error) -> GraphCLIExitCode {
        guard let error = error as? GraphInspectionError else {
            return .persistenceFailure
        }
        switch error {
        case .runNotFound, .checkpointNotFound:
            return .notFound
        case .incompatibleSchema:
            return .incompatibleSchema
        case .invalidBoundary, .corruptHistory:
            return .corruptHistory
        case .persistence:
            return .persistenceFailure
        case .evidenceUnavailable:
            return .evidenceUnavailable
        }
    }

    private func recordTelemetry(
        command: String,
        output: GraphCLIOutputMode,
        outcome: GraphCLICommandOutcome,
        started: UInt64
    ) {
        let ended = clock.nowNanoseconds()
        let duration = ended >= started ? ended - started : 0
        telemetry.record(
            GraphCLITelemetryRecord(
                command: command,
                outputMode: output,
                durationMilliseconds: duration / 1_000_000,
                exitCategory: outcome.exitCode.category,
                resultCount: outcome.resultCount,
                eventCount: outcome.eventCount,
                replayBoundary: outcome.replayBoundary,
                snapshotDisposition: outcome.snapshotDisposition,
                reconciliationOutcome:
                    outcome.reconciliationOutcome,
                terminalGraphDetected:
                    context?.terminalGraph.detected ?? false,
                pipedOutput: !isOutputTTY
            )
        )
    }

    private func encodeString<Value: Encodable>(
        _ value: Value
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(
            decoding: try encoder.encode(value),
            as: UTF8.self
        )
    }
}

private struct GraphCLICommandOutcome: Sendable {
    let exitCode: GraphCLIExitCode
    let resultCount: Int
    let eventCount: Int
    let replayBoundary: UInt64?
    let snapshotDisposition: GraphSnapshotDisposition?
    let reconciliationOutcome: String?

    init(
        exitCode: GraphCLIExitCode,
        resultCount: Int = 0,
        eventCount: Int = 0,
        replayBoundary: UInt64? = nil,
        snapshotDisposition: GraphSnapshotDisposition? = nil,
        reconciliationOutcome: String? = nil
    ) {
        self.exitCode = exitCode
        self.resultCount = resultCount
        self.eventCount = eventCount
        self.replayBoundary = replayBoundary
        self.snapshotDisposition = snapshotDisposition
        self.reconciliationOutcome = reconciliationOutcome
    }
}

private func graphCLIISO8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

public struct GraphExportEntity:
    Equatable,
    Codable,
    Sendable
{
    public let kind: String
    public let id: String
    public let state: String?
    public let role: String?
}
