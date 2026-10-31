import Darwin
import Foundation

public final class BridgeCommandClient: @unchecked Sendable {
    private let socketURL: URL

    public init(socketURL: URL = BridgeSocketLocation.currentURL()) {
        self.socketURL = socketURL
    }

    public func send(
        _ command: BridgeCommand,
        timeout: TimeInterval = 45
    ) throws -> BridgeResponse? {
        guard timeout.isFinite, timeout > 0, timeout <= 86_400 else { throw BridgeTransportError.responseTimedOut }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor != -1 else {
            throw BridgeTransportError.systemCallFailed("socket", errno)
        }

        defer {
            close(fileDescriptor)
        }

        do {
            try disableSocketSigPipe(fileDescriptor)
            try withUnixSocketAddress(path: socketURL.path) { address, length in
                guard Darwin.connect(fileDescriptor, address, length) != -1 else {
                    throw BridgeTransportError.systemCallFailed("connect", errno)
                }
            }

            var timeoutValue = timeval(
                tv_sec: Int(timeout),
                tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
            )

            guard setsockopt(
                fileDescriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &timeoutValue,
                socklen_t(MemoryLayout<timeval>.size)
            ) != -1 else {
                throw BridgeTransportError.systemCallFailed("setsockopt", errno)
            }

            guard setsockopt(
                fileDescriptor,
                SOL_SOCKET,
                SO_SNDTIMEO,
                &timeoutValue,
                socklen_t(MemoryLayout<timeval>.size)
            ) != -1 else {
                throw BridgeTransportError.systemCallFailed("setsockopt", errno)
            }

            let data = try BridgeCodec.encodeLine(.command(command))
            try writeAll(data, to: fileDescriptor, timeout: min(timeout, 1))
        } catch {
            throw error
        }

        var buffer = Data()
        var scanCursor = 0
        var localBuffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw BridgeTransportError.responseTimedOut }
            var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(max(1, min(remaining * 1000, 1000))))
            if ready == 0 { continue }
            if ready < 0 {
                if errno == EINTR { continue }
                throw BridgeTransportError.systemCallFailed("poll read", errno)
            }
            let bytesRead = read(fileDescriptor, &localBuffer, localBuffer.count)

            if bytesRead > 0 {
                buffer.append(localBuffer, count: bytesRead)
                let messages = try BridgeCodec.decodeLines(from: &buffer, scanCursor: &scanCursor)

                for message in messages {
                    if case let .response(response) = message {
                        return response
                    }
                }

                continue
            }

            if bytesRead == 0 {
                return nil
            }

            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { continue }

            throw BridgeTransportError.systemCallFailed("read", errno)
        }
    }
}
