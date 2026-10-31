import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeListenerIsolationTests {
    @Test
    func customServersDoNotReplaceAnExplicitLegacyListener() throws {
        let production = BridgeSocketLocation.uniqueTestURL()
        let legacy = BridgeSocketLocation.uniqueTestURL()
        let first = BridgeSocketLocation.uniqueTestURL()
        let second = BridgeSocketLocation.uniqueTestURL()
        defer {
            for url in [production, legacy, first, second] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let existingServer = BridgeServer(socketURL: production, legacySocketURL: legacy)
        try existingServer.start()
        defer { existingServer.stop() }
        let sentinel = try FileManager.default.attributesOfItem(atPath: legacy.path)[.systemFileNumber] as? NSNumber

        let firstServer = BridgeServer(socketURL: first)
        let secondServer = BridgeServer(socketURL: second)
        try firstServer.start()
        defer { firstServer.stop() }
        try secondServer.start()
        defer { secondServer.stop() }

        for url in [legacy, first, second] {
            #expect(try BridgeCommandClient(socketURL: url).send(.registerClient(role: .observer), timeout: 1) == .acknowledged)
        }
        #expect(try FileManager.default.attributesOfItem(atPath: legacy.path)[.systemFileNumber] as? NSNumber == sentinel)
    }
}
