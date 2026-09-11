import Foundation
import Network
import Testing
import OpenIslandTransport

struct WatchBonjourTransportTests {
    @Test func connectsToBonjourServiceDirectlyOverAuthenticatedTLS() async throws {
        let server = try BonjourTransportTestServer()
        defer { server.stop() }
        try await securityWait { !server.ready.values.isEmpty }
        let response = try await WatchHTTPClient.request(endpoint: server.endpoint, key: server.key, path: "status")
        #expect(response.status == 200)
        #expect(response.body == Data("{}".utf8))
        #expect(server.requests.values.first?.hasPrefix("GET /status HTTP/1.1\r\n") == true)
    }
}

private final class BonjourTransportTestServer: @unchecked Sendable {
    let key = WatchSecureTransport.randomSecret()
    let ready = SecurityRecorder<Bool>()
    let requests = SecurityRecorder<String>()
    let endpoint: NWEndpoint
    private let listener: NWListener
    private let queue = DispatchQueue(label: "open-island.test.bonjour")
    private var connections: [NWConnection] = []

    init() throws {
        let name = "open-island-test-\(UUID().uuidString)"
        endpoint = .service(name: name, type: WatchSecureTransport.serviceType, domain: "local.", interface: nil)
        listener = try NWListener(using: WatchSecureTransport.parameters(key: key))
        listener.service = NWListener.Service(name: name, type: WatchSecureTransport.serviceType)
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            if case .add = change { self?.ready.append(true) }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            listener.cancel()
            for connection in connections { connection.cancel() }
            connections.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, ended, error in
            guard let self else { return }
            let bytes = buffer + (data ?? Data())
            guard bytes.count <= 8192 else { connection.cancel(); return }
            guard bytes.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if !ended && error == nil { self.receive(connection, buffer: bytes) }
                else { connection.cancel() }
                return
            }
            self.requests.append(String(decoding: bytes, as: UTF8.self))
            let reply = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}".utf8)
            connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
