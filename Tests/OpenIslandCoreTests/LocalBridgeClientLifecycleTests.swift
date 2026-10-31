import Foundation
import Testing
@testable import OpenIslandCore

struct LocalBridgeClientLifecycleTests {
    @Test
    func releasingObserverFinishesItsEventStream() async throws {
        let url = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: url)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: url) }
        let stream: AsyncThrowingStream<AgentEvent, Error>
        do {
            let client = LocalBridgeClient(socketURL: url)
            stream = try client.connect()
            try await client.send(.registerClient(role: .observer))
        }
        let ended = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do { for try await _ in stream {} } catch {}
                return true
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(200))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(ended)
    }
}
