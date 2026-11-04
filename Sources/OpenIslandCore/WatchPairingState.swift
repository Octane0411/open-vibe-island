import Foundation
import OpenIslandTransport

/// Accessed only on the endpoint's serial queue. Reading never opens pairing.
struct WatchPairingState {
    private(set) var transportKey = WatchSecureTransport.randomSecret()
    private var secret: String?
    private var expiresAt = Date.distantPast
    private var attempts = 0
    private var codeWasUsed = false
    private(set) var tokens: Set<String> = []

    mutating func begin(now: Date = .now) -> String {
        secret = WatchSecureTransport.randomSecret().base64EncodedString()
        expiresAt = now.addingTimeInterval(120)
        attempts = 0
        codeWasUsed = false
        return currentCode(now: now)
    }

    func currentCode(now: Date = .now) -> String {
        guard let secret, now < expiresAt, attempts < 5 else { return "" }
        return WatchPairingCode(key: transportKey, secret: secret).text
    }

    mutating func pair(secret candidate: String, now: Date = .now) throws -> String {
        guard let secret else {
            throw codeWasUsed ? WatchPairingFailure.codeUsed : WatchPairingFailure.pairingClosed
        }
        guard now < expiresAt else { throw WatchPairingFailure.codeExpired }
        guard attempts < 5 else { throw WatchPairingFailure.attemptsExhausted }
        attempts += 1
        guard candidate == secret else {
            throw attempts == 5 ? WatchPairingFailure.attemptsExhausted : WatchPairingFailure.invalidCode
        }
        self.secret = nil
        codeWasUsed = true
        let token = WatchSecureTransport.randomSecret().base64EncodedString()
        tokens.insert(token)
        return token
    }

    mutating func revoke() {
        self = WatchPairingState()
    }
}
