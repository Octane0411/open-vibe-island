import Foundation
import Network
import Testing
@testable import OpenIslandCore
import OpenIslandTransport

struct WatchSecurityTests {
    @Test func pairingIsExplicitExpiringLimitedAndSingleUse() throws {
        var state = WatchPairingState()
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(state.currentCode(now: now).isEmpty)
        #expect(state.pair(secret: "0000", now: now) == nil)
        let expired = try WatchPairingCode(state.begin(now: now))
        #expect(state.pair(secret: expired.secret, now: now.addingTimeInterval(120)) == nil)
        #expect(state.currentCode(now: now.addingTimeInterval(121)).isEmpty)
        let limited = try WatchPairingCode(state.begin(now: now))
        for _ in 0..<5 { #expect(state.pair(secret: "wrong", now: now) == nil) }
        #expect(state.pair(secret: limited.secret, now: now) == nil)
        let valid = try WatchPairingCode(state.begin(now: now))
        let pairedToken = state.pair(secret: valid.secret, now: now)
        let token = try #require(pairedToken)
        #expect(Data(base64Encoded: token)?.count == 32)
        #expect(state.pair(secret: valid.secret, now: now) == nil)
        state.revoke()
        #expect(state.tokens.isEmpty)
        #expect(state.transportKey != valid.key)
        #expect(state.currentCode(now: now).isEmpty)
    }

    @Test func parserWaitsForBodyAndRejectsAmbiguousRequests() throws {
        let header = "POST /pair HTTP/1.1\r\nContent-Length: 2\r\n\r\n"
        #expect(try WatchHTTPRequest.parse(Data((header + "{").utf8)) == nil)
        #expect(try WatchHTTPRequest.parse(Data((header + "{}").utf8))?.body == "{}")
        let invalid = [
            header + "{}extra",
            "POST /pair HTTP/1.1\r\nContent-Length: 2\r\ncontent-length: 2\r\n\r\n{}",
            "POST /pair HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
            "POST /pair HTTP/1.1\r\nContent-Length: 65537\r\n\r\n",
            String(repeating: "a", count: 8193)
        ]
        for request in invalid {
            #expect(throws: (any Error).self) { try WatchHTTPRequest.parse(Data(request.utf8)) }
        }
    }

    @Test func securePairingEnforcesAuthorizationAndRevocation() async throws {
        let endpoint = WatchHTTPEndpoint()
        let resolutions = SecurityRecorder<String>()
        endpoint.onResolution = { resolutions.append($0.requestID) }
        endpoint.start()
        defer { endpoint.stop() }
        let url = try await listeningURL(endpoint)
        #expect(endpoint.currentCode().isEmpty)
        endpoint.regeneratePairingCode()
        let code = try WatchPairingCode(endpoint.currentCode())
        let token = try await pair(endpoint, url: url, code: code)
        try await checkAuthorization(url: url, code: code, token: token, resolutions: resolutions)
        try await checkEventsAndRevocation(endpoint, url: url, code: code, token: token)
    }

    @Test func rejectsWrongEncryptionKeyAndPlainHTTP() async throws {
        let endpoint = WatchHTTPEndpoint()
        endpoint.start()
        defer { endpoint.stop() }
        let url = try await listeningURL(endpoint)
        do {
            _ = try await WatchHTTPClient.request(baseURL: url, key: WatchSecureTransport.randomSecret(), path: "status")
            Issue.record("A connection with the wrong key reached HTTP")
        } catch { /* TLS must fail before any HTTP response. */ }
        let response = await PlainHTTPProbe(url: url).run()
        #expect(!String(decoding: response, as: UTF8.self).contains("HTTP/1.1"))
    }
}

private func pair(_ endpoint: WatchHTTPEndpoint, url: URL, code: WatchPairingCode) async throws -> String {
    let body = try JSONEncoder().encode(WatchPairRequest(code: code.secret))
    let reply = try await WatchHTTPClient.request(baseURL: url, key: code.key, path: "pair", method: "POST", body: body)
    #expect(reply.status == 200)
    #expect(endpoint.currentCode().isEmpty)
    let replay = try await WatchHTTPClient.request(baseURL: url, key: code.key, path: "pair", method: "POST", body: body)
    #expect(replay.status == 403)
    return try JSONDecoder().decode(WatchPairResponse.self, from: reply.body).token
}

private func checkAuthorization(
    url: URL, code: WatchPairingCode, token: String, resolutions: SecurityRecorder<String>
) async throws {
    let body = Data(#"{"requestID":"request-1","action":"allow"}"#.utf8)
    let denied = try await WatchHTTPClient.request(baseURL: url, key: code.key, path: "resolution", method: "POST", body: body)
    #expect(denied.status == 401)
    #expect(resolutions.values.isEmpty)
    let accepted = try await WatchHTTPClient.request(
        baseURL: url, key: code.key, path: "resolution", method: "POST", token: token, body: body
    )
    #expect(accepted.status == 200)
    #expect(resolutions.values == ["request-1"])
    let invalidToken = try await WatchHTTPClient.request(baseURL: url, key: code.key, path: "status", token: "wrong")
    #expect(invalidToken.status == 401)
}

private func checkEventsAndRevocation(
    _ endpoint: WatchHTTPEndpoint, url: URL, code: WatchPairingCode, token: String
) async throws {
    let chunks = SecurityRecorder<Data>()
    let closed = SecurityRecorder<Bool>()
    let stream = try WatchHTTPStream(baseURL: url, key: code.key)
    stream.start(path: "events", token: token, onResponse: { #expect($0 == 200) },
                 onData: { chunks.append($0) }, onComplete: { _ in closed.append(true) })
    defer { stream.cancel() }
    try await securityWait { endpoint.connectedDeviceCount == 1 }
    endpoint.pushEvent(.actionableStateResolved(.init(requestID: "private-event", sessionID: "test")))
    try await securityWait { String(decoding: chunks.values.reduce(Data(), +), as: UTF8.self).contains("private-event") }
    endpoint.revokeAllTokens()
    try await securityWait { !closed.values.isEmpty }
    #expect(endpoint.connectedDeviceCount == 0)
    let renewedURL = try await listeningURL(endpoint)
    do {
        _ = try await WatchHTTPClient.request(baseURL: renewedURL, key: code.key, path: "status", token: token)
        Issue.record("Revoked transport credentials still work")
    } catch { }
}

private func listeningURL(_ endpoint: WatchHTTPEndpoint) async throws -> URL {
    try await securityWait { endpoint.listeningPort != nil }
    let port = try #require(endpoint.listeningPort)
    return try #require(URL(string: "https://127.0.0.1:\(port)"))
}

func securityWait(_ predicate: () -> Bool) async throws {
    for _ in 0..<500 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw WatchTransportError.timedOut
}

final class SecurityRecorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []
    var values: [Value] { lock.withLock { storage } }
    func append(_ value: Value) { lock.withLock { storage.append(value) } }
}

private final class PlainHTTPProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "open-island.test.plain-http")
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Data, Never>?

    init(url: URL) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: UInt16(url.port!))!, using: .tcp)
    }

    func run() async -> Data {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.continuation = continuation
                connection.stateUpdateHandler = { [self] state in
                    switch state {
                    case .ready: send()
                    case .failed, .cancelled: finish(Data())
                    default: break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + 3) { [self] in finish(Data()) }
            }
        }
    }

    private func send() {
        let data = Data("GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        connection.send(content: data, completion: .contentProcessed { [self] _ in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, _, _ in
                finish(data ?? Data())
            }
        })
    }

    private func finish(_ data: Data) {
        guard let continuation else { return }
        self.continuation = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: data)
    }
}
