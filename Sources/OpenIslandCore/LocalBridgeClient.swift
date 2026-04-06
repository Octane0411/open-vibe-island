import Dispatch
import Darwin
import Foundation

public final class LocalBridgeClient: @unchecked Sendable {
    private let socketURL: URL
    private let queue = DispatchQueue(label: "app.openisland.bridge.client")

    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation?
    private var buffer = Data()

    public init(socketURL: URL = BridgeSocketLocation.defaultURL) {
        self.socketURL = socketURL
    }

    public func connect() throws -> AsyncThrowingStream<AgentEvent, Error> {
        guard fileDescriptor == -1 else {
            throw BridgeTransportError.alreadyConnected
        }

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor != -1 else {
            throw BridgeTransportError.systemCallFailed("socket", errno)
        }

        do {
            try disableSocketSigPipe(fileDescriptor)
            try withUnixSocketAddress(path: socketURL.path) { address, length in
                guard Darwin.connect(fileDescriptor, address, length) != -1 else {
                    throw BridgeTransportError.systemCallFailed("connect", errno)
                }
            }
            try makeSocketNonBlocking(fileDescriptor)
        } catch {
            close(fileDescriptor)
            throw error
        }

        self.fileDescriptor = fileDescriptor

        let stream = AsyncThrowingStream<AgentEvent, Error> { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.disconnect()
            }
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.readAvailableData()
        }
        readSource.setCancelHandler { [weak self] in
            guard let self else {
                return
            }

            if self.fileDescriptor != -1 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.readSource = readSource
        readSource.resume()

        return stream
    }

    public func send(_ command: BridgeCommand) async throws {
        guard fileDescriptor != -1 else {
            throw BridgeTransportError.notConnected
        }

        let data = try BridgeCodec.encodeLine(.command(command))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: BridgeTransportError.notConnected)
                    return
                }

                guard self.fileDescriptor != -1 else {
                    continuation.resume(throwing: BridgeTransportError.notConnected)
                    return
                }

                do {
                    try writeAll(data, to: self.fileDescriptor)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func disconnect() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.readSource?.cancel()
            self.readSource = nil
            self.buffer.removeAll(keepingCapacity: false)
            self.finish(throwing: nil)
        }
    }

    private func readAvailableData() {
        guard fileDescriptor != -1 else {
            return
        }

        var localBuffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let bytesRead = read(fileDescriptor, &localBuffer, localBuffer.count)

            if bytesRead > 0 {
                buffer.append(localBuffer, count: bytesRead)

                do {
                    let messages = try BridgeCodec.decodeLines(from: &buffer)

                    for message in messages {
                        if case let .event(event) = message {
                            continuation?.yield(event)
                        }
                    }
                } catch {
                    finish(throwing: error)
                    readSource?.cancel()
                    readSource = nil
                    return
                }

                continue
            }

            if bytesRead == 0 {
                finish(throwing: nil)
                readSource?.cancel()
                readSource = nil
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            finish(throwing: BridgeTransportError.systemCallFailed("read", errno))
            readSource?.cancel()
            readSource = nil
            return
        }
    }

    private func finish(throwing error: Error?) {
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }

        continuation = nil
    }
}
