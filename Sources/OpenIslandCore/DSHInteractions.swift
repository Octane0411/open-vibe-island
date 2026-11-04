import Darwin
import Foundation

public struct DSHInteractionOption: Equatable, Codable, Sendable {
    public var label: String
    public var description: String?

    public init(label: String, description: String? = nil) {
        self.label = label
        self.description = description
    }
}

public struct DSHInteractionIntent: Equatable, Codable, Sendable {
    public var kind: String
    public var approve: String
    public var callId: String?

    public init(kind: String, approve: String, callId: String? = nil) {
        self.kind = kind
        self.approve = approve
        self.callId = callId
    }
}

public struct DSHInteractionQuestion: Equatable, Codable, Sendable {
    public var id: String
    public var question: String
    public var detail: String?
    public var header: String?
    public var options: [DSHInteractionOption]?
    public var multiSelect: Bool?
    public var intent: DSHInteractionIntent?

    public init(
        id: String, question: String, detail: String? = nil, header: String? = nil,
        options: [DSHInteractionOption]? = nil, multiSelect: Bool? = nil,
        intent: DSHInteractionIntent? = nil
    ) {
        self.id = id
        self.question = question
        self.detail = detail
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
        self.intent = intent
    }
}

/// Exact companion request data. Presentation UUIDs never replace native question IDs.
public struct DSHInteraction: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case question, plan, approval
    }

    public enum Status: String, Codable, Sendable {
        case pending, resolved
    }

    public var requestID: String
    public var kind: Kind
    public var status: Status
    public var callID: String?
    public var turnID: Int?
    public var questions: [DSHInteractionQuestion]?
    public var toolName: String?
    public var reason: String?
    public var resolution: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case kind, status, questions, reason, resolution
        case callID = "call_id"
        case turnID = "turn_id"
        case toolName = "tool_name"
    }

    public init(
        requestID: String, kind: Kind, status: Status, callID: String? = nil,
        questions: [DSHInteractionQuestion]? = nil, toolName: String? = nil,
        reason: String? = nil, resolution: String? = nil, turnID: Int? = nil
    ) {
        self.requestID = requestID
        self.kind = kind
        self.status = status
        self.callID = callID
        self.turnID = turnID
        self.questions = questions
        self.toolName = toolName
        self.reason = reason
        self.resolution = resolution
    }

    public var presentationID: UUID? {
        guard let id = UUID(uuidString: requestID),
              id.uuidString.lowercased() == requestID.lowercased() else { return nil }
        return id
    }

    public var questionPrompt: QuestionPrompt? {
        guard kind != .approval, let id = presentationID, let questions,
              !questions.isEmpty, Set(questions.map(\.id)).count == questions.count,
              questions.allSatisfy({ question in
                  let options = question.options ?? []
                  return !question.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !question.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && Set(options.map(\.label)).count == options.count
                      && options.allSatisfy { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
              }) else { return nil }
        let items = questions.map { question in
            QuestionPromptItem(
                question: question.question,
                header: question.header ?? "Question",
                options: Self.presentationOptions(for: question),
                multiSelect: question.multiSelect ?? false,
                nativeID: question.id,
                detail: question.detail
            )
        }
        return QuestionPrompt(
            id: id,
            title: questions.count == 1 ? questions[0].question : "DSH has \(questions.count) questions for you.",
            questions: items
        )
    }

    private static func presentationOptions(for question: DSHInteractionQuestion) -> [QuestionOption] {
        let nativeOptions = question.options ?? []
        guard !nativeOptions.isEmpty else { return [] }
        var label = "Other response"
        let labels = Set(nativeOptions.map(\.label))
        while labels.contains(label) { label += " (custom)" }
        return nativeOptions.map { QuestionOption(label: $0.label, description: $0.description ?? "") }
            + [QuestionOption(label: label, allowsFreeform: true)]
    }

    public var permissionRequest: PermissionRequest? {
        guard kind == .approval, let id = presentationID else { return nil }
        return PermissionRequest(
            id: id,
            title: toolName.map { "Allow \($0)" } ?? "Allow DSH action",
            summary: reason ?? "DSH needs permission to continue.",
            affectedPath: "",
            toolName: toolName,
            toolUseID: callID ?? requestID
        )
    }

    func nativeAnswers(for response: QuestionPromptResponse) throws -> [DSHInteractionAnswer] {
        guard questionPrompt != nil, let questions else { throw DSHInteractionError.invalidResponse }
        let structured = response.structuredAnswers ?? [:]
        guard Set(structured.keys).isSubset(of: Set(questions.map(\.id))) else {
            throw DSHInteractionError.invalidResponse
        }
        return try questions.map { question in
            let selected: [String]
            let custom: String?
            if let answer = structured[question.id] {
                selected = answer.selectedOptions
                custom = answer.customText
            } else if questions.count == 1, structured.isEmpty, let raw = response.rawAnswer {
                selected = []
                custom = raw
            } else {
                throw DSHInteractionError.invalidResponse
            }
            let labels = Set((question.options ?? []).map(\.label))
            guard Set(selected).count == selected.count,
                  selected.allSatisfy({ labels.contains($0) }),
                  question.multiSelect == true || selected.count <= 1,
                  (custom?.utf16.count ?? 0) <= 4096,
                  !selected.isEmpty || custom?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw DSHInteractionError.invalidResponse
            }
            return DSHInteractionAnswer(id: question.id, selected: selected, custom: custom)
        }
    }
}

