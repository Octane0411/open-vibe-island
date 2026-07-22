import CryptoKit
import Darwin
import Foundation

public struct GraphProcessBirthIdentity: Equatable, Codable, Sendable {
    public let seconds: Int64
    public let microseconds: Int32

    public init(seconds: Int64, microseconds: Int32) {
        self.seconds = seconds
        self.microseconds = microseconds
    }

    public var token: String { "\(seconds):\(microseconds)" }
}

public struct GraphDurableProcessIdentity: Equatable, Codable, Sendable {
    public let process: ProcessIdentity
    public let birthIdentity: GraphProcessBirthIdentity?
    public let executablePath: String
    public let executableIdentity: String
    public let invocationDigest: String
    public let workspaceIdentity: String
    public let runID: String
    public let nodeID: String
    public let attemptID: String
    public let attemptOrdinal: Int
    public let claimID: String
    public var leaseGeneration: UInt64
    public let executorID: String
    public let executorInstanceID: String
    public let processGroupID: Int32?
    public let launchRecordID: String

    public init(
        process: ProcessIdentity,
        birthIdentity: GraphProcessBirthIdentity?,
        executablePath: String,
        executableIdentity: String,
        invocationDigest: String,
        workspaceIdentity: String,
        runID: String,
        nodeID: String,
        attemptID: String,
        attemptOrdinal: Int,
        claimID: String,
        leaseGeneration: UInt64,
        executorID: String,
        executorInstanceID: String,
        processGroupID: Int32?,
        launchRecordID: String
    ) {
        self.process = process
        self.birthIdentity = birthIdentity
        self.executablePath = executablePath
        self.executableIdentity = executableIdentity
        self.invocationDigest = invocationDigest
        self.workspaceIdentity = workspaceIdentity
        self.runID = runID
        self.nodeID = nodeID
        self.attemptID = attemptID
        self.attemptOrdinal = attemptOrdinal
        self.claimID = claimID
        self.leaseGeneration = leaseGeneration
        self.executorID = executorID
        self.executorInstanceID = executorInstanceID
        self.processGroupID = processGroupID
        self.launchRecordID = launchRecordID
    }
}

public enum GraphLocalProcessLifecycle: String, Codable, Sendable {
    case prepared
    case running
    case exited
    case cleaned
}

public struct GraphLocalProcessExitRecord: Equatable, Codable, Sendable {
    public let terminationStatus: Int32
    public let terminationReason: String
    public let observedAt: Date

    public init(
        terminationStatus: Int32,
        terminationReason: String,
        observedAt: Date
    ) {
        self.terminationStatus = terminationStatus
        self.terminationReason = terminationReason
        self.observedAt = observedAt
    }
}

public struct GraphLocalProcessLaunchRecord: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public var lifecycle: GraphLocalProcessLifecycle
    public var identity: GraphDurableProcessIdentity
    public let preparedAt: Date
    public var acceptedAt: Date?
    public var exit: GraphLocalProcessExitRecord?
    public var cancellationRequestedAt: Date?
    public var cancellationEscalatedAt: Date?
    public var cleanedAt: Date?
    public let stdoutLogPath: String
    public let stderrLogPath: String
    public let logIndexPath: String
    public let redactionLabels: [String]

    public init(
        schemaVersion: Int = 1,
        id: String,
        lifecycle: GraphLocalProcessLifecycle,
        identity: GraphDurableProcessIdentity,
        preparedAt: Date,
        acceptedAt: Date? = nil,
        exit: GraphLocalProcessExitRecord? = nil,
        cancellationRequestedAt: Date? = nil,
        cancellationEscalatedAt: Date? = nil,
        cleanedAt: Date? = nil,
        stdoutLogPath: String,
        stderrLogPath: String,
        logIndexPath: String,
        redactionLabels: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.lifecycle = lifecycle
        self.identity = identity
        self.preparedAt = preparedAt
        self.acceptedAt = acceptedAt
        self.exit = exit
        self.cancellationRequestedAt = cancellationRequestedAt
        self.cancellationEscalatedAt = cancellationEscalatedAt
        self.cleanedAt = cleanedAt
        self.stdoutLogPath = stdoutLogPath
        self.stderrLogPath = stderrLogPath
        self.logIndexPath = logIndexPath
        self.redactionLabels = redactionLabels.sorted()
    }
}

public enum GraphProcessRecoveryClassification:
    String,
    Codable,
    Sendable
{
    case matchingRunning = "matching_running"
    case matchingExited = "matching_exited"
    case identityMismatch = "identity_mismatch"
    case unavailableToInspect = "unavailable_to_inspect"
    case orphaned
    case indeterminate
}

public protocol GraphProcessInspecting: Sendable {
    func classify(
        _ identity: GraphDurableProcessIdentity
    ) -> GraphProcessRecoveryClassification
}

public struct DarwinGraphProcessInspector: GraphProcessInspecting, Sendable {
    public init() {}

