import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeLiveSessionIndexTests {
    private func makeSessionsDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-live-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    @Test
    func returnsUserAssignedNamesOnly() throws {
        let rootURL = try makeSessionsDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        // `/rename` / `--name` writes `name` without a `nameSource`.
        try #"{"pid":100,"sessionId":"session-user","name":"checkout-flow","status":"busy"}"#
            .write(to: rootURL.appendingPathComponent("100.json"), atomically: true, encoding: .utf8)
        // Explicit user marker.
        try #"{"pid":101,"sessionId":"session-user-explicit","name":"payments","nameSource":"user"}"#
            .write(to: rootURL.appendingPathComponent("101.json"), atomically: true, encoding: .utf8)
        // Auto-generated names are marked "derived" (or "auto") and must be skipped.
        try #"{"pid":102,"sessionId":"session-derived","name":"open-vibe-island-db","nameSource":"derived"}"#
            .write(to: rootURL.appendingPathComponent("102.json"), atomically: true, encoding: .utf8)
        try #"{"pid":103,"sessionId":"session-auto","name":"generated-topic","nameSource":"auto"}"#
            .write(to: rootURL.appendingPathComponent("103.json"), atomically: true, encoding: .utf8)
        // No name at all.
        try #"{"pid":104,"sessionId":"session-unnamed","status":"idle"}"#
            .write(to: rootURL.appendingPathComponent("104.json"), atomically: true, encoding: .utf8)
        // Malformed JSON must not break the scan.
        try #"{"pid":105,"sessionId":"#
            .write(to: rootURL.appendingPathComponent("105.json"), atomically: true, encoding: .utf8)
        // Non-JSON files are ignored.
        try "not a session".write(to: rootURL.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let index = ClaudeLiveSessionIndex(rootURL: rootURL)
        let names = index.userAssignedSessionNames()

        #expect(names == [
            "session-user": "checkout-flow",
            "session-user-explicit": "payments",
        ])
    }

    @Test
    func returnsEmptyForMissingDirectory() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-claude-live-index-missing-\(UUID().uuidString)", isDirectory: true)

        let index = ClaudeLiveSessionIndex(rootURL: missingURL)

        #expect(index.userAssignedSessionNames().isEmpty)
    }
}