struct DSHInteractionAnswer: Equatable, Codable, Sendable {
    var id: String
    var selected: [String]
    var custom: String?
}

public enum DSHInteractionError: Error, LocalizedError, Equatable {
    case staleRequest
    case invalidResponse
    case unavailable
    case timedOut
    case malformedResponse
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .staleRequest: "This DSH request is no longer active."
        case .invalidResponse: "This answer does not match the DSH request."
        case .unavailable: "The DSH interaction connection is unavailable."
        case .timedOut: "DSH did not confirm this response in time."
        case .malformedResponse: "DSH returned an invalid interaction response."
        case .rejected: "DSH could not accept this response."
        }
    }
}

struct DSHInteractionFrame: Codable, Sendable {
    var type: String
    var protocolVersion: Int?
    var observerID: String?
    var nonce: String?
    var sessionID: String?
    var interaction: DSHInteraction?

    enum CodingKeys: String, CodingKey {
        case type, nonce, interaction
        case protocolVersion = "protocol_version"
        case observerID = "observer_id"
        case sessionID = "session_id"
    }
}

struct DSHInteractionCommand: Encodable, Sendable {
    var type = "respond_interaction"
    var observerID: String
    var sessionID: String
    var requestID: String
    var answers: [DSHInteractionAnswer]?
    var decision: String?

    enum CodingKeys: String, CodingKey {
        case type, answers, decision
        case observerID = "observer_id"
        case sessionID = "session_id"
        case requestID = "request_id"
    }
}

/// One lease per private host endpoint. Cancellation closes the lease without answering.
final class DSHInteractionSubscription: @unchecked Sendable {
    let observerID: String
    let socketPath: String
    private let lock = NSLock()
    private var cancelled = false
    private let onInteraction: @Sendable (String, DSHInteraction) -> Void
    private let onDisconnect: @Sendable () -> Void

    init(
        socketPath: String, observerID: String,
        onInteraction: @escaping @Sendable (String, DSHInteraction) -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    ) {
        self.socketPath = socketPath
        self.observerID = observerID
        self.onInteraction = onInteraction
        self.onDisconnect = onDisconnect
    }

    func start() {
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { onDisconnect() }
            do { try observe() } catch { /* Native DSH resumes through the revoked lease. */ }
        }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    private func observe() throws {
        guard !lock.withLock({ cancelled }) else { return }
        let fd = try DSHInteractionSocket.connect(socketPath, timeout: 3)
        defer { close(fd) }
        guard !lock.withLock({ cancelled }) else { return }
        let subscribe = DSHInteractionFrame(
            type: "observe_interactions", protocolVersion: 1, observerID: observerID
        )
        try DSHInteractionSocket.write(subscribe, to: fd, deadline: ProcessInfo.processInfo.systemUptime + 3)
        var buffer = Data()
        var ready = false
        var deadline = ProcessInfo.processInfo.systemUptime + 12
        while !lock.withLock({ cancelled }) {
            guard try DSHInteractionSocket.wait(fd, events: Int16(POLLIN), deadline: deadline, slice: true) else { continue }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else {
                if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                throw DSHInteractionError.unavailable
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= DSHInteractionSocket.maximumFrameBytes else { throw DSHInteractionError.malformedResponse }
            while let newline = buffer.firstIndex(of: 10) {
                let data = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                let frame = try JSONDecoder().decode(DSHInteractionFrame.self, from: data)
                switch frame.type {
                case "interaction_ready":
                    guard !ready, frame.protocolVersion == 1, frame.observerID == observerID else {
                        throw DSHInteractionError.malformedResponse
                    }
                    ready = true
                case "interaction_ping":
                    guard ready, frame.observerID == observerID,
                          let nonce = frame.nonce, !nonce.isEmpty, nonce.utf8.count <= 1024 else {
                        throw DSHInteractionError.malformedResponse
                    }
                    try DSHInteractionSocket.write(
                        DSHInteractionFrame(type: "interaction_pong", observerID: observerID, nonce: nonce),
                        to: fd, deadline: ProcessInfo.processInfo.systemUptime + 3
                    )
                case "interaction":
                    guard ready, let sessionID = frame.sessionID, !sessionID.isEmpty,
                          let interaction = frame.interaction, interaction.presentationID != nil else {
                        throw DSHInteractionError.malformedResponse
                    }
                    onInteraction(sessionID, interaction)
                default:
                    throw DSHInteractionError.malformedResponse
                }
                deadline = ProcessInfo.processInfo.systemUptime + 12
            }
        }
    }
}

private enum DSHInteractionSocket {
    static let maximumFrameBytes = 1024 * 1024

