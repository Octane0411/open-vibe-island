import Foundation
import Network
import Testing
@testable import OpenIslandCore
import OpenIslandTransport

struct WatchRecoveryTests {
    @Test func listenerCreationFailureCanBeRestarted() async throws {
        let attempts = SecurityRecorder<Bool>()
        let endpoint = WatchHTTPEndpoint(listenerFactory: { parameters in
            attempts.append(true)
            if attempts.values.count == 1 { throw NWError.posix(.EADDRINUSE) }
            return try NWListener(using: parameters)
        })
        defer { endpoint.stop() }
        try await restartUntilListening(endpoint)
        #expect(attempts.values.count == 2)
    }

    @Test func failedListenerStateCanBeRestarted() async throws {
        let blocker = try NWListener(using: .tcp)
        blocker.newConnectionHandler = { $0.cancel() }
        blocker.start(queue: DispatchQueue(label: "open-island.test.occupied-port"))
        defer { blocker.cancel() }
        try await securityWait { if case .ready = blocker.state { true } else { false } }
        let port = try #require(blocker.port)
        let attempts = SecurityRecorder<Bool>()
        let endpoint = WatchHTTPEndpoint(listenerFactory: { parameters in
            attempts.append(true)
            return try NWListener(using: parameters, on: attempts.values.count == 1 ? port : .any)
        })
        defer { endpoint.stop() }
        try await restartUntilListening(endpoint)
        #expect(attempts.values.count == 2)
        #expect(endpoint.listeningPort != port.rawValue)
    }

    @Test func pairingErrorsExplainRetryAndRecovery() async throws {
        let endpoint = WatchHTTPEndpoint()
        defer { endpoint.stop() }
        try await restartUntilListening(endpoint)
        let port = try #require(endpoint.listeningPort)
        let target = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        endpoint.regeneratePairingCode()
        let code = try WatchPairingCode(endpoint.currentCode())
        for attempt in 1...5 {
            let response = try await sendPairing(target, key: code.key, secret: "incorrect")
            #expect(response.status == (attempt < 5 ? 403 : 429))
            let failure = try JSONDecoder().decode(WatchPairingFailureResponse.self, from: response.body)
            #expect(failure.error == (attempt < 5 ? .invalidCode : .attemptsExhausted))
        }
        #expect(try await sendPairing(target, key: code.key, secret: code.secret).status == 429)
        endpoint.regeneratePairingCode()
        let renewed = try WatchPairingCode(endpoint.currentCode())
        #expect(try await sendPairing(target, key: renewed.key, secret: renewed.secret).status == 200)
        #expect(try await sendPairing(target, key: renewed.key, secret: renewed.secret).status == 409)
    }

    @Test func pairingCodeCodablePreservesValidation() throws {
        let code = WatchPairingCode(key: WatchSecureTransport.randomSecret(), secret: WatchSecureTransport.randomSecret().base64EncodedString())
        let encoded = try JSONEncoder().encode(code)
        #expect(try JSONDecoder().decode(WatchPairingCode.self, from: encoded).text == code.text)
        #expect(throws: WatchTransportError.invalidPairingCode) {
            try JSONDecoder().decode(WatchPairingCode.self, from: Data(#""OI2.truncated.invalid""#.utf8))
        }
    }
}

private func restartUntilListening(_ endpoint: WatchHTTPEndpoint) async throws {
    for _ in 0..<500 {
        endpoint.start()
        if endpoint.listeningPort != nil { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw WatchTransportError.timedOut
}

private func sendPairing(_ endpoint: NWEndpoint, key: Data, secret: String) async throws -> WatchHTTPResponse {
    let body = try JSONEncoder().encode(WatchPairRequest(code: secret))
    return try await WatchHTTPClient.request(endpoint: endpoint, key: key, path: "pair", method: "POST", body: body)
}
