import Foundation
import OpenIslandTransport

/// Accessed only on the endpoint's serial queue. Reading never opens pairing.
struct WatchPairingState {
    private(set) var transportKey = WatchSecureTransport.randomSecret()
    private var secret: String?
    private var expiresAt = Date.distantPast
    private var attempts = 0
    private(set) var tokens: Set<String> = []

    mutating func begin(now: Date = .now) -> String {
        secret = WatchSecureTransport.randomSecret().base64EncodedString()
        expiresAt = now.addingTimeInterval(120)
        attempts = 0
        return currentCode(now: now)
    }

    func currentCode(now: Date = .now) -> String {
        guard let secret, now < expiresAt, attempts < 5 else { return "" }
        return WatchPairingCode(key: transportKey, secret: secret).text
    }

    mutating func pair(secret candidate: String, now: Date = .now) -> String? {
        guard !currentCode(now: now).isEmpty else { return nil }
        attempts += 1
        guard candidate == secret else { return nil }
        secret = nil
        let token = WatchSecureTransport.randomSecret().base64EncodedString()
        tokens.insert(token)
        return token
    }

    mutating func revoke() {
        self = WatchPairingState()
    }
}
