import XCTest
import OpenIslandCore

final class OpenCodeSessionRegistryTests: XCTestCase {
    var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    func testSaveAndLoad() throws {
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

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].sessionID, "opencode-1")
        XCTAssertEqual(loaded[0].openCodeMetadata?.initialUserPrompt, "Hello")
    }

    func testLoadEmpty() throws {
        let registry = OpenCodeSessionRegistry(fileURL: tempFileURL)
        let loaded = try registry.load()
        XCTAssertEqual(loaded.count, 0)
    }
}
