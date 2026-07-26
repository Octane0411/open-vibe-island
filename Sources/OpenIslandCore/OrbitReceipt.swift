import Foundation

/// An immutable local record of a bounded action routed through an originating adapter.
/// Receipts intentionally contain metadata, not raw commands, prompts, paths, or secrets.
public struct OrbitReceipt: Codable, Equatable, Identifiable, Sendable {
    public enum Action: String, Codable, Sendable {
        case permissionDenied
        case permissionAllowedOnce
        case permissionAllowedWithUpdates
        case questionAnswered
    }

    public enum Status: String, Codable, Sendable {
        case queued
        case sent
        case failed
    }

    public let id: UUID
    public let createdAt: Date
    public let sessionID: String
    public let requestID: UUID?
    public let adapter: String
    public let action: Action
    public let scope: String
    public let status: Status
    public let summary: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sessionID: String,
        requestID: UUID? = nil,
        adapter: String,
        action: Action,
        scope: String,
        status: Status,
        summary: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sessionID = sessionID
        self.requestID = requestID
        self.adapter = adapter
        self.action = action
        self.scope = scope
        self.status = status
        self.summary = summary
    }

    public func with(status: Status) -> OrbitReceipt {
        OrbitReceipt(
            id: id,
            createdAt: createdAt,
            sessionID: sessionID,
            requestID: requestID,
            adapter: adapter,
            action: action,
            scope: scope,
            status: status,
            summary: summary
        )
    }
}

/// A bounded append-only receipt log for one Orbit process.
public struct OrbitReceiptLedger: Codable, Equatable, Sendable {
    public private(set) var entries: [OrbitReceipt]
    public let maxEntries: Int

    public init(maxEntries: Int = 512) {
        self.entries = []
        self.maxEntries = max(1, maxEntries)
    }

    public mutating func append(_ receipt: OrbitReceipt) {
        entries.append(receipt)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func entry(id: UUID) -> OrbitReceipt? {
        entries.first { $0.id == id }
    }
}
