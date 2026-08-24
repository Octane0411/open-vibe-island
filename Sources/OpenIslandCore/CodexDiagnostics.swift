import Foundation

/// Observability for the Codex ingestion layer.
///
/// Two classes of silent failure motivated this type:
///
/// 1. **Format drift.** Codex writes its rollout transcript as an internal
///    append-only log with no compatibility contract. New record types appear
///    across releases and previously used ones disappear. When the decoder
///    drops an unrecognized record into a `default` branch, the drift stays
///    invisible until it resurfaces months later as an unexplained bug.
///
/// 2. **Authority conflicts.** Several sources observe the same session. When a
///    source tries to write a facet it is not authoritative for, the write is
///    rejected by design — but a rejection that happens thousands of times a
///    day is a signal that the authority matrix disagrees with reality.
///
/// Both are recorded here as counters keyed by the Codex version that produced
/// them, so the settings diagnostics pane can surface "we saw N records of a
/// type we do not understand, written by Codex X.Y.Z".
public final class CodexDiagnostics: @unchecked Sendable {
    public struct UnknownRecord: Hashable, Sendable {
        public let recordType: String
        public let cliVersion: String?

        public init(recordType: String, cliVersion: String?) {
            self.recordType = recordType
            self.cliVersion = cliVersion
        }
    }

    public struct RejectedWrite: Hashable, Sendable {
        public let facet: String
        public let attemptedBy: String
        public let heldBy: String?

        public init(facet: String, attemptedBy: String, heldBy: String?) {
            self.facet = facet
            self.attemptedBy = attemptedBy
            self.heldBy = heldBy
        }
    }

    public struct Snapshot: Equatable, Sendable {
        public var unknownRecords: [UnknownRecord: Int]
        public var rejectedWrites: [RejectedWrite: Int]
        public var unknownOriginators: [String: Int]

        public init(
            unknownRecords: [UnknownRecord: Int] = [:],
            rejectedWrites: [RejectedWrite: Int] = [:],
            unknownOriginators: [String: Int] = [:]
        ) {
            self.unknownRecords = unknownRecords
            self.rejectedWrites = rejectedWrites
            self.unknownOriginators = unknownOriginators
        }

        public var isEmpty: Bool {
            unknownRecords.isEmpty && rejectedWrites.isEmpty && unknownOriginators.isEmpty
        }

        /// Human-readable lines for the diagnostics pane, most frequent first.
        public var summaryLines: [String] {
            var lines: [String] = []

            for (key, count) in unknownRecords.sorted(by: { $0.value > $1.value }) {
                let version = key.cliVersion.map { " (codex \($0))" } ?? ""
                lines.append("Unrecognized rollout record “\(key.recordType)”\(version) × \(count)")
            }

            for (key, count) in unknownOriginators.sorted(by: { $0.value > $1.value }) {
                lines.append("Unrecognized Codex originator “\(key)” × \(count)")
            }

            for (key, count) in rejectedWrites.sorted(by: { $0.value > $1.value }) {
                let holder = key.heldBy.map { ", held by \($0)" } ?? ""
                lines.append("Rejected \(key.facet) write from \(key.attemptedBy)\(holder) × \(count)")
            }

            return lines
        }
    }

    private let lock = NSLock()
    private var unknownRecords: [UnknownRecord: Int] = [:]
    private var rejectedWrites: [RejectedWrite: Int] = [:]
    private var unknownOriginators: [String: Int] = [:]

    public init() {}

    public func recordUnknownRecordType(_ type: String, cliVersion: String?) {
        let key = UnknownRecord(recordType: type, cliVersion: cliVersion)
        lock.lock()
        unknownRecords[key, default: 0] += 1
        lock.unlock()
    }

    public func recordRejectedWrite(facet: String, attemptedBy: String, heldBy: String?) {
        let key = RejectedWrite(facet: facet, attemptedBy: attemptedBy, heldBy: heldBy)
        lock.lock()
        rejectedWrites[key, default: 0] += 1
        lock.unlock()
    }

    public func recordUnknownOriginator(_ originator: String) {
        lock.lock()
        unknownOriginators[originator, default: 0] += 1
        lock.unlock()
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            unknownRecords: unknownRecords,
            rejectedWrites: rejectedWrites,
            unknownOriginators: unknownOriginators
        )
    }

    public func reset() {
        lock.lock()
        unknownRecords.removeAll()
        rejectedWrites.removeAll()
        unknownOriginators.removeAll()
        lock.unlock()
    }
}
