import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Data Models

public struct AnthropicOAuthUsageWindow: Equatable, Codable, Sendable {
    public var usedPercentage: Double
    public var resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    public var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

public struct AnthropicOAuthUsageSnapshot: Equatable, Codable, Sendable {
    public var fiveHour: AnthropicOAuthUsageWindow?
    public var sevenDay: AnthropicOAuthUsageWindow?
    public var sevenDayOAuthApps: AnthropicOAuthUsageWindow?
    public var sevenDaySonnet: AnthropicOAuthUsageWindow?
    public var sevenDayOpus: AnthropicOAuthUsageWindow?
    public var monthlyLimit: Int?
    public var remaining: Int?
    public var fetchedAt: Date?

    public init(
        fiveHour: AnthropicOAuthUsageWindow? = nil,
        sevenDay: AnthropicOAuthUsageWindow? = nil,
        sevenDayOAuthApps: AnthropicOAuthUsageWindow? = nil,
        sevenDaySonnet: AnthropicOAuthUsageWindow? = nil,
        sevenDayOpus: AnthropicOAuthUsageWindow? = nil,
        monthlyLimit: Int? = nil,
        remaining: Int? = nil,
        fetchedAt: Date? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOAuthApps = sevenDayOAuthApps
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOpus = sevenDayOpus
        self.monthlyLimit = monthlyLimit
        self.remaining = remaining
        self.fetchedAt = fetchedAt
    }

    public var isEmpty: Bool {
        fiveHour == nil && sevenDay == nil && monthlyLimit == nil && remaining == nil
    }
}

// MARK: - API Client

public enum AnthropicOAuthUsageError: Error, Sendable {
    case noTokenAvailable
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case httpError(statusCode: Int, message: String)
}

public actor AnthropicOAuthUsageClient {
    private let session: URLSession
    private let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchUsage(token: String) async throws -> AnthropicOAuthUsageSnapshot {
        var request = URLRequest(url: apiURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AnthropicOAuthUsageError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicOAuthUsageError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnthropicOAuthUsageError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        let snapshot = try parseResponse(data: data)
        return snapshot
    }

    private func parseResponse(data: Data) throws -> AnthropicOAuthUsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }

        do {
            return try decoder.decode(AnthropicOAuthUsageSnapshot.self, from: data)
        } catch {
            // Fallback: try parsing as generic JSON to extract known fields
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AnthropicOAuthUsageError.invalidResponse
            }
            return snapshotFromDictionary(json)
        }
    }

    private func snapshotFromDictionary(_ dict: [String: Any]) -> AnthropicOAuthUsageSnapshot {
        AnthropicOAuthUsageSnapshot(
            fiveHour: usageWindow(from: dict["five_hour"]),
            sevenDay: usageWindow(from: dict["seven_day"]),
            sevenDayOAuthApps: usageWindow(from: dict["seven_day_oauth_apps"]),
            sevenDaySonnet: usageWindow(from: dict["seven_day_sonnet"]),
            sevenDayOpus: usageWindow(from: dict["seven_day_opus"]),
            monthlyLimit: dict["monthly_limit"] as? Int,
            remaining: dict["remaining"] as? Int,
            fetchedAt: Date()
        )
    }

    private func usageWindow(from value: Any?) -> AnthropicOAuthUsageWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        let percentage = (dict["used_percentage"] as? Double)
            ?? (dict["usedPercentage"] as? Double)
            ?? (dict["utilization"] as? Double)
        guard let percentage else { return nil }

        let resetsAt: Date?
        if let timestamp = dict["resets_at"] as? Double {
            resetsAt = Date(timeIntervalSince1970: timestamp)
        } else if let timestampString = dict["resets_at"] as? String,
                  let timestamp = Double(timestampString) {
            resetsAt = Date(timeIntervalSince1970: timestamp)
        } else {
            resetsAt = nil
        }

        return AnthropicOAuthUsageWindow(usedPercentage: percentage, resetsAt: resetsAt)
    }
}

// MARK: - Loader

public enum AnthropicOAuthUsageLoader {
    public static let defaultCacheURL = URL(fileURLWithPath: "/tmp/open-island-oauth-usage.json")

    public static func load(token: String? = nil) async throws -> AnthropicOAuthUsageSnapshot? {
        let resolvedToken: String
        if let token {
            resolvedToken = token
        } else {
            resolvedToken = try AnthropicOAuthTokenResolver.resolve()
        }

        let client = AnthropicOAuthUsageClient()
        let snapshot = try await client.fetchUsage(token: resolvedToken)
        return snapshot.isEmpty ? nil : snapshot
    }

    public static func loadWithFallback() async -> AnthropicOAuthUsageSnapshot? {
        do {
            return try await load()
        } catch {
            // Silently fail — hooks fail open
            return nil
        }
    }
}
