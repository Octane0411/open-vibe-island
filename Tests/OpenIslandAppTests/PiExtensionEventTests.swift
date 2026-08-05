import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

struct PiExtensionEventTests {
    @Test(arguments: [PiAgentVariant.pi, .ohMyPi])
    func emitsCanonicalLifecycleAndHeartbeat(agent: PiAgentVariant) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-pi-events-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oi-\(UUID().uuidString.prefix(8)).sock")
        defer { try? FileManager.default.removeItem(at: socketURL) }

        let sourceURL = try #require(
            Bundle.appResources.url(forResource: "open-island-pi", withExtension: "ts")
        )
        let manager = PiExtensionInstallationManager(agent: agent, agentDirectory: root)
        let installed = try manager.install(extensionSourceData: Data(contentsOf: sourceURL))
        let completionEvent = agent == .ohMyPi ? "session_stop" : "agent_settled"
        let harnessURL = root.appendingPathComponent("event-harness.mjs")
        try Data(Self.nodeHarness.utf8).write(to: harnessURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "node",
            harnessURL.path,
            installed.extensionURL.path,
            socketURL.path,
            completionEvent,
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
                domain: "PiExtensionEventTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: String(decoding: errorOutput, as: UTF8.self),
                ]
            )
        }

        let result = try #require(
            try JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        let events = try #require(result["events"] as? [String])
        let registered = try #require(result["registered"] as? [String])

        #expect(result["stopCountBeforeCompletion"] as? Int == 0)
        #expect(events.filter { $0 == "PreToolUse" }.count == 1)
        #expect(events.filter { $0 == "PostToolUse" }.count == 1)
        #expect(events.filter { $0 == "Stop" }.count == 1)
        #expect(events.filter { $0 == "SessionEnd" }.count == 1)
        #expect(events.contains("Heartbeat"))
        #expect(result["heartbeatCountAfterShutdown"] as? Int == result["heartbeatCountAtShutdown"] as? Int)
        #expect(result["shutdownWasAwaitable"] as? Bool == true)
        #expect(registered.contains(completionEvent))
        let unrelatedCompletionEvent = agent == .ohMyPi ? "agent_settled" : "session_stop"
        #expect(!registered.contains(unrelatedCompletionEvent))
        #expect(!registered.contains("turn_end"))
        #expect(!registered.contains("agent_end"))
        #expect(!registered.contains("tool_call"))
        #expect(!registered.contains("tool_result"))
    }

    private static let nodeHarness = #"""
    import { createServer } from "node:net";
    import { unlink } from "node:fs/promises";
    import { pathToFileURL } from "node:url";

    const [extensionPath, socketPath, completionEvent] = process.argv.slice(2);
    process.env.OPEN_ISLAND_SOCKET_PATH = socketPath;
    process.env.OPEN_ISLAND_HEARTBEAT_INTERVAL_MS = "20";
    await unlink(socketPath).catch(() => {});

    const commands = [];
    const server = createServer((socket) => {
      let buffer = "";
      socket.on("data", (chunk) => { buffer += chunk; });
      socket.on("end", () => {
        for (const line of buffer.trim().split("\n")) {
          if (line) commands.push(JSON.parse(line).command.piHook.hook_event_name);
        }
      });
    });
    await new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(socketPath, resolve);
    });

    const extension = await import(`${pathToFileURL(extensionPath).href}?test=${Date.now()}`);
    const handlers = new Map();
    extension.default({
      on(name, handler) {
        if (handlers.has(name)) throw new Error(`duplicate handler: ${name}`);
        handlers.set(name, handler);
      },
    });

    const context = {
      cwd: "/tmp/open-island",
      sessionManager: {
        getSessionId: () => "event-sequence",
        getSessionFile: () => "/tmp/open-island/session.jsonl",
      },
    };
    const emit = (name, event = {}) => handlers.get(name)?.(event, context);
    const waitForEvent = async (name, count = 1) => {
      const deadline = Date.now() + 3000;
      while (commands.filter((eventName) => eventName === name).length < count && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      if (commands.filter((eventName) => eventName === name).length < count) {
        throw new Error(`did not receive ${name} ${count} time(s)`);
      }
    };

    emit("session_start");
    await waitForEvent("Heartbeat");
    emit("before_agent_start", { prompt: "Run the tool" });
    emit("tool_execution_start", { toolName: "read", args: { path: "README.md" } });
    emit("tool_call", { toolName: "read", input: { path: "README.md" } });
    emit("tool_result", { toolName: "read" });
    emit("tool_execution_end", { toolName: "read" });
    emit("turn_end");
    emit("turn_start");
    await waitForEvent("PostToolUse");
    const stopCountBeforeCompletion = commands.filter((name) => name === "Stop").length;

    emit(completionEvent);
    await waitForEvent("Stop");
    const shutdownResult = emit("session_shutdown", { reason: "quit" });
    const shutdownWasAwaitable = shutdownResult instanceof Promise;
    await shutdownResult;
    await waitForEvent("SessionEnd");
    const heartbeatCountAtShutdown = commands.filter((name) => name === "Heartbeat").length;
    await new Promise((resolve) => setTimeout(resolve, 80));
    const heartbeatCountAfterShutdown = commands.filter((name) => name === "Heartbeat").length;
    await new Promise((resolve) => server.close(resolve));
    await unlink(socketPath).catch(() => {});

    console.log(JSON.stringify({
      events: commands,
      registered: [...handlers.keys()],
      stopCountBeforeCompletion,
      heartbeatCountAtShutdown,
      heartbeatCountAfterShutdown,
      shutdownWasAwaitable,
    }));
    """#
}
