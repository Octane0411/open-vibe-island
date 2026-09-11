import Foundation

/// Receives bounded UTF-8 events through the same authenticated transport as pairing.
final class SSEClient: @unchecked Sendable {
    private let baseURL: URL
    private let credentials: WatchCredentials
    private var stream: WatchHTTPStream?
    private var buffer = Data()
    private var accepted = false

    var onEvent: (@MainActor (String, Data) -> Void)?
    var onDisconnect: (@MainActor () -> Void)?
    var onUnauthorized: (@MainActor () -> Void)?

    init(baseURL: URL, credentials: WatchCredentials) {
        self.baseURL = baseURL
        self.credentials = credentials
    }

    func connect() {
        do {
            let stream = try WatchHTTPStream(baseURL: baseURL, key: credentials.key)
            self.stream = stream
            stream.start(path: "events", token: credentials.token, onResponse: { [weak self] status in
                self?.accepted = status == 200
                if status == 401 {
                    let handler = self?.onUnauthorized
                    Task { @MainActor in handler?() }
                }
                if status != 200 { self?.stream?.cancel() }
            }, onData: { [weak self] in self?.receive($0) }, onComplete: { [weak self] _ in
                let handler = self?.onDisconnect
                Task { @MainActor in handler?() }
            })
        } catch {
            let handler = onDisconnect
            Task { @MainActor in handler?() }
        }
    }

    func disconnect() { stream?.cancel() }

    private func receive(_ bytes: Data) {
        guard accepted else { return }
        buffer.append(bytes)
        guard buffer.count <= 262_144 else { stream?.cancel(); return }
        while let separator = buffer.range(of: Data("\n\n".utf8)) {
            let block = Data(buffer[..<separator.lowerBound])
            buffer.removeSubrange(..<separator.upperBound)
            guard let text = String(data: block, encoding: .utf8) else { stream?.cancel(); return }
            deliver(text)
        }
    }

    private func deliver(_ block: String) {
        let lines = block.components(separatedBy: "\n")
        guard let type = lines.first(where: { $0.hasPrefix("event: ") })?.dropFirst(7) else { return }
        let payload = lines.filter { $0.hasPrefix("data: ") }.map { String($0.dropFirst(6)) }.joined(separator: "\n")
        let handler = onEvent
        Task { @MainActor in handler?(String(type), Data(payload.utf8)) }
    }
}