    public func classify(
        _ identity: GraphDurableProcessIdentity
    ) -> GraphProcessRecoveryClassification {
        guard let pid = identity.process.processID, pid > 0 else {
            return .orphaned
        }
        errno = 0
        guard kill(pid, 0) == 0 else {
            if errno == ESRCH { return .matchingExited }
            if errno == EPERM { return .unavailableToInspect }
            return .indeterminate
        }
        guard let actual = Self.snapshot(pid: pid) else {
            return .unavailableToInspect
        }
        guard let expectedBirth = identity.birthIdentity else {
            return .indeterminate
        }
        guard actual.birthIdentity == expectedBirth,
              URL(fileURLWithPath: actual.executablePath).standardizedFileURL.path
                == URL(fileURLWithPath: identity.executablePath)
                    .standardizedFileURL.path else {
            return .identityMismatch
        }
        return .matchingRunning
    }

    public static func snapshot(
        pid: Int32
    ) -> (birthIdentity: GraphProcessBirthIdentity, executablePath: String)? {
        var info = proc_bsdinfo()
        let bytes = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard bytes == MemoryLayout<proc_bsdinfo>.size else { return nil }
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = proc_pidpath(
            pid,
            &pathBuffer,
            UInt32(pathBuffer.count)
        )
        guard pathLength > 0 else { return nil }
        return (
            GraphProcessBirthIdentity(
                seconds: Int64(info.pbi_start_tvsec),
                microseconds: Int32(info.pbi_start_tvusec)
            ),
            String(
                decoding: pathBuffer.prefix { $0 != 0 }.map(UInt8.init),
                as: UTF8.self
            )
        )
    }
}

