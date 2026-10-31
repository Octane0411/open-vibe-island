import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeSocketIdentityTests {
    @Test
    func secondServerCannotReplaceLiveSocket() throws {
        let url = BridgeSocketLocation.uniqueTestURL()
        let first = BridgeServer(socketURL: url)
        try first.start()
        defer { first.stop(); try? FileManager.default.removeItem(at: url) }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let second = BridgeServer(socketURL: url)
        #expect(throws: (any Error).self) { try second.start() }
        defer { second.stop() }
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber)
        #expect(try BridgeCommandClient(socketURL: url).send(.registerClient(role: .observer)) == .acknowledged)
        #expect((after[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test(arguments: [false, true])
    func unrelatedFileOrSymlinkIsNeverRemoved(symlink: Bool) throws {
        let url = BridgeSocketLocation.uniqueTestURL()
        let target = url.appendingPathExtension("target")
        let contents = Data("user data".utf8)
        try contents.write(to: symlink ? target : url)
        if symlink { try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target) }
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: target)
        }
        let server = BridgeServer(socketURL: url)
        #expect(throws: (any Error).self) { try server.start() }
        defer { server.stop() }
        #expect(try Data(contentsOf: url) == contents)
    }
}
