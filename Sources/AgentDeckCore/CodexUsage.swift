import Foundation

public struct CodexUsageWindow: Equatable, Codable, Sendable, Identifiable {
    public var key: String
    public var label: String
    public var usedPercentage: Double
    public var leftPercentage: Double
    public var windowMinutes: Int
    public var resetsAt: Date?

    public init(
        key: String,
        label: String,
        usedPercentage: Double,
        leftPercentage: Double,
        windowMinutes: Int,
        resetsAt: Date?
    ) {
        self.key = key
        self.label = label
        self.usedPercentage = usedPercentage
        self.leftPercentage = leftPercentage
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    public var id: String {
        key
    }

    public var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

public struct CodexUsageSnapshot: Equatable, Codable, Sendable {
    public var sourceFilePath: String
    public var capturedAt: Date?
    public var planType: String?
    public var limitID: String?
    public var windows: [CodexUsageWindow]

    public init(
        sourceFilePath: String,
        capturedAt: Date?,
        planType: String? = nil,
        limitID: String? = nil,
        windows: [CodexUsageWindow]
    ) {
        self.sourceFilePath = sourceFilePath
        self.capturedAt = capturedAt
        self.planType = planType
        self.limitID = limitID
        self.windows = windows
    }

    public var isEmpty: Bool {
        windows.isEmpty
    }
}

public enum CodexUsageLoader {
    public static let defaultRootURL = CodexRolloutDiscovery.defaultRootURL

    private struct Candidate {
        var fileURL: URL
        var modifiedAt: Date
    }

    public static func load(
        fromRootURL rootURL: URL = defaultRootURL,
        fileManager: FileManager = .default
    ) throws -> CodexUsageSnapshot? {
        guard fileManager.fileExists(atPath: rootURL.path),
              let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        var candidates: [Candidate] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl",
                  let resourceValues = try? fileURL.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                  ),
                  resourceValues.isRegularFile == true else {
                continue
            }

            candidates.append(
                Candidate(
                    fileURL: fileURL,
                    modifiedAt: resourceValues.contentModificationDate ?? .distantPast
                )
            )
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.fileURL.path.localizedStandardCompare(rhs.fileURL.path) == .orderedDescending
            }

            return lhs.modifiedAt > rhs.modifiedAt
        }

        for candidate in sortedCandidates {
            if let snapshot = loadLatestSnapshot(
                from: candidate.fileURL,
                modifiedAt: candidate.modifiedAt
            ) {
                return snapshot
            }
        }

        return nil
    }

    private static func loadLatestSnapshot(from fileURL: URL, modifiedAt: Date) -> CodexUsageSnapshot? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        var latestSnapshot: CodexUsageSnapshot?
        contents.enumerateLines { line, _ in
            guard let snapshot = snapshot(
                from: line,
                filePath: fileURL.path,
                fallbackTimestamp: modifiedAt
            ) else {
                return
            }

            latestSnapshot = snapshot
        }

        return latestSnapshot
    }

    private static func snapshot(
        from line: String,
        filePath: String,
        fallbackTimestamp: Date
    ) -> CodexUsageSnapshot? {
        guard let object = jsonObject(for: line),
              object["type"] as? String == "event_msg" else {
            return nil
        }

        let payload = object["payload"] as? [String: Any] ?? [:]
        guard payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any] else {
            return nil
        }

        let windows = ["primary", "secondary"].compactMap { key in
            usageWindow(for: key, in: rateLimits)
        }
        guard !windows.isEmpty else {
            return nil
        }

        return CodexUsageSnapshot(
            sourceFilePath: filePath,
            capturedAt: timestamp(from: object["timestamp"]) ?? fallbackTimestamp,
            planType: string(from: rateLimits["plan_type"]),
            limitID: string(from: rateLimits["limit_id"]),
            windows: windows
        )
    }

    private static func usageWindow(for key: String, in rateLimits: [String: Any]) -> CodexUsageWindow? {
        guard let payload = rateLimits[key] as? [String: Any],
              let usedPercentage = number(from: payload["used_percent"]),
              let windowMinutes = integer(from: payload["window_minutes"]) else {
            return nil
        }

        return CodexUsageWindow(
            key: key,
            label: windowLabel(forMinutes: windowMinutes),
            usedPercentage: usedPercentage,
            leftPercentage: max(0, 100 - usedPercentage),
            windowMinutes: windowMinutes,
            resetsAt: date(from: payload["resets_at"])
        )
    }

    private static func windowLabel(forMinutes minutes: Int) -> String {
        let days = minutes / 1_440
        let remainingMinutesAfterDays = minutes % 1_440
        let hours = remainingMinutesAfterDays / 60
        let remainingMinutes = remainingMinutesAfterDays % 60

        if days > 0, hours == 0, remainingMinutes == 0 {
            return "\(days)d"
        }

        if days > 0, hours > 0 {
            return "\(days)d \(hours)h"
        }

        if hours > 0, remainingMinutes == 0 {
            return "\(hours)h"
        }

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        return "\(minutes)m"
    }

    private static func jsonObject(for line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }

        return dictionary
    }

    private static func timestamp(from value: Any?) -> Date? {
        guard let string = value as? String else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let string as String:
            Double(string)
        default:
            nil
        }
    }

    private static func integer(from value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            number.intValue
        case let string as String:
            Int(string)
        default:
            nil
        }
    }

    private static func date(from value: Any?) -> Date? {
        switch value {
        case let number as NSNumber:
            return Date(timeIntervalSince1970: number.doubleValue)
        case let string as String:
            guard let seconds = Double(string) else {
                return nil
            }

            return Date(timeIntervalSince1970: seconds)
        default:
            return nil
        }
    }

    private static func string(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
