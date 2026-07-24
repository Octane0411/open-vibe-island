import Foundation
import Testing
@testable import OpenIslandCore

/// Pins the read-buffer behavior of `CodexAppServerClient.handleIncomingData`:
///
/// 1. A multi-line burst is parsed end-to-end and the buffer is fully drained
///    (the previous `Data(slice)` rebuild was O(N²) per line — switching to
///    `removeSubrange` keeps it O(N) total).
/// 2. A trailing partial line stays in the buffer, intact, awaiting more bytes.
/// 3. A runaway producer that never sends `\n` triggers the safety cap rather
///    than letting `readBuffer` grow without bound.
struct CodexAppServerBufferTests {
    @Test
    func threadListDecodesCurrentDataEnvelope() async throws {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 1
        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting

        let request = Task { try await client.listThreads(limit: 10) }
        try await Task.sleep(for: .milliseconds(20))
        client.handleIncomingData(Data("""
        {"jsonrpc":"2.0","id":1,"result":{"data":[{"id":"thread-1","cwd":"/tmp/project","name":"Real task name","preview":"Prompt","modelProvider":"openai","createdAt":1,"updatedAt":2,"ephemeral":false,"path":"/tmp/rollout.jsonl","status":{"type":"notLoaded"},"source":"app-server","turns":[]}]}}

        """.utf8))

        let threads = try await request.value
        #expect(threads.map(\.id) == ["thread-1"])
        #expect(threads.first?.name == "Real task name")
    }

    @Test
    func multiLineBurstIsFullyDrainedAndAllLinesParsed() {
        let client = CodexAppServerClient()

        let received = LockedNotifications()
        client.onNotification = { received.append($0) }

        let burst = ([
            #"{"method":"alpha","params":{}}"#,
            #"{"method":"beta","params":{}}"#,
            #"{"method":"gamma","params":{}}"#,
        ].joined(separator: "\n") + "\n").data(using: .utf8)!

        client.handleIncomingData(burst)

        let notifications = received.snapshot()
        #expect(notifications.count == 3)
        #expect(notifications.compactMap(unknownMethod) == ["alpha", "beta", "gamma"])
        #expect(client.readBufferCountForTests == 0)
    }

    @Test
    func trailingPartialLineStaysInBufferUntilNewlineArrives() {
        let client = CodexAppServerClient()
        let received = LockedNotifications()
        client.onNotification = { received.append($0) }

        let firstChunk = #"{"method":"alpha","params":{}}"# + "\n" + #"{"method":"par"#
        client.handleIncomingData(Data(firstChunk.utf8))

        var notifications = received.snapshot()
        #expect(notifications.count == 1)
        #expect(client.readBufferCountForTests > 0)

        let secondChunk = #"tial","params":{}}"# + "\n"
        client.handleIncomingData(Data(secondChunk.utf8))

        notifications = received.snapshot()
        #expect(notifications.count == 2)
        #expect(notifications.compactMap(unknownMethod) == ["alpha", "partial"])
        #expect(client.readBufferCountForTests == 0)
    }

    @Test
    func runawayBufferIsCappedAndDropped() {
        let client = CodexAppServerClient()

        // Feed garbage past the cap WITHOUT a newline. Without the bound
        // the buffer would keep growing on every chunk forever.
        let chunkSize = 1 * 1_024 * 1_024
        let chunk = Data(count: chunkSize)
        for _ in 0..<10 {
            client.handleIncomingData(chunk)
        }

        // Total fed (10 MB) exceeds the 8 MB cap, so the buffer must
        // have been cleared at least once. The exact remaining count
        // depends on which chunk tipped past the threshold; what we
        // pin is that we never settle above the cap.
        #expect(client.readBufferCountForTests <= CodexAppServerClient.maxLineByteCount)
    }

    // MARK: - Helpers

    private func unknownMethod(_ notification: CodexAppServerNotification) -> String? {
        if case let .unknown(method) = notification {
            return method
        }
        return nil
    }
}

/// Thread-safe collector for the `@Sendable` notification callback.
private final class LockedNotifications: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CodexAppServerNotification] = []

    func append(_ notification: CodexAppServerNotification) {
        lock.lock()
        items.append(notification)
        lock.unlock()
    }

    func snapshot() -> [CodexAppServerNotification] {
        lock.lock()
        let copy = items
        lock.unlock()
        return copy
    }
}
