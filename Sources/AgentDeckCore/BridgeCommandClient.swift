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
            try writeAll(data, to: fileDescriptor)
        } catch {
            throw error
        }

        var buffer = Data()
        var localBuffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let bytesRead = read(fileDescriptor, &localBuffer, localBuffer.count)

            if bytesRead > 0 {
                buffer.append(localBuffer, count: bytesRead)
                let messages = try BridgeCodec.decodeLines(from: &buffer)

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

            if errno == EAGAIN || errno == EWOULDBLOCK {
                throw BridgeTransportError.responseTimedOut
            }

            throw BridgeTransportError.systemCallFailed("read", errno)
        }
    }
}
