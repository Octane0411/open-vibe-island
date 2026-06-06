import Foundation
import Testing
@testable import OpenIslandCore

struct CodexUsageTests {
    @Test
    func codexUsageLoaderParsesLastTokenCountRateLimits() throws {
        let rootURL = temporaryRootURL(named: "codex-usage")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-latest.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T01:49:35.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": [
                                "total_tokens": 999_999,
                            ],
                        ],
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 12.0,
                                "window_minutes": 300,
                                "resets_at": 1_775_158_295,
                            ],
                            "secondary": [
                                "used_percent": 24.0,
                                "window_minutes": 10_080,
                                "resets_at": 1_775_635_184,
                            ],
                        ],
                    ]
                ),
                rolloutLine(
                    timestamp: "2026-04-03T01:50:35.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": [
                                "total_tokens": 1_234_567,
                            ],
                        ],
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 13.0,
                                "window_minutes": 300,
                                "resets_at": 1_775_158_295,
                            ],
                            "secondary": [
                                "used_percent": 25.0,
                                "window_minutes": 10_080,
                                "resets_at": 1_775_635_184,
                            ],
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )
        try setModificationDate(
            Date(timeIntervalSince1970: 2_000),
            for: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == rolloutURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.planType == "pro")
        #expect(snapshot?.windows.map(\.label) == ["5h", "7d"])
        #expect(snapshot?.windows.map(\.roundedUsedPercentage) == [13, 25])
        #expect(snapshot?.windows.first?.leftPercentage == 87)
        #expect(snapshot?.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_775_158_295))
        #expect(snapshot?.capturedAt == isoDate("2026-04-03T01:50:35.000Z"))
    }

    @Test
    func codexUsageLoaderFallsBackWhenNewestRolloutHasNoRateLimits() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-fallback")
        let oldRolloutURL = rootURL
            .appendingPathComponent("2026/04/02", isDirectory: true)
            .appendingPathComponent("rollout-has-rate-limits.jsonl")
        let newRolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-no-rate-limits.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-02T17:54:17.621Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 13.0,
                                "window_minutes": 300,
                                "resets_at": 1_775_158_295,
                            ],
                        ],
                    ]
                ),
            ],
            to: oldRolloutURL
        )
        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T03:00:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "user_message",
                        "message": "Start a fresh session.",
                    ]
                ),
            ],
            to: newRolloutURL
        )

        try setModificationDate(Date(timeIntervalSince1970: 1_000), for: oldRolloutURL)
        try setModificationDate(Date(timeIntervalSince1970: 2_000), for: newRolloutURL)

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == oldRolloutURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.windows.map(\.label) == ["5h"])
        #expect(snapshot?.windows.first?.roundedUsedPercentage == 13)
    }

    @Test
    func codexUsageLoaderPrefersNewestTokenCountTimestampOverFileModificationDate() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-event-time")
        let olderSnapshotURL = rootURL
            .appendingPathComponent("2026/04/02", isDirectory: true)
            .appendingPathComponent("rollout-old-token-new-mtime.jsonl")
        let newerSnapshotURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-new-token-old-mtime.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T01:00:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex_bengalfox",
                            "primary": [
                                "used_percent": 0.0,
                                "window_minutes": 300,
                            ],
                        ],
                    ]
                ),
            ],
            to: olderSnapshotURL
        )
        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T02:00:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "primary": [
                                "used_percent": 40.0,
                                "window_minutes": 300,
                            ],
                            "secondary": [
                                "used_percent": 8.0,
                                "window_minutes": 10_080,
                            ],
                        ],
                    ]
                ),
            ],
            to: newerSnapshotURL
        )

        try setModificationDate(Date(timeIntervalSince1970: 3_000), for: olderSnapshotURL)
        try setModificationDate(Date(timeIntervalSince1970: 2_000), for: newerSnapshotURL)

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == newerSnapshotURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.windows.map(\.roundedUsedPercentage) == [40, 8])
    }

    @Test
    func codexUsageLoaderIgnoresAllZeroPlaceholderRateLimits() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-zero-placeholder")
        let realSnapshotURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-real-rate-limits.jsonl")
        let placeholderSnapshotURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-placeholder-rate-limits.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T02:00:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 47.0,
                                "window_minutes": 300,
                            ],
                            "secondary": [
                                "used_percent": 9.0,
                                "window_minutes": 10_080,
                            ],
                        ],
                    ]
                ),
            ],
            to: realSnapshotURL
        )
        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T02:01:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 0.0,
                                "window_minutes": 300,
                            ],
                            "secondary": [
                                "used_percent": 0.0,
                                "window_minutes": 10_080,
                            ],
                        ],
                    ]
                ),
            ],
            to: placeholderSnapshotURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == realSnapshotURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.windows.map(\.roundedUsedPercentage) == [47, 9])
    }

    @Test
    func codexUsageLoaderIgnoresModelSpecificAllZeroPlaceholderWithResets() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-model-zero-placeholder")
        let realSnapshotURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-real-rate-limits.jsonl")
        let placeholderSnapshotURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-placeholder-rate-limits.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T02:00:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex",
                            "plan_type": "pro",
                            "primary": [
                                "used_percent": 47.0,
                                "window_minutes": 300,
                                "resets_at": 1_780_571_047,
                            ],
                            "secondary": [
                                "used_percent": 9.0,
                                "window_minutes": 10_080,
                                "resets_at": 1_781_139_840,
                            ],
                        ],
                    ]
                ),
            ],
            to: realSnapshotURL
        )
        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T02:01:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "limit_id": "codex_bengalfox",
                            "primary": [
                                "used_percent": 0.0,
                                "window_minutes": 300,
                                "resets_at": 1_780_588_623,
                            ],
                            "secondary": [
                                "used_percent": 0.0,
                                "window_minutes": 10_080,
                                "resets_at": 1_781_175_423,
                            ],
                        ],
                    ]
                ),
            ],
            to: placeholderSnapshotURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == realSnapshotURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.windows.map(\.roundedUsedPercentage) == [47, 9])
    }

    @Test
    func codexUsageLoaderIgnoresCachedAllZeroPlaceholder() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-placeholder-cache")
        let cacheURL = rootURL.appendingPathComponent("codex-usage-cache.json")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let snapshot = CodexUsageSnapshot(
            sourceFilePath: "/tmp/rollout-placeholder.jsonl",
            capturedAt: isoDate("2026-04-03T02:00:00.000Z"),
            planType: nil,
            limitID: "codex_bengalfox",
            windows: [
                CodexUsageWindow(
                    key: "primary",
                    label: "5h",
                    usedPercentage: 0,
                    leftPercentage: 100,
                    windowMinutes: 300,
                    resetsAt: isoDate("2026-04-03T07:00:00.000Z")
                ),
                CodexUsageWindow(
                    key: "secondary",
                    label: "7d",
                    usedPercentage: 0,
                    leftPercentage: 100,
                    windowMinutes: 10_080,
                    resetsAt: isoDate("2026-04-10T02:00:00.000Z")
                ),
            ]
        )

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: cacheURL)

        let restored = try CodexUsageLoader.loadCached(from: cacheURL)

        #expect(restored == nil)
    }

    @Test
    func codexUsageLoaderRoundTripsCachedSnapshot() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-cache")
        let cacheURL = rootURL.appendingPathComponent("codex-usage-cache.json")
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let snapshot = CodexUsageSnapshot(
            sourceFilePath: "/tmp/rollout.jsonl",
            capturedAt: isoDate("2026-04-03T02:00:00.000Z"),
            planType: "pro",
            limitID: "codex",
            windows: [
                CodexUsageWindow(
                    key: "primary",
                    label: "5h",
                    usedPercentage: 40,
                    leftPercentage: 60,
                    windowMinutes: 300,
                    resetsAt: nil
                ),
            ]
        )

        try CodexUsageLoader.saveCached(snapshot, to: cacheURL)
        let restored = try CodexUsageLoader.loadCached(from: cacheURL)

        #expect(restored == snapshot)
    }

    @Test
    func codexUsageLoaderFormatsNonStandardWindowLengths() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-labels")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/04/03", isDirectory: true)
            .appendingPathComponent("rollout-custom-window.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-03T05:30:00.000Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "rate_limits": [
                            "primary": [
                                "used_percent": 8.0,
                                "window_minutes": 90,
                                "resets_at": 1_775_200_000,
                            ],
                            "secondary": [
                                "used_percent": 11.0,
                                "window_minutes": 1_500,
                                "resets_at": 1_775_260_000,
                            ],
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(snapshot?.windows.map(\.label) == ["1h 30m", "1d 1h"])
    }
}

private func temporaryRootURL(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("open-island-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func writeRollout(_ lines: [String], to url: URL) throws {
    let directoryURL = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
}

private func setModificationDate(_ date: Date, for url: URL) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

private func isoDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

private func resolvedPath(_ value: String?) -> String? {
    guard let value else {
        return nil
    }

    return URL(fileURLWithPath: value).resolvingSymlinksInPath().path
}

private func rolloutLine(
    timestamp: String,
    type: String,
    payload: [String: Any]
) -> String {
    let object: [String: Any] = [
        "timestamp": timestamp,
        "type": type,
        "payload": payload,
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}
