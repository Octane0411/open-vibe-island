import CryptoKit
import Foundation
import Network
import Security

public enum WatchSecureTransport {
    public static let serviceType = "_openisland2._tcp"

    public static func randomSecret() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// TLS authenticates both peers with an out-of-band, random 256-bit key.
    /// Only the AEAD PSK cipher is offered; there is no plaintext fallback.
    public static func parameters(key: Data) throws -> NWParameters {
        guard key.count == 32 else { throw WatchTransportError.invalidPairingCode }
        let tls = NWProtocolTLS.Options()
        let identity = Data("open-island-watch-v2".utf8)
        sec_protocol_options_add_pre_shared_key(
            tls.securityProtocolOptions,
            key.withUnsafeBytes { DispatchData(bytes: $0) as __DispatchData },
            identity.withUnsafeBytes { DispatchData(bytes: $0) as __DispatchData }
        )
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        // The typed replacement API omits PSK suites; use the platform PSK API.
        sec_protocol_options_add_tls_ciphersuite(
            tls.securityProtocolOptions, TLS_PSK_WITH_AES_128_GCM_SHA256
        )
        sec_protocol_options_set_tls_tickets_enabled(tls.securityProtocolOptions, false)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}

public struct WatchPairingCode: Sendable {
    public let key: Data
    public let secret: String

    public init(key: Data, secret: String) {
        self.key = key
        self.secret = secret
    }

    public init(_ text: String) throws {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3, parts[0] == "OI2",
              let key = Data(base64Encoded: String(parts[1])), key.count == 32,
              let secret = Data(base64Encoded: String(parts[2])), secret.count == 32 else {
            throw WatchTransportError.invalidPairingCode
        }
        self.key = key
        self.secret = secret.base64EncodedString()
    }

    public var text: String { "OI2.\(key.base64EncodedString()).\(secret)" }
}

public enum WatchTransportError: Error, LocalizedError {
    case invalidPairingCode
    case invalidResponse
    case connectionClosed
    case timedOut
    case oversizedMessage

    public var errorDescription: String? {
        switch self {
        case .invalidPairingCode: "Invalid pairing key. Copy a new key from the Mac."
        case .invalidResponse: "Invalid response from the paired Mac."
        case .connectionClosed: "The secure connection closed."
        case .timedOut: "The secure connection timed out."
        case .oversizedMessage: "The message exceeds the size limit."
        }
    }
}
