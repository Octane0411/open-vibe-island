import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

// The harnesses below import the installed `open-island.ts` as-is, which
// relies on Node's built-in type stripping. Skip (rather than fail) when
// node is missing or too old so an unsupported Node on the CI runner does
// not turn into a red build.
@Suite(.enabled(
    if: PiExtensionNodeRuntime.isAvailable,
    "Requires node >= 22.6 on PATH to load the TypeScript extension"
))
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
        process.arguments = ["node"] + PiExtensionNodeRuntime.launchArguments + [
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
            let errorDescription =
                String(bytes: errorOutput, encoding: .utf8)
                ?? "Pi extension event harness produced non-UTF-8 stderr."
            throw NSError(
                domain: "PiExtensionEventTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: errorDescription,
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

    @Test(arguments: ["abc", "0", "-1", "1.5", "999999999999999999999"])
    func rejectsIllegalHeartbeatIntervalWithoutStorm(interval: String) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-island-pi-heartbeat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oi-hb-\(UUID().uuidString.prefix(8)).sock")
        defer { try? FileManager.default.removeItem(at: socketURL) }

        let sourceURL = try #require(
            Bundle.appResources.url(forResource: "open-island-pi", withExtension: "ts")
        )
        let manager = PiExtensionInstallationManager(agent: .pi, agentDirectory: root)
        let installed = try manager.install(extensionSourceData: Data(contentsOf: sourceURL))
        let harnessURL = root.appendingPathComponent("heartbeat-harness.mjs")
        try Data(Self.illegalHeartbeatHarness.utf8).write(to: harnessURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node"] + PiExtensionNodeRuntime.launchArguments + [
            harnessURL.path,
            installed.extensionURL.path,
            socketURL.path,
            interval,
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
            let errorDescription =
                String(bytes: errorOutput, encoding: .utf8)
                ?? "Pi extension event harness produced non-UTF-8 stderr."
            throw NSError(
                domain: "PiExtensionEventTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: errorDescription,
                ]
            )
        }

        let result = try #require(
            try JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
        #expect(result["heartbeatCount"] as? Int == 0)
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

    private static let illegalHeartbeatHarness = #"""
    import { createServer } from "node:net";
    import { unlink } from "node:fs/promises";
    import { pathToFileURL } from "node:url";

    const [extensionPath, socketPath, interval] = process.argv.slice(2);
    process.env.OPEN_ISLAND_SOCKET_PATH = socketPath;
    process.env.OPEN_ISLAND_HEARTBEAT_INTERVAL_MS = interval;
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
        getSessionId: () => "heartbeat-interval",
        getSessionFile: () => "/tmp/open-island/session.jsonl",
      },
    };
    handlers.get("session_start")?.({}, context);
    await new Promise((resolve) => setTimeout(resolve, 150));
    const heartbeatCount = commands.filter((name) => name === "Heartbeat").length;
    const shutdownResult = handlers.get("session_shutdown")?.({ reason: "quit" }, context);
    if (shutdownResult instanceof Promise) await shutdownResult;
    await new Promise((resolve) => server.close(resolve));
    await unlink(socketPath).catch(() => {});

    console.log(JSON.stringify({ heartbeatCount }));
    """#
}

/// Locates `node` on PATH once and works out whether it can load the
/// TypeScript extension directly.
///
/// Type stripping shipped behind `--experimental-strip-types` in Node 22.6,
/// and is on by default since 22.18 and 23.6 (and every later major).
/// Anything older cannot import `.ts` at all, so the suite is skipped.
enum PiExtensionNodeRuntime {
    struct Capability: Equatable, Sendable {
        var major: Int
        var minor: Int
        var launchArguments: [String]
    }

    static let capability: Capability? = detect()

    static var isAvailable: Bool { capability != nil }

    /// Extra arguments to place before the script path when launching node.
    static var launchArguments: [String] { capability?.launchArguments ?? [] }

    /// Returns `nil` when a Node of this version cannot load `.ts` modules.
    static func launchArguments(forNodeMajor major: Int, minor: Int) -> [String]? {
        switch major {
        case ..<22:
            return nil
        case 22 where minor < 6:
            return nil
        case 22 where minor < 18, 23 where minor < 6:
            return ["--experimental-strip-types"]
        default:
            return []
        }
    }

    private static func detect() -> Capability? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "--version"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: output, encoding: .utf8) else {
            return nil
        }

        // `node --version` prints e.g. "v22.18.0".
        let components = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "v" })
            .split(separator: ".")
        guard components.count >= 2,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let arguments = launchArguments(forNodeMajor: major, minor: minor) else {
            return nil
        }
        return Capability(major: major, minor: minor, launchArguments: arguments)
    }
}

struct PiExtensionNodeRuntimeTests {
    @Test(arguments: [
        (20, 19, nil),
        (22, 5, nil),
        (22, 6, ["--experimental-strip-types"]),
        (22, 17, ["--experimental-strip-types"]),
        (22, 18, []),
        (23, 5, ["--experimental-strip-types"]),
        (23, 6, []),
        (24, 0, []),
        (26, 0, []),
    ] as [(Int, Int, [String]?)])
    func launchArgumentsFollowTypeStrippingAvailability(major: Int, minor: Int, expected: [String]?) {
        #expect(PiExtensionNodeRuntime.launchArguments(forNodeMajor: major, minor: minor) == expected)
    }
}
