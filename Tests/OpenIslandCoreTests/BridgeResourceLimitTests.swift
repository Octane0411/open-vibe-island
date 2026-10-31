import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeResourceLimitTests {
    @Test
    func stalledObserverDoesNotBlockAnotherProducer() throws {
        let url = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: url)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: url) }
        let observer = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(observer) }
        try withUnixSocketAddress(path: url.path) { address, length in
            #expect(Darwin.connect(observer, address, length) == 0)
        }
        try disableSocketSigPipe(observer)
        try writeAll(BridgeCodec.encodeLine(.command(.registerClient(role: .observer))), to: observer)
        _ = fcntl(observer, F_SETFL, fcntl(observer, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(observer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        // Consume hello and registration acknowledgment, then stop reading events.
        var received = Data()
        var cursor = 0
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(observer, &buffer, buffer.count)
            #expect(count > 0)
            guard count > 0 else { return }
            received.append(buffer, count: count)
            if try BridgeCodec.decodeLines(from: &received, scanCursor: &cursor).contains(.response(.acknowledged)) { break }
        }
        let start = ContinuousClock.now
        let result = try? BridgeCommandClient(socketURL: url).send(.processOpenCodeHook(.init(
            hookEventName: .stop, sessionID: "large", cwd: "/tmp", lastAssistantMessage: String(repeating: "x", count: 1_000_000))), timeout: 0.8)
        #expect(result == .acknowledged)
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(try BridgeCommandClient(socketURL: url).send(.registerClient(role: .observer), timeout: 0.8) == .acknowledged)
    }

    @Test
    func excessConnectionsAreClosed() throws {
        let url = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: url)
        try server.start()
        var descriptors: [Int32] = []
        defer {
            descriptors.forEach { close($0) }
            server.stop()
            try? FileManager.default.removeItem(at: url)
        }
        for index in 0..<33 {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            descriptors.append(fd)
            try withUnixSocketAddress(path: url.path) { address, length in
                #expect(Darwin.connect(fd, address, length) == 0)
            }
            if index < 32 {
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var hello = [UInt8](repeating: 0, count: 1024)
                // Wait for acceptance so this tests the application limit, not the kernel listen backlog.
                #expect(read(fd, &hello, hello.count) > 0)
            }
        }
        let excess = try #require(descriptors.last)
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(excess, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var byte: UInt8 = 0
        #expect(read(excess, &byte, 1) == 0)
    }

    @Test
    func tricklingResponsesCannotExtendClientDeadline() async throws {
        let url = BridgeSocketLocation.uniqueTestURL()
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(listener); try? FileManager.default.removeItem(at: url) }
        try withUnixSocketAddress(path: url.path) { address, length in #expect(bind(listener, address, length) == 0) }
        #expect(listen(listener, 1) == 0)
        let producer = Task.detached {
            let peer = accept(listener, nil, nil)
            guard peer >= 0 else { return }
            defer { close(peer) }
            do { try disableSocketSigPipe(peer) } catch { return } // The deadline may already have closed the peer.
            for _ in 0..<20 {
                do { try writeAll(Data([10]), to: peer) } catch { return }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let start = ContinuousClock.now
        #expect(throws: BridgeTransportError.self) {
            try BridgeCommandClient(socketURL: url).send(.registerClient(role: .observer), timeout: 0.06)
        }
        #expect(ContinuousClock.now - start < .milliseconds(150))
        try await producer.value
    }

    @Test
    func oversizedUnterminatedFrameIsRejected() throws {
        var data = Data(repeating: 120, count: 8 * 1024 * 1024 + 1)
        var cursor = 0
        #expect(throws: BridgeTransportError.self) { try BridgeCodec.decodeLines(from: &data, scanCursor: &cursor) }
    }
}
