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
    private var scanCursor = 0
    private var generation = UUID()
    private var registration: (id: UUID, continuation: CheckedContinuation<Void, Error>)?

    public init(socketURL: URL = BridgeSocketLocation.defaultURL) {
        self.socketURL = socketURL
    }

    deinit {
        readSource?.cancel()
        registration?.continuation.resume(throwing: BridgeTransportError.notConnected)
        continuation?.finish()
    }

    public func connect() throws -> AsyncThrowingStream<AgentEvent, Error> {
        try queue.sync { try connectLocked() }
    }

    private func connectLocked() throws -> AsyncThrowingStream<AgentEvent, Error> {
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

        generation = UUID()
        let connectionGeneration = generation
        let stream = AsyncThrowingStream<AgentEvent, Error>(bufferingPolicy: .bufferingOldest(64)) { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.queue.async { [weak self] in
                    guard let self, self.generation == connectionGeneration else { return }
                    self.finish(throwing: nil)
                }
            }
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.readAvailableData()
        }
        readSource.setCancelHandler { close(fileDescriptor) }
        self.readSource = readSource
        readSource.resume()

        return stream
    }

    public func send(_ command: BridgeCommand) async throws {
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

                guard self.registration == nil else {
                    continuation.resume(throwing: BridgeTransportError.alreadyConnected)
                    return
                }
                do {
                    if case .registerClient = command {
                        let id = UUID()
                        self.registration = (id, continuation)
                        try writeAll(data, to: self.fileDescriptor)
                        self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                            guard let self, self.registration?.id == id else { return }
                            self.finish(throwing: BridgeTransportError.responseTimedOut)
                            self.disconnect()
                        }
                    } else {
                        try writeAll(data, to: self.fileDescriptor)
                        continuation.resume(returning: ())
                    }
                } catch {
                    self.registration = nil
                    continuation.resume(throwing: error)
                    self.finish(throwing: error)
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
            self.scanCursor = 0
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
                    let messages = try BridgeCodec.decodeLines(from: &buffer, scanCursor: &scanCursor)

                    for message in messages {
                        if case let .event(event) = message {
                            if case .dropped = continuation?.yield(event) {
                                finish(throwing: BridgeTransportError.resourceLimit)
                                return
                            }
                        } else if case let .response(response) = message, let pending = registration {
                            registration = nil
                            if response == .acknowledged { pending.continuation.resume() }
                            else { pending.continuation.resume(throwing: BridgeTransportError.malformedEnvelope) }
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
        readSource?.cancel()
        readSource = nil
        fileDescriptor = -1
        buffer.removeAll(keepingCapacity: false)
        scanCursor = 0
        registration?.continuation.resume(throwing: error ?? BridgeTransportError.notConnected)
        registration = nil
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }

        continuation = nil
    }
}
