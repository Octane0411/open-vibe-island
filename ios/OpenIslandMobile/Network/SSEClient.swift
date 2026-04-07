import Foundation
import os

/// Parses and delivers Server-Sent Events from the macOS WatchHTTPEndpoint.
final class SSEClient: NSObject, @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.openisland.mobile", category: "SSEClient")

    private let baseURL: URL
    private let token: String
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var buffer = ""

    /// Called on main queue when an SSE event is received.
    var onEvent: (@MainActor (String, Data) -> Void)?

    /// Called on main queue when the connection is lost.
    var onDisconnect: (@MainActor () -> Void)?

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
        super.init()
    }

    func connect() {
        disconnect()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity

        let urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = urlSession

        var request = URLRequest(url: baseURL.appendingPathComponent("events"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let task = urlSession.dataTask(with: request)
        self.task = task
        task.resume()

        Self.logger.info("SSE connecting to \(self.baseURL.absoluteString)/events")
    }

    func disconnect() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        buffer = ""
    }

    // MARK: - SSE Parsing

    private func processBuffer() {
        // SSE format: "event: <type>\ndata: <json>\n\n"
        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            parseSSEBlock(block)
        }
    }

    private func parseSSEBlock(_ block: String) {
        var eventType: String?
        var dataLines: [String] = []

        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix("event: ") {
                eventType = String(line.dropFirst("event: ".count))
            } else if line.hasPrefix("data: ") {
                dataLines.append(String(line.dropFirst("data: ".count)))
            } else if line == "data" {
                // Bare "data" field per SSE spec = empty line in payload
                dataLines.append("")
            } else if line.hasPrefix(":") {
                // Comment line (keepalive), ignore
                continue
            }
        }

        guard let eventType, !dataLines.isEmpty else {
            return
        }

        // SSE spec: multiple data lines are joined with "\n"
        let dataString = dataLines.joined(separator: "\n")
        guard let data = dataString.data(using: .utf8) else {
            return
        }

        Self.logger.info("SSE received event: \(eventType)")

        let handler = self.onEvent
        Task { @MainActor in
            handler?(eventType, data)
        }
    }
}

// MARK: - URLSessionDataDelegate

extension SSEClient: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text
        processBuffer()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            Self.logger.warning("SSE connection ended: \(error.localizedDescription)")
        } else {
            Self.logger.info("SSE connection completed")
        }

        let handler = self.onDisconnect
        Task { @MainActor in
            handler?()
        }
    }
}
