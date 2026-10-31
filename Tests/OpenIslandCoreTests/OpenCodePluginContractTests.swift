import Foundation
import Testing
@testable import OpenIslandCore

struct OpenCodePluginContractTests {
    @Test
    func swiftDecisionReachesRealJavaScriptPluginAsOrderedAnswers() async throws {
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: socket) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PluginTests/roundtrip.mjs")
        process.arguments = ["node", script.path]
        process.environment = ProcessInfo.processInfo.environment.merging(["OPEN_ISLAND_SOCKET_PATH": socket.path]) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let deadline = ContinuousClock.now + .seconds(3)
        while server.sessionStateSnapshotForTests().session(id: "opencode-contract")?.questionPrompt == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let prompt = try #require(server.sessionStateSnapshotForTests().session(id: "opencode-contract")?.questionPrompt)
        _ = try await server.decide(.question(sessionID: "opencode-contract", requestID: prompt.id,
            response: .init(answers: ["Choose colors": "Red, Blue", "Choose size": "Large"], orderedAnswers: [["Red", "Blue"], ["Large"]])))
        while process.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!process.isRunning)
        guard !process.isRunning else { return }
        let json = try #require(JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [String: [[String]]])
        #expect(json["answers"] == [["Red", "Blue"], ["Large"]])
    }
}
