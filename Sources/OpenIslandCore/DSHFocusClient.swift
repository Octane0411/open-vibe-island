import Darwin
import Foundation

public struct DSHWebJumpTarget: Equatable, Codable, Sendable {
    public var sessionID: String
    public var origin: String
    public var focusSocketPath: String

    public init(sessionID: String, origin: String, focusSocketPath: String) {
        self.sessionID = sessionID
        self.origin = origin
        self.focusSocketPath = focusSocketPath
    }
}

public enum DSHFocusError: Error, LocalizedError, Equatable {
    case unsafeEndpoint
    case unavailable
    case timedOut
    case malformedResponse
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeEndpoint:
            "The DSH focus endpoint is not a private socket owned by this user."
        case .unavailable:
            "DSH Web is unavailable. Restart DSH after updating its Open Island plugin."
        case .timedOut:
            "DSH did not confirm the conversation focus in time."
        case .malformedResponse:
            "DSH returned an invalid conversation focus response."
        case .rejected(let code):
            switch code {
            case "not-found": "This conversation is no longer loaded in DSH."
            case "no-client": "Open the installed DSH Web app and reload it after updating the plugin."
            case "busy", "superseded": "Another conversation jump replaced this request."
            default: "DSH could not focus the selected conversation."
            }
        }
    }
}

/// Sends only a session selector to the private local DSH companion.
/// It never sends an authenticated Web URL, tool command, or approval decision.
public enum DSHFocusClient {
    public static func validateEndpoint(_ path: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let directory = url.deletingLastPathComponent()
        guard path.hasPrefix("/"), url.path == path,
              ["/tmp", "/private/tmp"].contains(directory.deletingLastPathComponent().path),
              directory.lastPathComponent.hasPrefix("oi-dsh-focus-"), url.lastPathComponent == "focus.sock" else {
            throw DSHFocusError.unsafeEndpoint
        }
        var parent = stat()
        guard lstat(directory.path, &parent) == 0,
              parent.st_mode & S_IFMT == S_IFDIR,
              parent.st_uid == getuid(), parent.st_mode & 0o077 == 0 else {
            throw DSHFocusError.unsafeEndpoint
        }
        var attributes = stat()
        guard lstat(path, &attributes) == 0 else { throw DSHFocusError.unavailable }
        guard attributes.st_mode & S_IFMT == S_IFSOCK,
              attributes.st_uid == getuid(), attributes.st_mode & 0o077 == 0 else {
            throw DSHFocusError.unsafeEndpoint
        }
    }

    public static func focus(_ target: DSHWebJumpTarget, timeout: TimeInterval = 8) throws {
        try validateEndpoint(target.focusSocketPath)
        guard !target.sessionID.isEmpty, target.sessionID.utf8.count <= 1024,
              timeout.isFinite, timeout > 0, timeout <= 30 else {
            throw DSHFocusError.malformedResponse
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DSHFocusError.unavailable }
        defer { close(fd) }
        try disableSocketSigPipe(fd)
        try makeSocketNonBlocking(fd)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let connected = try withUnixSocketAddress(path: target.focusSocketPath) { address, length in
            Darwin.connect(fd, address, length)
        }
        if connected != 0 {
            guard errno == EINPROGRESS || errno == EAGAIN else { throw DSHFocusError.unavailable }
            try wait(fd, events: Int16(POLLOUT), deadline: deadline)
            var code: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &code, &size) == 0, code == 0 else {
                throw DSHFocusError.unavailable
            }
        }
        let request = try JSONEncoder().encode(Request(sessionID: target.sessionID)) + Data([10])
        try request.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try wait(fd, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count }
                else if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                else { throw DSHFocusError.unavailable }
            }
        }
        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            try wait(fd, events: Int16(POLLIN), deadline: deadline)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count > 0 {
                response.append(contentsOf: chunk.prefix(count))
                guard response.count <= 8192 else { throw DSHFocusError.malformedResponse }
                if let newline = response.firstIndex(of: 10) {
                    try validateResponse(Data(response[..<newline]))
                    return
                }
            } else if count == 0 {
                throw DSHFocusError.malformedResponse
            } else if errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK {
                throw DSHFocusError.unavailable
            }
        }
    }

    private struct Request: Encodable {
        var sessionID: String
        enum CodingKeys: String, CodingKey { case sessionID = "session_id" }
    }

    private struct Response: Decodable {
        var ok: Bool
        var error: String?
    }

    private static func validateResponse(_ data: Data) throws {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw DSHFocusError.malformedResponse
        }
        guard response.ok else {
            let allowed = ["not-found", "no-client", "busy", "timeout", "disposed", "focus-failed", "superseded"]
            let code = response.error ?? "focus-failed"
            throw DSHFocusError.rejected(allowed.contains(code) ? code : "focus-failed")
        }
    }

    private static func wait(_ fd: Int32, events: Int16, deadline: TimeInterval) throws {
        while true {
            try Task.checkCancellation()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw DSHFocusError.timedOut }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            // Short slices make cancellation responsive without extending the absolute deadline.
            let result = poll(&descriptor, 1, Int32(min(remaining * 1000, 100).rounded(.up)))
            if result > 0 {
                if descriptor.revents & events != 0 { return }
                if descriptor.revents & Int16(POLLHUP) != 0, events == Int16(POLLIN) { return }
                throw DSHFocusError.unavailable
            }
            if result < 0, errno != EINTR { throw DSHFocusError.unavailable }
        }
    }
}
