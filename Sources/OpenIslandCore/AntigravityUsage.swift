import Foundation

/// Quota snapshot for the Antigravity CLI, polled from the language server
/// embedded in a running `agy` instance via its `GetUserStatus` RPC.
public struct AntigravityQuotaSnapshot: Equatable, Codable, Sendable {
    public var planName: String?
    public var monthlyPromptCredits: Int
    public var availablePromptCredits: Int
    public var monthlyFlowCredits: Int
    public var availableFlowCredits: Int
    public var fetchedAt: Date?

    public init(
        planName: String?,
        monthlyPromptCredits: Int,
        availablePromptCredits: Int,
        monthlyFlowCredits: Int,
        availableFlowCredits: Int,
        fetchedAt: Date? = nil
    ) {
        self.planName = planName
        self.monthlyPromptCredits = monthlyPromptCredits
        self.availablePromptCredits = availablePromptCredits
        self.monthlyFlowCredits = monthlyFlowCredits
        self.availableFlowCredits = availableFlowCredits
        self.fetchedAt = fetchedAt
    }

    public var isEmpty: Bool {
        monthlyPromptCredits <= 0 && monthlyFlowCredits <= 0
    }

    public var promptUsedPercentage: Double {
        Self.usedPercentage(available: availablePromptCredits, monthly: monthlyPromptCredits)
    }

    public var flowUsedPercentage: Double {
        Self.usedPercentage(available: availableFlowCredits, monthly: monthlyFlowCredits)
    }

    private static func usedPercentage(available: Int, monthly: Int) -> Double {
        guard monthly > 0, available >= 0 else {
            return 0
        }
        return min(100, max(0, (Double(monthly - available) / Double(monthly)) * 100))
    }
}

/// A captured language-server address plus the CSRF token needed to talk to
/// it. The pair only lives as long as the `agy` instance that minted it.
public struct AntigravityCredential: Equatable, Sendable {
    public var address: String
    public var token: String
    public var capturedAt: Date?

    public init(address: String, token: String, capturedAt: Date? = nil) {
        self.address = address
        self.token = token
        self.capturedAt = capturedAt
    }
}

/// Reads credentials appended by the shell-level capture hook
/// (`~/.zshenv`) into the agy data home. Lines look like:
///
/// ```
/// localhost:58033 975a0492-a78a-4df8-9fe0-998c7bb7193b 1795577578
/// ```
///
/// The file grows one line per agy tool-command shell, so parsing keeps
/// only the freshest entry per address and tolerates malformed lines.
public enum AntigravityCredentialStore {
    public static let defaultURL = URL(fileURLWithPath: {
        let home = NSHomeDirectory()
        return "\(home)/.gemini/antigravity-cli/open-island-credentials"
    }())

    public static func load(from url: URL = defaultURL) -> [AntigravityCredential] {
        guard let contents = try? String(contentsOfFile: url.path, encoding: .utf8) else {
            return []
        }

        var freshestByAddress: [String: AntigravityCredential] = [:]
        var order: [String] = []

        for line in contents.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else {
                continue
            }

            let address = String(fields[0])
            let token = String(fields[1])
            guard !address.isEmpty, !token.isEmpty else {
                continue
            }

            let capturedAt = fields.count >= 3
                ? Double(fields[2]).map { Date(timeIntervalSince1970: $0) }
                : nil

            if freshestByAddress[address] == nil {
                order.append(address)
            }
            freshestByAddress[address] = AntigravityCredential(
                address: address,
                token: token,
                capturedAt: capturedAt
            )
        }

        return order.compactMap { freshestByAddress[$0] }
    }
}

public enum AntigravityUsageError: Error, Equatable {
    case invalidResponse
}

/// Polls `GetUserStatus` on a live agy language server and decodes the
/// plan-credit payload.
public enum AntigravityUsageLoader {
    private static let servicePath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        return URLSession(configuration: configuration)
    }()

    static func makeRequest(credential: AntigravityCredential) -> URLRequest? {
        guard let url = URL(string: "http://\(credential.address)\(servicePath)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(credential.token, forHTTPHeaderField: "x-antigravity-csrf-token")
        request.httpBody = #"{"metadata":{"ideName":"antigravity","extensionName":"antigravity","locale":"en"}}"#
            .data(using: .utf8)
        return request
    }

    /// Tries the captured credentials newest-first and returns the first
    /// live server's quota. Dead instances (connection refused, rotated
    /// token) are skipped rather than surfaced as errors.
    public static func fetchLatestQuota(
        from credentials: [AntigravityCredential]
    ) async -> AntigravityQuotaSnapshot? {
        for credential in credentials.reversed() {
            if let snapshot = try? await fetchQuota(credential: credential) {
                return snapshot
            }
        }
        return nil
    }

    public static func fetchQuota(
        credential: AntigravityCredential
    ) async throws -> AntigravityQuotaSnapshot {
        guard let request = makeRequest(credential: credential) else {
            throw AntigravityUsageError.invalidResponse
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw AntigravityUsageError.invalidResponse
        }

        return try parseQuota(from: data)
    }

    static func parseQuota(from data: Data) throws -> AntigravityQuotaSnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any],
              let userStatus = payload["userStatus"] as? [String: Any],
              let planStatus = userStatus["planStatus"] as? [String: Any] else {
            throw AntigravityUsageError.invalidResponse
        }

        let planInfo = planStatus["planInfo"] as? [String: Any]

        return AntigravityQuotaSnapshot(
            planName: planInfo?["planName"] as? String,
            monthlyPromptCredits: intValue(planInfo?["monthlyPromptCredits"]) ?? 0,
            availablePromptCredits: intValue(planStatus["availablePromptCredits"]) ?? 0,
            monthlyFlowCredits: intValue(planInfo?["monthlyFlowCredits"]) ?? 0,
            availableFlowCredits: intValue(planStatus["availableFlowCredits"]) ?? 0,
            fetchedAt: Date()
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }
}
