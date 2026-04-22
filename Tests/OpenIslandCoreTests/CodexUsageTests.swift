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
                                "input_tokens": 999_000,
                                "cached_input_tokens": 900_000,
                                "output_tokens": 999,
                                "reasoning_output_tokens": 111,
                                "total_tokens": 999_999,
                            ],
                            "last_token_usage": [
                                "input_tokens": 5_000,
                                "cached_input_tokens": 4_000,
                                "output_tokens": 80,
                                "reasoning_output_tokens": 20,
                                "total_tokens": 5_100,
                            ],
                            "model_context_window": 128_000,
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
                                "input_tokens": 1_234_000,
                                "cached_input_tokens": 1_100_000,
                                "output_tokens": 567,
                                "reasoning_output_tokens": 111,
                                "total_tokens": 1_234_567,
                            ],
                            "last_token_usage": [
                                "input_tokens": 8_000,
                                "cached_input_tokens": 7_000,
                                "output_tokens": 120,
                                "reasoning_output_tokens": 30,
                                "total_tokens": 8_150,
                            ],
                            "model_context_window": 258_400,
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
        #expect(snapshot?.totalTokenUsage?.totalTokens == 1_234_567)
        #expect(snapshot?.totalTokenUsage?.inputTokens == 1_234_000)
        #expect(snapshot?.lastTokenUsage?.totalTokens == 8_150)
        #expect(snapshot?.modelContextWindow == 258_400)
        #expect(snapshot?.recentTotalTokenRate?.deltaTokens == 234_568)
        #expect(snapshot?.recentTotalTokenRate?.sampleInterval == 60)
        #expect(abs((snapshot?.recentTotalTokenRate?.tokensPerSecond ?? 0) - 3_909.466_666_666_667) < 0.001)
        #expect(snapshot?.capturedAt == isoDate("2026-04-03T01:50:35.000Z"))
    }

    @Test
    func codexUsageLoaderParsesInfoOnlySnapshotsWithoutRateLimitWindows() throws {
        let rootURL = temporaryRootURL(named: "codex-usage-info-only")
        let rolloutURL = rootURL
            .appendingPathComponent("2026/04/22", isDirectory: true)
            .appendingPathComponent("rollout-info-only.jsonl")

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        try writeRollout(
            [
                rolloutLine(
                    timestamp: "2026-04-22T03:18:20.834Z",
                    type: "event_msg",
                    payload: [
                        "type": "token_count",
                        "info": [
                            "total_token_usage": [
                                "input_tokens": 44_012_009,
                                "cached_input_tokens": 42_987_904,
                                "output_tokens": 113_981,
                                "reasoning_output_tokens": 40_485,
                                "total_tokens": 44_125_990,
                            ],
                            "last_token_usage": [
                                "input_tokens": 208_958,
                                "cached_input_tokens": 208_768,
                                "output_tokens": 37,
                                "reasoning_output_tokens": 0,
                                "total_tokens": 208_995,
                            ],
                            "model_context_window": 258_400,
                        ],
                        "rate_limits": [
                            "limit_id": "codex",
                            "primary": NSNull(),
                            "secondary": NSNull(),
                        ],
                    ]
                ),
            ],
            to: rolloutURL
        )

        let snapshot = try CodexUsageLoader.load(fromRootURL: rootURL)

        #expect(resolvedPath(snapshot?.sourceFilePath) == rolloutURL.resolvingSymlinksInPath().path)
        #expect(snapshot?.windows.isEmpty == true)
        #expect(snapshot?.isEmpty == false)
        #expect(snapshot?.limitID == "codex")
        #expect(snapshot?.totalTokenUsage?.totalTokens == 44_125_990)
        #expect(snapshot?.lastTokenUsage?.totalTokens == 208_995)
        #expect(snapshot?.modelContextWindow == 258_400)
        #expect(snapshot?.recentTotalTokenRate == nil)
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
