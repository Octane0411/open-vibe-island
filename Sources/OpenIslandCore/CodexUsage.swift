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

    public var isAllZeroPlaceholder: Bool {
        CodexUsageLoader.isAllZeroPlaceholder(
            windows,
            planType: planType,
            limitID: limitID
        )
    }
}

public enum CodexUsageLoader {
    public static let defaultRootURL = CodexRolloutDiscovery.defaultRootURL
    public static let defaultCacheURL: URL = {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return applicationSupportURL
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("codex-usage-cache.json")
    }()
    private static let tailReadLimit = 2 * 1024 * 1024

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

        return sortedCandidates
            .compactMap { candidate in
                loadLatestSnapshot(
                    from: candidate.fileURL,
                    modifiedAt: candidate.modifiedAt
                )
            }
            .max { lhs, rhs in
                let lhsDate = lhs.capturedAt ?? .distantPast
                let rhsDate = rhs.capturedAt ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.sourceFilePath.localizedStandardCompare(rhs.sourceFilePath) == .orderedAscending
                }
                return lhsDate < rhsDate
            }
    }

    public static func loadCached(
        from cacheURL: URL = defaultCacheURL
    ) throws -> CodexUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: cacheURL)
        let snapshot = try JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
        return snapshot.isAllZeroPlaceholder ? nil : snapshot
    }

    public static func saveCached(
        _ snapshot: CodexUsageSnapshot,
        to cacheURL: URL = defaultCacheURL
    ) throws {
        guard !snapshot.isAllZeroPlaceholder else {
            return
        }

        let directoryURL = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: cacheURL, options: .atomic)
    }

    private static func loadLatestSnapshot(from fileURL: URL, modifiedAt: Date) -> CodexUsageSnapshot? {
        if let snapshot = loadLatestSnapshotFromTail(from: fileURL, modifiedAt: modifiedAt) {
            return snapshot
        }

        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        return latestSnapshot(from: contents, fileURL: fileURL, modifiedAt: modifiedAt)
    }

    private static func loadLatestSnapshotFromTail(from fileURL: URL, modifiedAt: Date) -> CodexUsageSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(tailReadLimit) ? size - UInt64(tailReadLimit) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        var contents = String(decoding: data, as: UTF8.self)
        if offset > 0, let firstNewline = contents.firstIndex(of: "\n") {
            contents = String(contents[contents.index(after: firstNewline)...])
        }

        return latestSnapshot(from: contents, fileURL: fileURL, modifiedAt: modifiedAt)
    }

    private static func latestSnapshot(from contents: String, fileURL: URL, modifiedAt: Date) -> CodexUsageSnapshot? {
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
        let planType = string(from: rateLimits["plan_type"])
        let limitID = string(from: rateLimits["limit_id"])
        guard !windows.isEmpty,
              !isAllZeroPlaceholder(windows, planType: planType, limitID: limitID) else {
            return nil
        }

        return CodexUsageSnapshot(
            sourceFilePath: filePath,
            capturedAt: timestamp(from: object["timestamp"]) ?? fallbackTimestamp,
            planType: planType,
            limitID: limitID,
            windows: windows
        )
    }

    public static func isAllZeroPlaceholder(
        _ windows: [CodexUsageWindow],
        planType: String?,
        limitID: String?
    ) -> Bool {
        guard windows.count >= 2 else {
            return false
        }

        let allZero = windows.allSatisfy { window in
            window.usedPercentage == 0
                && window.leftPercentage >= 99.5
        }
        guard allZero else {
            return false
        }

        if windows.allSatisfy({ $0.resetsAt == nil }) {
            return true
        }

        let normalizedPlanType = planType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedLimitID = limitID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedPlanType?.isEmpty ?? true
            || normalizedLimitID.map { $0 != "codex" } ?? true
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

    public static func windowLabel(forMinutes minutes: Int) -> String {
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
