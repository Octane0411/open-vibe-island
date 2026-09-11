import Foundation
import Network
import Testing
import OpenIslandTransport

struct WatchHTTPClientFailureTests {
    @Test func malformedHeaderBytesFailBeforeDeliveringResponse() async throws {
        let reply = Data("HTTP/1.1 200 OK\r\nX-Test: ".utf8) + Data([0xFF]) + Data("\r\n\r\nprivate".utf8)
        let server = try BonjourTransportTestServer(reply: reply)
        defer { server.stop() }
        try await securityWait { !server.ready.values.isEmpty }
        let statuses = SecurityRecorder<Int>()
        let body = SecurityRecorder<Data>()
        let errors = SecurityRecorder<WatchTransportError>()
        let stream = try WatchHTTPStream(endpoint: server.endpoint, key: server.key)
        defer { stream.cancel() }
        stream.start(path: "status", onResponse: { statuses.append($0) }, onData: { body.append($0) }, onComplete: {
            if let error = $0 as? WatchTransportError { errors.append(error) }
        })
        try await securityWait { !errors.values.isEmpty }
        #expect(errors.values == [.invalidResponse])
        #expect(statuses.values.isEmpty)
        #expect(body.values.isEmpty)
    }

    @Test func stalledBodyUsesResponseDeadline() async throws {
        let server = try BonjourTransportTestServer(
            reply: Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n".utf8), closesAfterReply: false
        )
        defer { server.stop() }
        try await securityWait { !server.ready.values.isEmpty }
        let started = Date()
        await #expect(throws: WatchTransportError.timedOut) {
            try await WatchHTTPClient.request(endpoint: server.endpoint, key: server.key, path: "status")
        }
        #expect(Date().timeIntervalSince(started) >= 14)
    }

    @Test func callerCancellationRemainsCancellation() async throws {
        let server = try BonjourTransportTestServer(reply: Data("HTTP/1.1 200 OK\r\n\r\n".utf8), closesAfterReply: false)
        defer { server.stop() }
        try await securityWait { !server.ready.values.isEmpty }
        let task = Task { try await WatchHTTPClient.request(endpoint: server.endpoint, key: server.key, path: "status") }
        try await securityWait { !server.requests.values.isEmpty }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func unavailableServiceWaitsUntilConnectionDeadline() async throws {
        let endpoint = NWEndpoint.service(
            name: "absent-\(UUID().uuidString)", type: WatchSecureTransport.serviceType, domain: "local.", interface: nil
        )
        let started = Date()
        await #expect(throws: WatchTransportError.timedOut) {
            try await WatchHTTPClient.request(endpoint: endpoint, key: WatchSecureTransport.randomSecret(), path: "status")
        }
        #expect(Date().timeIntervalSince(started) >= 9)
    }
}
