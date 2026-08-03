import Foundation
import Testing
import OpenIslandCore

struct OpenCodeSessionRegistryTests {
    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    @Test
    func testSaveAndLoad() throws {
        let tempFileURL = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: tempFileURL) }

        let registry = OpenCodeSessionRegistry(fileURL: tempFileURL)
        let records = [
            OpenCodeTrackedSessionRecord(
                sessionID: "opencode-1",
                title: "Test Session",
                origin: .live,
                attachmentState: .attached,
                summary: "Testing OpenCode persistence",
                phase: .running,
                updatedAt: Date(),
                openCodeMetadata: OpenCodeSessionMetadata(
                    initialUserPrompt: "Hello",
                    model: "gpt-4"
                )
            )
        ]

        try registry.save(records)
        let loaded = try registry.load()

        #expect(loaded.count == 1)
        #expect(loaded[0].sessionID == "opencode-1")
        #expect(loaded[0].openCodeMetadata?.initialUserPrompt == "Hello")
    }

    @Test
    func testLoadEmpty() throws {
        let tempFileURL = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: tempFileURL) }

        let registry = OpenCodeSessionRegistry(fileURL: tempFileURL)
        let loaded = try registry.load()
        #expect(loaded.count == 0)
    }
}
