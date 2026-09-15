import Foundation
import OSLog

public struct GraphCLITelemetryRecord:
    Equatable,
    Codable,
    Sendable
{
    public let schemaVersion: Int
    public let command: String
    public let outputMode: GraphCLIOutputMode
    public let durationMilliseconds: UInt64
    public let exitCategory: String
    public let resultCount: Int
    public let eventCount: Int
    public let replayBoundary: UInt64?
    public let snapshotDisposition: GraphSnapshotDisposition?
    public let reconciliationOutcome: String?
    public let terminalGraphDetected: Bool
    public let pipedOutput: Bool

    public init(
        schemaVersion: Int = 1,
        command: String,
        outputMode: GraphCLIOutputMode,
        durationMilliseconds: UInt64,
        exitCategory: String,
        resultCount: Int,
        eventCount: Int,
        replayBoundary: UInt64?,
        snapshotDisposition: GraphSnapshotDisposition?,
        reconciliationOutcome: String?,
        terminalGraphDetected: Bool,
        pipedOutput: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.outputMode = outputMode
        self.durationMilliseconds = durationMilliseconds
        self.exitCategory = exitCategory
        self.resultCount = resultCount
        self.eventCount = eventCount
        self.replayBoundary = replayBoundary
        self.snapshotDisposition = snapshotDisposition
        self.reconciliationOutcome = reconciliationOutcome
        self.terminalGraphDetected = terminalGraphDetected
        self.pipedOutput = pipedOutput
    }
}

public protocol GraphCLITelemetrySink: Sendable {
    func record(_ record: GraphCLITelemetryRecord)
}

public struct NoopGraphCLITelemetrySink:
    GraphCLITelemetrySink,
    Sendable
{
    public init() {}

    public func record(_ record: GraphCLITelemetryRecord) {}
}

public struct OSLogGraphCLITelemetrySink:
    GraphCLITelemetrySink,
    Sendable
{
    private let logger = Logger(
        subsystem: "app.openisland",
        category: "GraphCLI"
    )

    public init() {}

    public func record(_ record: GraphCLITelemetryRecord) {
        logger.info(
            "command=\(record.command, privacy: .public) output=\(record.outputMode.rawValue, privacy: .public) duration_ms=\(record.durationMilliseconds) exit=\(record.exitCategory, privacy: .public) results=\(record.resultCount) events=\(record.eventCount) tg=\(record.terminalGraphDetected) piped=\(record.pipedOutput)"
        )
    }
}

public protocol GraphCLIMonotonicClock: Sendable {
    func nowNanoseconds() -> UInt64
}

public struct SystemGraphCLIMonotonicClock:
    GraphCLIMonotonicClock,
    Sendable
{
    public init() {}

    public func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
