import Foundation

/// Evidence quality for data read from the local Hermes gateway.
public enum HermesEvidenceTruth: String, Codable, Equatable, Sendable {
    case live
    case stale
    case unavailable
}

/// Metadata-only Hermes session projection. It intentionally excludes prompts,
/// messages, tool arguments, environment variables, and credentials.
public struct HermesGatewaySession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let model: String?
    public let source: String?
    public let status: String?
    public let messageCount: Int?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, model, source, status
        case messageCount = "message_count"
        case updatedAt = "updated_at"
    }
}

public struct HermesGatewaySnapshot: Equatable, Sendable {
    public let gateway: HermesEvidenceTruth
    public let sessions: HermesEvidenceTruth
    public let approvals: HermesEvidenceTruth
    public let completions: HermesEvidenceTruth
    public let sessionItems: [HermesGatewaySession]
    public let detail: String

    public init(
        gateway: HermesEvidenceTruth,
        sessions: HermesEvidenceTruth,
        approvals: HermesEvidenceTruth = .unavailable,
        completions: HermesEvidenceTruth = .unavailable,
        sessionItems: [HermesGatewaySession] = [],
        detail: String
    ) {
        self.gateway = gateway
        self.sessions = sessions
        self.approvals = approvals
        self.completions = completions
        self.sessionItems = sessionItems
        self.detail = detail
    }
}

private struct HermesSessionListEnvelope: Decodable {
    let object: String
    let data: [HermesGatewaySession]
}

/// Read-only adapter for Hermes's documented local gateway surface.
///
/// The bearer token must be injected by the caller at runtime. Orbit never
/// discovers it from Hermes files, persists it, or logs it. Non-loopback base
/// URLs are rejected so a configuration mistake cannot send the token remotely.
public actor HermesGatewayAdapter {
    public static let defaultBaseURL = URL(string: "http://127.0.0.1:8642")!
    public static let supportsApprovalEvents = false
    public static let supportsCompletionEvents = false

    private let baseURL: URL
    private let bearerToken: String?
    private let urlSession: URLSession

    public init(
        baseURL: URL = HermesGatewayAdapter.defaultBaseURL,
        bearerToken: String? = nil,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlSession = urlSession
    }

    public func fetchSnapshot() async -> HermesGatewaySnapshot {
        guard Self.isLoopback(baseURL) else {
            return HermesGatewaySnapshot(
                gateway: .unavailable,
                sessions: .unavailable,
                detail: "Hermes gateway URL must use a loopback host."
            )
        }

        do {
            let healthURL = baseURL.appending(path: "health")
            let (_, healthResponse) = try await urlSession.data(from: healthURL)
            guard let healthHTTP = healthResponse as? HTTPURLResponse,
                  (200..<300).contains(healthHTTP.statusCode) else {
                return HermesGatewaySnapshot(
                    gateway: .unavailable,
                    sessions: .unavailable,
                    detail: "Hermes gateway health check failed."
                )
            }
        } catch {
            return HermesGatewaySnapshot(
                gateway: .unavailable,
                sessions: .unavailable,
                detail: "Hermes gateway is offline."
            )
        }

        guard let bearerToken, !bearerToken.isEmpty else {
            return HermesGatewaySnapshot(
                gateway: .live,
                sessions: .unavailable,
                detail: "Hermes is live; session metadata requires a runtime-injected gateway token."
            )
        }

        do {
            let sessionsURL = baseURL.appending(path: "api/sessions").appending(queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "offset", value: "0"),
            ])
            var request = URLRequest(url: sessionsURL)
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return HermesGatewaySnapshot(
                    gateway: .live,
                    sessions: .unavailable,
                    detail: httpResponse.statusCode == 401
                        ? "Hermes rejected the injected gateway token."
                        : "Hermes session metadata is unavailable."
                )
            }
            let sessions = try Self.decodeSessions(data)
            return HermesGatewaySnapshot(
                gateway: .live,
                sessions: .live,
                sessionItems: sessions,
                detail: "Hermes session metadata is live; approval and completion events are unavailable."
            )
        } catch {
            return HermesGatewaySnapshot(
                gateway: .live,
                sessions: .unavailable,
                detail: "Hermes session metadata could not be decoded."
            )
        }
    }

    static func decodeSessions(_ data: Data) throws -> [HermesGatewaySession] {
        let envelope = try JSONDecoder().decode(HermesSessionListEnvelope.self, from: data)
        guard envelope.object == "list" else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Expected Hermes list envelope")
            )
        }
        return envelope.data
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http" || url.scheme == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
