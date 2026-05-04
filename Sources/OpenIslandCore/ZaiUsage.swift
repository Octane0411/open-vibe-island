import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ZaiUsageWindow: Equatable, Codable, Sendable, Identifiable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var usedPercentage: Double
    public var resetsAt: Date?

    public var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }

    public init(key: String, label: String, usedPercentage: Double, resetsAt: Date?) {
        self.key = key
        self.label = label
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public struct ZaiUsageSnapshot: Equatable, Codable, Sendable {
    public var capturedAt: Date
    public var windows: [ZaiUsageWindow]

    public var isEmpty: Bool { windows.isEmpty }
}

public enum ZaiUsageLoader {
    private static let defaultQuotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ZaiUsageSnapshot? {
        guard let token = resolveToken(environment: environment), !token.isEmpty else {
            return nil
        }

        let url = resolveQuotaURL(environment: environment)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 15)

        if let responseError {
            throw responseError
        }
        guard let responseData else {
            return nil
        }

        let payload = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        guard let data = payload?["data"] as? [String: Any],
              let limits = data["limits"] as? [[String: Any]] else {
            return nil
        }

        let windows = limits.compactMap(parseWindow)
        guard !windows.isEmpty else { return nil }

        return ZaiUsageSnapshot(capturedAt: .now, windows: windows)
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        if let token = environment["Z_AI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }

        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zai", isDirectory: true)
            .appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let keys = ["apiKey", "api_key", "token", "accessToken"]
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return nil
    }

    private static func resolveQuotaURL(environment: [String: String]) -> URL {
        if let override = environment["Z_AI_QUOTA_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: override), !override.isEmpty {
            return url
        }
        return defaultQuotaURL
    }

    private static func parseWindow(limit: [String: Any]) -> ZaiUsageWindow? {
        guard let type = limit["type"] as? String else { return nil }
        guard type == "TOKENS_LIMIT" || type == "TIME_LIMIT" else { return nil }

        let number = (limit["number"] as? NSNumber)?.intValue ?? 0
        let unit = (limit["unit"] as? NSNumber)?.intValue ?? 0
        let usage = (limit["usage"] as? NSNumber)?.doubleValue
        let currentValue = (limit["currentValue"] as? NSNumber)?.doubleValue
        let remaining = (limit["remaining"] as? NSNumber)?.doubleValue
        let percentage = (limit["percentage"] as? NSNumber)?.doubleValue

        var used: Double?
        if let usage, usage > 0 {
            if let remaining {
                used = ((usage - remaining) / usage) * 100
            } else if let currentValue {
                used = (currentValue / usage) * 100
            }
        }
        if used == nil { used = percentage }
        guard let used else { return nil }

        let resetMS = (limit["nextResetTime"] as? NSNumber)?.doubleValue
        let resetsAt = resetMS.map { Date(timeIntervalSince1970: $0 / 1000) }

        let label = labelFor(type: type, number: number, unit: unit)
        return ZaiUsageWindow(
            key: "\(type)-\(number)-\(unit)",
            label: label,
            usedPercentage: min(100, max(0, used)),
            resetsAt: resetsAt
        )
    }

    private static func labelFor(type: String, number: Int, unit: Int) -> String {
        if type == "TOKENS_LIMIT" {
            if unit == 3, number > 0 { return "\(number)h" }
            if unit == 1, number > 0 { return "\(number)d" }
            if unit == 6, number > 0 { return "\(number)w" }
            if unit == 5, number > 0 { return "\(number)m" }
        }
        if type == "TIME_LIMIT" {
            return "time"
        }
        return "zai"
    }
}
