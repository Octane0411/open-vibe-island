import Foundation
import OpenIslandCore
import os

@MainActor
final class NtfyRemoteNotifier {
    private nonisolated(unsafe) static let logger = Logger(subsystem: "app.openisland", category: "NtfyRemoteNotifier")

    struct Config {
        var server: String
        var topic: String

        var isConfigured: Bool {
            !server.isEmpty && !topic.isEmpty
        }

        var responseTopic: String { "\(topic)-response" }
    }

    private var pendingTask: Task<Void, Never>?
    private(set) var pendingRequestID: String?

    var config: Config {
        Config(
            server: UserDefaults.standard.string(forKey: "ntfy.server") ?? "",
            topic: UserDefaults.standard.string(forKey: "ntfy.topic") ?? ""
        )
    }

    var onPermissionResponse: ((String, Bool) -> Void)?
    var onQuestionResponse: ((String, String) -> Void)?

    func sendPermissionNotification(sessionID: String, session: AgentSession) {
        guard config.isConfigured,
              let request = session.permissionRequest else {
            Self.logger.warning("sendPermissionNotification skipped: configured=\(self.config.isConfigured), hasPermissionRequest=\(session.permissionRequest != nil)")
            return
        }

        let requestID = UUID().uuidString
        pendingRequestID = requestID

        Self.logger.info("Sending permission notification: sessionID=\(sessionID), requestID=\(requestID), tool=\(request.toolName ?? "nil")")

        let title = "Open Island: \(session.title) · \(request.toolName ?? "Permission")"
        let message = request.summary.isEmpty ? request.title : request.summary

        let responseURL = "\(config.server)/\(config.responseTopic)"
        let actions: [[String: Any]] = [
            [
                "action": "http",
                "label": "Approve",
                "url": responseURL,
                "method": "POST",
                "body": "{\"requestId\":\"\(requestID)\",\"approved\":true}",
            ],
            [
                "action": "http",
                "label": "Deny",
                "url": responseURL,
                "method": "POST",
                "body": "{\"requestId\":\"\(requestID)\",\"approved\":false}",
            ],
        ]

        let body: [String: Any] = [
            "topic": config.topic,
            "title": title,
            "message": String(message.prefix(1000)),
            "actions": actions,
        ]

        Task {
            await postNotification(body: body)
        }

        pendingTask = Task { [weak self] in
            await self?.listenForResponse(requestID: requestID, sessionID: sessionID)
        }
    }

    func sendQuestionNotification(sessionID: String, session: AgentSession) {
        guard config.isConfigured,
              let prompt = session.questionPrompt else {
            Self.logger.warning("sendQuestionNotification skipped: configured=\(self.config.isConfigured), hasQuestionPrompt=\(session.questionPrompt != nil)")
            return
        }

        let requestID = UUID().uuidString
        pendingRequestID = requestID

        Self.logger.info("Sending question notification: sessionID=\(sessionID), requestID=\(requestID)")

        let title = "Open Island: \(session.title) · Question"
        let questionText = prompt.questions.first?.question ?? prompt.title
        let responseURL = "\(config.server)/\(config.responseTopic)"

        var actions: [[String: Any]] = []
        let options = prompt.questions.first?.options ?? []
        for option in options.prefix(3) {
            actions.append([
                "action": "http",
                "label": option.label,
                "url": responseURL,
                "method": "POST",
                "body": "{\"requestId\":\"\(requestID)\",\"answer\":\"\(escapeJSON(option.label))\"}",
            ])
        }

        let body: [String: Any] = [
            "topic": config.topic,
            "title": title,
            "message": String(questionText.prefix(1000)),
            "actions": actions,
        ]

        Task {
            await postNotification(body: body)
        }

        pendingTask = Task { [weak self] in
            await self?.listenForResponse(requestID: requestID, sessionID: sessionID)
        }
    }

    func cancel() {
        Self.logger.info("Cancelling pending ntfy listener, requestID=\(self.pendingRequestID ?? "nil")")
        pendingTask?.cancel()
        pendingTask = nil
        pendingRequestID = nil
    }

