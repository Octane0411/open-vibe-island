import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["DSH_PACKAGE_ROOT"] != nil, "Set DSH_PACKAGE_ROOT for published DSH API composition"))
struct DSHInteractionRuntimeTests {
    @Test
    func publishedHostRoundTripsNativeCardsAndExplicitDecisionsThroughTheSwiftBridge() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("oi-dsh-interactive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }
        let model = AppModel(
            dshQuestionAction: { try await server.answerDSHQuestion(sessionID: $0, requestID: $1, response: $2) },
            dshPermissionAction: { try await server.resolveDSHPermission(sessionID: $0, requestID: $1, resolution: $2) }
        )
        let observer = LocalBridgeClient(socketURL: socket)
        let events = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))
        let source = try #require(Bundle.appResources.url(forResource: "open-island-dsh", withExtension: "js", subdirectory: "open-island-dsh")
            ?? Bundle.appResources.url(forResource: "open-island-dsh", withExtension: "js"))
        let fixture = root.appendingPathComponent("published-runtime.mjs")
        try Data(Self.fixture.utf8).write(to: fixture)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", fixture.path, source.path, socket.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled {
                if process.isRunning { process.terminate() }
                observer.disconnect()
            }
        }
        defer { timeout.cancel() }
        var questionKinds: Set<String> = []
        var approvalSeen = false
        for try await event in events {
            model.state.apply(event)
            switch event {
            case let .questionAsked(payload):
                let questions = payload.prompt.questions
                let plan = questions.first?.nativeID == "plan-review"
                questionKinds.insert(plan ? "plan" : "question")
                if plan {
                    #expect(questions.first?.detail?.contains("## Verification") == true)
                }
                let selections: [String: Set<String>] = plan ? ["plan-review": ["Approve"]] : ["first": ["Read, then write"]]
                let response = try #require(NativeQuestionAnswerBuilder.response(
                    questions: questions, selections: selections, freeformTexts: plan ? [:] : ["second": "local"]
                ))
                model.answerQuestion(for: payload.sessionID, answer: response, requestID: payload.prompt.id)
            case let .permissionRequested(payload):
                approvalSeen = true
                model.approvePermission(for: payload.sessionID, action: .allowOnce, requestID: payload.request.id)
            case let .sessionCompleted(payload) where payload.isSessionEnd == true:
                break
            default:
                continue
            }
            if case let .sessionCompleted(payload) = event, payload.isSessionEnd == true { break }
        }
        process.waitUntilExit()
        let diagnostics = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        try #require(process.terminationStatus == 0, Comment(rawValue: diagnostics))
        #expect(questionKinds == ["question", "plan"])
        #expect(approvalSeen)
        let session = try #require(model.state.session(id: "native-roundtrip-session"))
        #expect(session.isSessionEnded)
        #expect(session.questionPrompt == nil)
        #expect(session.permissionRequest == nil)
        #expect(session.lastAssistantMessageText?.contains("\n\n") == true)
        #expect((session.lastAssistantMessageText?.count ?? 0) > 110)
    }

    // Only synthetic in-memory DSH sessions are used. The approval policy belongs
    // to this disposable Context and never changes the user's live DSH instance.
    private static let fixture = #"""
    import assert from 'node:assert/strict'
    import { createRequire } from 'node:module'
    import { join } from 'node:path'
    import { pathToFileURL } from 'node:url'
    import { setTimeout as delay } from 'node:timers/promises'
    const [pluginPath, socketPath] = process.argv.slice(2)
    const require = createRequire(join(process.env.DSH_PACKAGE_ROOT, 'package.json'))
    const load = name => import(pathToFileURL(require.resolve('@deepseek-ai/' + name)).href)
    const [{ Context }, { default: SessionStore }, { UserQuestionService }, { ApprovalService }, { PlanModeController }, plugin] = await Promise.all([
      load('cordis'), load('dsh-session'), load('dsh-user-questions'), load('dsh-user-approval'), load('dsh-plan-mode'), import(pathToFileURL(pluginPath).href),
    ])
    const ctx = new Context()
    // The real Web host owns a referenced HTTP server. Keep this disposable
    // host alive while the observer and explicit UI response are in flight.
    const keepAlive = setInterval(() => {}, 1000)
    await ctx.plugin(SessionStore).inertia
    const session = ctx.sessions.create('native-roundtrip-session')
    const agent = { id: 'native-roundtrip-root', session, ctx }
    ctx.provide('agents', { get: id => id === agent.id ? agent : undefined, roots: () => [agent] })
    ctx.provide('connection', { browserPeer: {}, rpc: { handle: () => () => {} } })
    ctx.provide('webApp', { getAdvertisedUrl: () => 'http://127.0.0.1:3080/' })
    await ctx.plugin(UserQuestionService).inertia
    await ctx.plugin(ApprovalService, { policy: 'ask' }).inertia
    ctx.on('user-questions/request', request => ({ answers: request.questions.map(question => ({ id: question.id, selected: [], custom: 'native-fixture-fallback' })) }))
    ctx.on('approval/request', () => 'rejected')
    const host = ctx.plugin(plugin, { socketPath })
    await host.inertia
    try {
      session.append('turn/start', { turn: 1 })
      const questions = [
        { id: 'first', question: 'Which?', options: [{ label: 'Read, then write' }], multiSelect: true },
        { id: 'second', question: 'Which?' },
      ]
      const deadline = Date.now() + 10000
      let answers
      do {
        assert.ok(Date.now() < deadline, 'Native interaction observer did not become ready')
        session.append('tool/call', { turn: 1, step: 1, callId: 'question-call', name: 'ask_user_question', arguments: JSON.stringify({ questions }) })
        answers = await ctx.userQuestions.ask({ agent, questions })
        if (answers.answers.every(answer => answer.custom === 'native-fixture-fallback')) await delay(20)
        else break
      } while (true)
      assert.deepEqual(answers, { answers: [{ id: 'first', selected: ['Read, then write'] }, { id: 'second', selected: [], custom: 'local' }] })
      session.append('tool/result', { turn: 1, step: 1, message: { id: 'question-result', role: 'tool', source: { kind: 'tool', callId: 'question-call' }, toolCallId: 'question-call', content: [{ type: 'text', text: 'Question answered' }], isError: false } }, { surfaceOp: 'append' })
      let planTool
      ctx.provide('tools', { register: tool => { planTool = tool } })
      ctx.provide('systemPrompt', { section() {}, context() {}, getSectionOrder: () => 0, getContextOrder: () => 0 })
      ctx.provide('sessionProjections', { register() {}, stateOf: () => ({ active: true }) })
      await ctx.plugin(PlanModeController, { section: 'Synthetic plan test' }).inertia
      const plan = '# Native review\n\nKeep exact identities.\n\n## Verification\n\nTest cancellation and stale answers.\n'
      session.append('tool/call', { turn: 1, step: 2, callId: 'plan-call', name: 'exit_plan_mode', arguments: JSON.stringify({ plan }) })
      assert.deepEqual(await planTool.execute({ plan }, { agent, callId: 'plan-call', signal: new AbortController().signal }), { approved: true })
      session.append('tool/result', { turn: 1, step: 2, message: { id: 'plan-result', role: 'tool', source: { kind: 'tool', callId: 'plan-call' }, toolCallId: 'plan-call', content: [{ type: 'text', text: 'Plan review completed' }], isError: false } }, { surfaceOp: 'append' })
      assert.equal(await ctx.approval.request({ agent, toolName: 'synthetic-test-only', callId: 'approval-call', reason: 'Synthetic request, no command executes' }), 'allowed-once')
      const finalText = '# Integration verified\n\n' + 'Structured answers returned through the native bridge without altering permission policy. '.repeat(4)
      session.append('assistant/message', { turn: 1, message: { id: 'final-message', role: 'assistant', content: [{ type: 'text', text: finalText }] } }, { surfaceOp: 'append' })
      session.append('turn/end', { turn: 1, reason: { kind: 'completed' } })
    } finally {
      await host.dispose()
      await ctx.fiber.dispose()
      clearInterval(keepAlive)
    }
    console.log(JSON.stringify({ roundtrip: true }))
    """#
}
