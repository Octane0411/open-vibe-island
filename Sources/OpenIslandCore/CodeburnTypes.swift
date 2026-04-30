import Foundation

public struct CodeburnSnapshot: Equatable, Sendable {
    public var todayCost: Double
    public var currency: String
    public var observedAt: Date

    public init(todayCost: Double, currency: String, observedAt: Date) {
        self.todayCost = todayCost
        self.currency = currency
        self.observedAt = observedAt
    }

    public enum ParseError: Error { case missingField(String) }

    public static func parse(statusJSON: Data, now: Date = Date()) throws -> CodeburnSnapshot {
        let object = try JSONSerialization.jsonObject(with: statusJSON)
        guard let root = object as? [String: Any],
              let today = root["today"] as? [String: Any] else {
            throw ParseError.missingField("today")
        }
        guard let cost = (today["cost"] as? NSNumber)?.doubleValue else {
            throw ParseError.missingField("today.cost")
        }
        let currency = (today["currency"] as? String) ?? "USD"
        return CodeburnSnapshot(todayCost: cost, currency: currency, observedAt: now)
    }
}

public enum CodeburnState: Equatable, Sendable {
    case notProbed
    case notInstalled
    case unavailable(reason: String)
    case ok(CodeburnSnapshot)
}

public protocol CodeburnRunner: Sendable {
    /// Probe whether codeburn is on PATH. Returns version string, or nil.
    func probeVersion() async -> String?
    /// Run `codeburn status --format json`. Returns raw stdout bytes.
    func runStatus(timeout: TimeInterval) async throws -> Data
}

public extension CodeburnState {
    var isOk: Bool {
        if case .ok = self { return true }
        return false
    }
}