    // MARK: - Private

    private func postNotification(body: [String: Any]) async {
        guard let url = URL(string: config.server) else {
            Self.logger.error("postNotification: invalid server URL '\(self.config.server)'")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            Self.logger.info("postNotification: HTTP \(statusCode) to \(url.absoluteString)")
        } catch {
            Self.logger.error("postNotification failed: \(error.localizedDescription)")
        }
    }

    private nonisolated func listenForResponse(requestID: String, sessionID: String) async {
        let config = await self.config
        let streamURLString = "\(config.server)/\(config.responseTopic)/json?since=1s"
        guard let streamURL = URL(string: streamURLString) else {
            Self.logger.error("listenForResponse: invalid stream URL '\(streamURLString)'")
            return
        }

        Self.logger.info("listenForResponse: starting stream at \(streamURLString), requestID=\(requestID), sessionID=\(sessionID)")

        while !Task.isCancelled {
            var request = URLRequest(url: streamURL)
            request.timeoutInterval = .infinity

            guard let (bytes, response) = try? await URLSession.shared.bytes(for: request) else {
                Self.logger.error("listenForResponse: failed to open stream connection, retrying in 2s...")
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            Self.logger.info("listenForResponse: stream connected, HTTP \(statusCode)")

            if statusCode != 200 {
                Self.logger.error("listenForResponse: unexpected status \(statusCode), retrying in 2s...")
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            do {
                for try await line in bytes.lines {
                    guard !Task.isCancelled else {
                        Self.logger.info("listenForResponse: task cancelled, stopping")
                        return
                    }

                    let truncated = String(line.prefix(200))
                    Self.logger.debug("listenForResponse: received line: \(truncated)")

                    guard let data = line.data(using: .utf8) else {
                        Self.logger.warning("listenForResponse: line not valid UTF-8")
                        continue
                    }

                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        Self.logger.debug("listenForResponse: line is not valid JSON object")
                        continue
                    }

                    guard let messageStr = json["message"] as? String else {
                        Self.logger.debug("listenForResponse: no 'message' field in event (type=\(json["event"] as? String ?? "unknown"))")
                        continue
                    }

                    guard let messageData = messageStr.data(using: .utf8),
                          let responsePayload = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any] else {
                        Self.logger.warning("listenForResponse: 'message' field is not valid JSON: \(String(messageStr.prefix(100)))")
                        continue
                    }

                    guard let respRequestID = responsePayload["requestId"] as? String else {
                        Self.logger.warning("listenForResponse: response has no 'requestId' field, keys=\(Array(responsePayload.keys))")
                        continue
                    }

                    guard respRequestID == requestID else {
                        Self.logger.info("listenForResponse: requestId mismatch, got=\(respRequestID), expected=\(requestID)")
                        continue
                    }

                    Self.logger.info("listenForResponse: matched response! payload=\(String(messageStr.prefix(200)))")

                    await MainActor.run { [responsePayload] in
                        if let approved = responsePayload["approved"] as? Bool {
                            Self.logger.info("listenForResponse: invoking onPermissionResponse(sessionID=\(sessionID), approved=\(approved)), callback set=\(self.onPermissionResponse != nil)")
                            self.onPermissionResponse?(sessionID, approved)
                        } else if let answer = responsePayload["answer"] as? String {
                            Self.logger.info("listenForResponse: invoking onQuestionResponse(sessionID=\(sessionID), answer=\(answer)), callback set=\(self.onQuestionResponse != nil)")
                            self.onQuestionResponse?(sessionID, answer)
                        } else {
                            Self.logger.warning("listenForResponse: matched requestId but no 'approved' or 'answer' field, keys=\(Array(responsePayload.keys))")
                        }
                        self.pendingRequestID = nil
                        self.pendingTask = nil
                    }
                    return
                }
                Self.logger.info("listenForResponse: stream ended, reconnecting...")
            } catch {
                Self.logger.error("listenForResponse: stream error: \(error.localizedDescription), reconnecting...")
            }

            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