    static func connect(_ path: String, timeout: TimeInterval) throws -> Int32 {
        try DSHFocusClient.validateEndpoint(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DSHInteractionError.unavailable }
        do {
            try disableSocketSigPipe(fd)
            try makeSocketNonBlocking(fd)
            let result = try withUnixSocketAddress(path: path) { address, length in
                Darwin.connect(fd, address, length)
            }
            if result != 0 {
                guard errno == EINPROGRESS || errno == EAGAIN else { throw DSHInteractionError.unavailable }
                _ = try wait(fd, events: Int16(POLLOUT), deadline: ProcessInfo.processInfo.systemUptime + timeout)
                var code: Int32 = 0
                var size = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &code, &size) == 0, code == 0 else {
                    throw DSHInteractionError.unavailable
                }
            }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    static func write<T: Encodable>(_ value: T, to fd: Int32, deadline: TimeInterval) throws {
        let data = try JSONEncoder().encode(value) + Data([10])
        guard data.count <= maximumFrameBytes else { throw DSHInteractionError.invalidResponse }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                _ = try wait(fd, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count }
                else if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                else { throw DSHInteractionError.unavailable }
            }
        }
    }

    static func wait(_ fd: Int32, events: Int16, deadline: TimeInterval, slice: Bool = false) throws -> Bool {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw DSHInteractionError.timedOut }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(remaining * 1000, 100).rounded(.up)))
            if result > 0 {
                if descriptor.revents & events != 0 { return true }
                if descriptor.revents & Int16(POLLHUP) != 0, events == Int16(POLLIN) { return true }
                throw DSHInteractionError.unavailable
            }
            if result < 0, errno != EINTR { throw DSHInteractionError.unavailable }
            if slice { return false }
        }
    }

    struct Acknowledgement: Decodable {
        var ok: Bool
        var error: String?
    }

    static func respond(path: String, command: DSHInteractionCommand, isCancelled: () -> Bool) throws {
        let fd = try connect(path, timeout: 3)
        defer { close(fd) }
        guard !isCancelled() else { throw DSHInteractionError.unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        try write(command, to: fd, deadline: deadline)
        var buffer = Data()
        while true {
            _ = try wait(fd, events: Int16(POLLIN), deadline: deadline)
            var bytes = [UInt8](repeating: 0, count: 1024)
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else {
                if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                throw DSHInteractionError.unavailable
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 8192 else { throw DSHInteractionError.malformedResponse }
            if let newline = buffer.firstIndex(of: 10) {
                guard let response = try? JSONDecoder().decode(Acknowledgement.self, from: buffer[..<newline]) else {
                    throw DSHInteractionError.malformedResponse
                }
                guard response.ok else {
                    if response.error == "stale-request" { throw DSHInteractionError.staleRequest }
                    throw DSHInteractionError.rejected(response.error ?? "invalid-request")
                }
                return
            }
        }
    }
}

extension DSHInteractionSubscription {
    func respond(_ command: DSHInteractionCommand) throws {
        guard !lock.withLock({ cancelled }), command.observerID == observerID else {
            throw DSHInteractionError.unavailable
        }
        try DSHInteractionSocket.respond(path: socketPath, command: command, isCancelled: { lock.withLock { cancelled } })
    }
}
