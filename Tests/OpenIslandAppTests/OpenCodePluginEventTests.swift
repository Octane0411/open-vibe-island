import Foundation
import Testing
@testable import OpenIslandApp

// Loads the bundled `open-island-opencode.js` in node, feeds it OpenCode bus
// events and records the hook payloads it forwards to the bridge socket.
// Skipped when node is not on PATH so the suite still runs without it.
@Suite(.enabled(
    if: OpenCodePluginNodeRuntime.isAvailable,
    "Requires node on PATH to load the OpenCode plugin"
))
struct OpenCodePluginEventTests {
    @Test
    func childSessionsDoNotStartOrCompleteIslandSessions() throws {
        let hooks = try forwardedHooks(for: [
            sessionEvent("session.created", id: "ses_root"),
            sessionEvent("session.created", id: "ses_child", parentID: "ses_root"),
            event("message.updated", [
                "info": ["id": "msg_child", "sessionID": "ses_child", "role": "user"],
            ]),
            event("message.part.updated", [
                "part": ["type": "text", "messageID": "msg_child", "sessionID": "ses_child", "text": "Explore"],
            ]),
            toolPart(sessionID: "ses_child", status: "running"),
            toolPart(sessionID: "ses_child", status: "completed"),
            sessionIdle(id: "ses_child"),
            sessionEvent("session.deleted", id: "ses_child", parentID: "ses_root"),
            // A plugin-injected child the plugin only learns about from session.updated.
            sessionEvent("session.updated", id: "ses_compartment", parentID: "ses_root"),
            sessionIdle(id: "ses_compartment"),
            sessionIdle(id: "ses_root"),
        ])

        #expect(hooks.map(\.summary) == [
            "SessionStart opencode-ses_root",
            "Stop opencode-ses_root",
        ])
    }

    @Test
    func childApprovalsAndQuestionsSurfaceOnRootSession() throws {
        let hooks = try forwardedHooks(for: [
            sessionEvent("session.created", id: "ses_root"),
            sessionEvent("session.created", id: "ses_child", parentID: "ses_root"),
            sessionEvent("session.created", id: "ses_grandchild", parentID: "ses_child"),
            event("permission.asked", [
                "id": "per_1", "sessionID": "ses_grandchild", "permission": "bash", "patterns": ["ls"],
            ]),
            event("permission.replied", ["sessionID": "ses_grandchild", "requestID": "per_1", "reply": "once"]),
            event("question.asked", [
                "id": "que_1", "sessionID": "ses_child",
                "questions": [["question": "Which file?", "header": "File", "options": [["label": "README.md"]]]],
            ]),
            event("question.replied", ["sessionID": "ses_child", "requestID": "que_1"]),
        ])

        #expect(hooks.map(\.summary) == [
            "SessionStart opencode-ses_root",
            "PermissionRequest opencode-ses_root",
            "PostToolUse opencode-ses_root",
            "QuestionAsked opencode-ses_root",
            "PostToolUse opencode-ses_root",
        ])
        // The island still answers through the original OpenCode request ID.
        let permission = try #require(hooks.first { $0.eventName == "PermissionRequest" })
        #expect(permission.payload["permission_id"] as? String == "per_1")
        #expect(permission.payload["_opencode_request_id"] as? String == "per_1")
        let question = try #require(hooks.first { $0.eventName == "QuestionAsked" })
        #expect(question.payload["question_id"] as? String == "que_1")
        #expect(question.payload["_opencode_request_id"] as? String == "que_1")
    }

    // MARK: - Harness

    struct ForwardedHook {
        var payload: [String: Any]

        var eventName: String { payload["hook_event_name"] as? String ?? "?" }

        var summary: String { "\(eventName) \(payload["session_id"] as? String ?? "?")" }
    }

    private func event(_ type: String, _ properties: [String: Any]) -> [String: Any] {
        ["type": type, "properties": properties]
    }

    private func sessionEvent(_ type: String, id: String, parentID: String? = nil) -> [String: Any] {
        var info: [String: Any] = ["id": id, "directory": "/tmp/open-island"]
        info["parentID"] = parentID
        return event(type, ["info": info])
    }

    private func toolPart(sessionID: String, status: String) -> [String: Any] {
        event("message.part.updated", [
            "part": ["type": "tool", "sessionID": sessionID, "tool": "read", "state": ["status": status]],
        ])
    }

    private func sessionIdle(id: String) -> [String: Any] {
        event("session.status", ["sessionID": id, "status": ["type": "idle"]])
    }

    private func forwardedHooks(for events: [[String: Any]]) throws -> [ForwardedHook] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-opencode-events-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oi-oc-\(UUID().uuidString.prefix(8)).sock")
        defer { try? FileManager.default.removeItem(at: socketURL) }

        let sourceURL = try #require(
            Bundle.appResources.url(forResource: "open-island-opencode", withExtension: "js")
        )
        // `.mjs` so node loads the ES module regardless of its syntax detection.
        let pluginURL = root.appendingPathComponent("open-island.mjs")
        try FileManager.default.copyItem(at: sourceURL, to: pluginURL)
        let harnessURL = root.appendingPathComponent("event-harness.mjs")
        try Data(Self.nodeHarness.utf8).write(to: harnessURL)
        let eventsJSON = try JSONSerialization.data(withJSONObject: events)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "node",
            harnessURL.path,
            pluginURL.path,
            socketURL.path,
            String(decoding: eventsJSON, as: UTF8.self),
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "OpenCodePluginEventTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: String(decoding: errorOutput, as: UTF8.self),
                ]
            )
        }

        let payloads = try #require(
            try JSONSerialization.jsonObject(with: output) as? [[String: Any]]
        )
        return payloads.map(ForwardedHook.init(payload:))
    }

    private static let nodeHarness = #"""
    import { createServer } from "node:net";
    import { unlink } from "node:fs/promises";
    import { pathToFileURL } from "node:url";

    const [pluginPath, socketPath, eventsJSON] = process.argv.slice(2);
    process.env.OPEN_ISLAND_SOCKET_PATH = socketPath;
    await unlink(socketPath).catch(() => {});

    const hooks = [];
    const server = createServer((socket) => {
      let buffer = "";
      socket.on("data", (chunk) => { buffer += chunk; });
      socket.on("end", () => {
        for (const line of buffer.trim().split("\n")) {
          if (line) hooks.push(JSON.parse(line).command.openCodeHook);
        }
      });
    });
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(socketPath, resolve);
    });

    const plugin = await import(pathToFileURL(pluginPath).href);
    // No internal fetch: approvals and questions are sent fire-and-forget,
    // so every forwarded payload reaches the socket in order.
    const handlers = await plugin.default({ client: {}, serverUrl: null });
    for (const event of JSON.parse(eventsJSON)) {
      await handlers.event({ event });
    }

    await new Promise((resolve) => server.close(resolve));
    await unlink(socketPath).catch(() => {});
    console.log(JSON.stringify(hooks));
    """#
}

/// Whether `node` is on PATH. The plugin is plain JavaScript, so any version
/// that can import ES modules can load it.
enum OpenCodePluginNodeRuntime {
    static let isAvailable: Bool = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "--version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }()
}