public actor GraphLocalProcessLaunchStore {
    public let rootURL: URL

    public init(rootURL: URL) throws {
        self.rootURL = rootURL.standardizedFileURL
        try FileManager.default.createDirectory(
            at: self.rootURL,
            withIntermediateDirectories: true
        )
    }

    public static func defaultRootURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("local-process-runtime", isDirectory: true)
    }

    public func record(id: String) throws -> GraphLocalProcessLaunchRecord? {
        let url = recordURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try JSONDecoder.graphProcess.decode(
            GraphLocalProcessLaunchRecord.self,
            from: Data(contentsOf: url)
        )
    }

    public func save(_ record: GraphLocalProcessLaunchRecord) throws {
        let data = try JSONEncoder.graphProcess.encode(record)
        let url = recordURL(id: record.id)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    public func records() throws -> [GraphLocalProcessLaunchRecord] {
        let directory = rootURL
            .appendingPathComponent("launch-records", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
            .map {
                try JSONDecoder.graphProcess.decode(
                    GraphLocalProcessLaunchRecord.self,
                    from: Data(contentsOf: $0)
                )
            }
            .sorted {
                if $0.preparedAt != $1.preparedAt {
                    return $0.preparedAt < $1.preparedAt
                }
                return $0.id < $1.id
            }
    }

    public func update(
        id: String,
        _ transform: (inout GraphLocalProcessLaunchRecord) throws -> Void
    ) throws -> GraphLocalProcessLaunchRecord {
        guard var record = try record(id: id) else {
            throw GraphLocalProcessRuntimeError.launchRecordMissing(id)
        }
        try transform(&record)
        try save(record)
        return record
    }

    public func logDirectory(id: String) throws -> URL {
        let url = rootURL
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent(Self.safeName(id), isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func recordURL(id: String) -> URL {
        rootURL
            .appendingPathComponent("launch-records", isDirectory: true)
            .appendingPathComponent(Self.safeName(id))
            .appendingPathExtension("json")
    }

    private static func safeName(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum GraphProcessLogChannel: String, Codable, CaseIterable, Sendable {
    case stdout
    case stderr
}

public struct GraphProcessLogEntry: Equatable, Codable, Sendable, Identifiable {
    public var id: UInt64 { sequence }
    public let sequence: UInt64
    public let channel: GraphProcessLogChannel
    public let data: Data
    public let byteOffset: UInt64
    public let droppedByteCount: Int
    public let redacted: Bool

    public init(
        sequence: UInt64,
        channel: GraphProcessLogChannel,
        data: Data,
        byteOffset: UInt64,
        droppedByteCount: Int = 0,
        redacted: Bool = false
    ) {
        self.sequence = sequence
        self.channel = channel
        self.data = data
        self.byteOffset = byteOffset
        self.droppedByteCount = droppedByteCount
        self.redacted = redacted
    }

    public var text: String { String(decoding: data, as: UTF8.self) }
    public var usedUTF8Fallback: Bool { String(data: data, encoding: .utf8) == nil }
    public var isTruncated: Bool { droppedByteCount > 0 }
}

public struct GraphProcessLogPage: Equatable, Sendable {
    public let entries: [GraphProcessLogEntry]
    public let nextSequence: UInt64
    public let truncatedChannels: [GraphProcessLogChannel]
    public let redactionLabels: [String]
}

public final class GraphProcessLogStore: @unchecked Sendable {
    private struct State {
        var nextSequence: UInt64 = 1
        var bytesByChannel: [GraphProcessLogChannel: Int] = [:]
        var truncatedChannels: Set<GraphProcessLogChannel> = []
    }

    private let lock = NSCondition()
    private var states: [String: State] = [:]

    public init() {}

    public func append(
        launchID: String,
        channel: GraphProcessLogChannel,
        data: Data,
        indexURL: URL,
        streamURL: URL,
        maximumBytes: Int,
        redactionValues: [String]
    ) throws {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var state = try states[launchID] ?? loadState(indexURL: indexURL)
        guard !state.truncatedChannels.contains(channel) else { return }
        let current = state.bytesByChannel[channel, default: 0]
        let remaining = max(0, maximumBytes - current)
        let accepted = data.prefix(remaining)
        let dropped = data.count - accepted.count
        var payload = Data(accepted)
        var redacted = false
        if !redactionValues.isEmpty,
           var text = String(data: payload, encoding: .utf8) {
            for value in redactionValues where text.contains(value) {
                text = text.replacingOccurrences(of: value, with: "[REDACTED]")
                redacted = true
            }
            payload = Data(text.utf8)
        }
        let entry = GraphProcessLogEntry(
            sequence: state.nextSequence,
            channel: channel,
            data: payload,
            byteOffset: UInt64(current),
            droppedByteCount: dropped,
            redacted: redacted
        )
        try Self.appendLine(entry, to: indexURL)
        try Self.appendBytes(payload, to: streamURL)
        state.nextSequence += 1
        state.bytesByChannel[channel] = current + accepted.count
        if dropped > 0 { state.truncatedChannels.insert(channel) }
        states[launchID] = state
        lock.broadcast()
    }

    public func read(
        indexURL: URL,
        channel: GraphProcessLogChannel? = nil,
        afterSequence: UInt64 = 0,
        limit: Int = 500,
        redactionLabels: [String] = []
    ) throws -> GraphProcessLogPage {
        lock.lock()
        defer { lock.unlock() }
        let entries = try Self.readEntries(indexURL: indexURL)
        let matching = entries.filter {
            $0.sequence > afterSequence
                && (channel == nil || $0.channel == channel)
        }
        let page = Array(matching.prefix(max(1, min(limit, 5_000))))
        return GraphProcessLogPage(
            entries: page,
            nextSequence: page.last?.sequence ?? afterSequence,
            truncatedChannels: GraphProcessLogChannel.allCases.filter {
                candidate in entries.contains {
                    $0.channel == candidate && $0.isTruncated
                }
            },
            redactionLabels: redactionLabels.sorted()
        )
    }

    public func waitForText(
        indexURL: URL,
        containing text: String,
        timeout: TimeInterval
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let deadline = Date().addingTimeInterval(max(0.1, timeout))
        while true {
            if let entries = try? Self.readEntries(indexURL: indexURL),
               entries.contains(where: { $0.text.contains(text) }) {
                return true
            }
            guard lock.wait(until: deadline) else { return false }
        }
    }

    private func loadState(indexURL: URL) throws -> State {
        let entries = try Self.readEntries(indexURL: indexURL)
        var state = State()
        state.nextSequence = (entries.last?.sequence ?? 0) + 1
        for entry in entries {
            state.bytesByChannel[entry.channel] = max(
                state.bytesByChannel[entry.channel, default: 0],
                Int(entry.byteOffset) + entry.data.count
            )
            if entry.isTruncated {
                state.truncatedChannels.insert(entry.channel)
            }
        }
        return state
    }

    private static func readEntries(indexURL: URL) throws
        -> [GraphProcessLogEntry]
    {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return []
        }
        return try Data(contentsOf: indexURL)
            .split(separator: UInt8(ascii: "\n"))
            .map { try JSONDecoder.graphProcess.decode(
                GraphProcessLogEntry.self,
                from: Data($0)
            ) }
            .sorted { $0.sequence < $1.sequence }
    }

    private static func appendLine<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = try JSONEncoder.graphProcess.encode(value)
        data.append(UInt8(ascii: "\n"))
        try appendBytes(data, to: url)
    }

    private static func appendBytes(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

public enum GraphLocalProcessRuntimeError: Error, Equatable, Sendable {
    case launchRecordMissing(String)
    case launchRecordConflict(String)
    case staleLeaseGeneration(expectedAtLeast: UInt64, actual: UInt64)
    case identityMismatch(String)
    case artifactMissing(String)
    case artifactTooLarge(String, Int)
}

extension GraphLocalProcessRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .launchRecordMissing(id):
            "Local process launch record is missing: \(id)."
        case let .launchRecordConflict(id):
            "Local process launch record conflicts with the command: \(id)."
        case let .staleLeaseGeneration(expected, actual):
            "Stale lease generation \(actual); expected at least \(expected)."
        case let .identityMismatch(id):
            "Local process identity no longer matches launch record \(id)."
        case let .artifactMissing(path):
            "Declared artifact is missing: \(path)."
        case let .artifactTooLarge(path, limit):
            "Declared artifact \(path) exceeds \(limit) bytes."
        }
    }
}

extension JSONEncoder {
    fileprivate static var graphProcess: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var graphProcess: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
