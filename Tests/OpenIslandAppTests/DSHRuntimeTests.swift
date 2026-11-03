import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@Suite(.enabled(if: PiExtensionNodeRuntime.isAvailable, "Requires Node on PATH"))
struct DSHRuntimeTests {
    @Test
    func bundledPluginRunsThroughInstalledPackageAndSwiftBridge() async throws {
        let sourceURL = try #require(
            Bundle.appResources.url(forResource: "open-island-dsh", withExtension: "js", subdirectory: "open-island-dsh")
                ?? Bundle.appResources.url(forResource: "open-island-dsh", withExtension: "js")
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("oi-dsh-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{\"name\":\"test-profile\"}".utf8).write(to: root.appendingPathComponent("package.json"))
        let installed = try DSHPluginInstallationManager(dshProfileDirectory: root).install(pluginSourceData: Data(contentsOf: sourceURL))
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { deadline.cancel() }
        try await observer.send(.registerClient(role: .observer))

        let harnessURL = root.appendingPathComponent("smoke.mjs")
        try Data(Self.harness.utf8).write(to: harnessURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", harnessURL.path, installed.pluginFileURL.path, socketURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let diagnostics = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(process.terminationStatus == 0, Comment(rawValue: diagnostics))

        var state = SessionState()
        for try await event in stream {
            state.apply(event)
            if case let .sessionCompleted(payload) = event, payload.isSessionEnd == true { break }
        }
        let session = try #require(state.session(id: "dsh-bundle-smoke"))
        #expect(session.tool == .dsh)
        #expect(session.latestUserPromptText == "Build integration")
        #expect(session.lastAssistantMessageText == "Integration ready")
        #expect(session.isSessionEnded)
    }

    // Host stand-in only. The public DSH classes are covered by the Node API tests.
    // This smoke checks app resource lookup, managed installation, and real Swift ingress together.
    private static let harness = #"""
    import { pathToFileURL } from 'node:url'
    const [pluginPath, socketPath] = process.argv.slice(2)
    const plugin = await import(pathToFileURL(pluginPath).href)
    const sessions = new Map()
    const handlers = new Map()
    const cleanups = []
    plugin.apply({
      sessions: { list: () => [], get: id => sessions.get(id) },
      on: (name, handler) => handlers.set(name, handler),
      effect: effect => cleanups.push(effect()),
    }, { socketPath })
    const session = { id: 'dsh-bundle-smoke', header: { cwd: '/tmp/project' } }
    sessions.set(session.id, session)
    handlers.get('session/created')(session)
    const emit = (type, data) => handlers.get('session/event')(session, { type, data })
    emit('user/message', { source: { kind: 'user' }, content: 'Build integration' })
    emit('assistant/message', { message: { content: 'Integration ready' } })
    emit('turn/end', { turn: 1, reason: { kind: 'completed' } })
    for (const cleanup of cleanups) await cleanup()
    """#
}
