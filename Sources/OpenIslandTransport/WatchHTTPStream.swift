import Foundation
import Network

/// A bounded HTTP/1.1 response stream carried exclusively inside authenticated TLS.
public final class WatchHTTPStream: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.openisland.secure-http")
    private let connection: NWConnection
    private var headerBuffer = Data()
    private var receivedHeaders = false
    private var finished = false
    private var started = false
    private var responseHandler: (@Sendable (Int) -> Void)?
    private var dataHandler: (@Sendable (Data) -> Void)?
    private var completionHandler: (@Sendable ((any Error)?) -> Void)?

    public init(baseURL: URL, key: Data) throws {
        guard baseURL.scheme == "https", let host = baseURL.host,
              let portNumber = baseURL.port, let port = NWEndpoint.Port(rawValue: UInt16(exactly: portNumber) ?? 0),
              portNumber > 0 else { throw WatchTransportError.invalidResponse }
        connection = NWConnection(
            host: NWEndpoint.Host(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))),
            port: port, using: try WatchSecureTransport.parameters(key: key)
        )
    }

    public func start(
        path: String, method: String = "GET", token: String? = nil, body: Data = Data(),
        onResponse: @escaping @Sendable (Int) -> Void,
        onData: @escaping @Sendable (Data) -> Void,
        onComplete: @escaping @Sendable ((any Error)?) -> Void
    ) {
        queue.async { [self] in
            guard !finished else { onComplete(CancellationError()); return }
            guard !started else { onComplete(WatchTransportError.invalidResponse); return }
            started = true
            responseHandler = onResponse
            dataHandler = onData
            completionHandler = onComplete
            guard let request = Self.request(path: path, method: method, token: token, body: body) else {
                finish(WatchTransportError.invalidResponse)
                return
            }
            connect(request)
        }
    }

    public func cancel() {
        queue.async { [self] in finish(CancellationError()) }
    }

    private func connect(_ request: Data) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.finished else { return }
            switch state {
            case .ready:
                self.connection.send(content: request, completion: .contentProcessed { [weak self] error in
                    if let error { self?.finish(error) } else { self?.receive() }
                })
            case let .failed(error), let .waiting(error): self.finish(error)
            case .cancelled: self.finish(CancellationError())
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, !self.receivedHeaders else { return }
            self.finish(WatchTransportError.timedOut)
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, ended, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty { self.consume(data) }
            if let error { self.finish(error) }
            else if ended { self.finish(self.receivedHeaders ? nil : WatchTransportError.invalidResponse) }
            else if !self.finished { self.receive() }
        }
    }

    private func consume(_ data: Data) {
        if receivedHeaders { dataHandler?(data); return }
        headerBuffer.append(data)
        guard headerBuffer.count <= 65_536 else { finish(WatchTransportError.oversizedMessage); return }
        guard let separator = headerBuffer.range(of: Data("\r\n\r\n".utf8)) else { return }
        let header = String(decoding: headerBuffer[..<separator.lowerBound], as: UTF8.self)
        let parts = header.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0] == "HTTP/1.1", let status = Int(parts[1]),
              !header.lowercased().contains("transfer-encoding:") else {
            finish(WatchTransportError.invalidResponse)
            return
        }
        receivedHeaders = true
        responseHandler?(status)
        let remainder = Data(headerBuffer[separator.upperBound...])
        headerBuffer.removeAll()
        if !remainder.isEmpty { dataHandler?(remainder) }
    }

    private func finish(_ error: (any Error)?) {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        let handler = completionHandler
        completionHandler = nil
        dataHandler = nil
        responseHandler = nil
        handler?(error)
    }

    private static func request(path: String, method: String, token: String?, body: Data) -> Data? {
        guard ["pair", "events", "resolution", "status"].contains(path),
              ["GET", "POST"].contains(method),
              token?.contains(where: { $0.isNewline }) != true else { return nil }
        var header = "\(method) /\(path) HTTP/1.1\r\nHost: open-island\r\nConnection: close\r\n"
        if let token { header += "Authorization: Bearer \(token)\r\n" }
        header += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n"
        return Data(header.utf8) + body
    }
}
