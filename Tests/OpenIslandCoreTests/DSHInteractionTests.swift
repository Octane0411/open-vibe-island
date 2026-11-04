import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

@Suite(.serialized)
struct DSHInteractionTests {
    @Test
    func boundaryPreservesNativeIdentityPlanDetailAndLosslessSelections() throws {
        let id = UUID().uuidString.lowercased()
        let wire = Data("""
        {"hook_event_name":"Heartbeat","session_id":"chat","cwd":"/tmp/project","interaction":{
          "request_id":"\(id)","kind":"plan","status":"pending","call_id":"tool-call",
          "questions":[{"id":"plan-review","question":"Review this plan","detail":"# Plan\\n\\nFull markdown content","header":"Plan","multiSelect":false,
          "options":[{"label":"Approve"},{"label":"Keep planning"},{"label":"Other response"}],
          "intent":{"kind":"plan-review","approve":"Approve","callId":"tool-call"}}]}}
        """.utf8)
        let hook = try JSONDecoder().decode(DSHHookPayload.self, from: wire)
        let interaction = try #require(hook.interaction)
        let prompt = try #require(interaction.questionPrompt)
        #expect(prompt.id == UUID(uuidString: id))
        #expect(prompt.questions[0].nativeID == "plan-review")
        #expect(prompt.questions[0].detail == "# Plan\n\nFull markdown content")
        #expect(prompt.questions[0].options.last?.allowsFreeform == true)
        #expect(prompt.questions[0].options.last?.label != "Other response")
        #expect(interaction.questions?[0].intent?.callId == "tool-call")
        #expect(interaction.permissionRequest == nil)
        #expect(try interaction.nativeAnswers(for: QuestionPromptResponse(structuredAnswers: [
            "plan-review": StructuredQuestionAnswer(selectedOptions: ["Keep planning"], customText: "Add tests first")
        ])) == [DSHInteractionAnswer(id: "plan-review", selected: ["Keep planning"], custom: "Add tests first")])

        var multi = interaction
        multi.kind = .question
        multi.questions = [
            DSHInteractionQuestion(id: "exact-id-1", question: "Same text", options: [
                DSHInteractionOption(label: "A, B"), DSHInteractionOption(label: "C")
            ], multiSelect: true),
            DSHInteractionQuestion(id: "exact-id-2", question: "Same text")
        ]
        let answers = try multi.nativeAnswers(for: QuestionPromptResponse(structuredAnswers: [
            "exact-id-1": StructuredQuestionAnswer(selectedOptions: ["A, B", "C"]),
            "exact-id-2": StructuredQuestionAnswer(customText: "Typed answer")
        ]))
        #expect(answers.map(\.id) == ["exact-id-1", "exact-id-2"])
        #expect(answers[0].selected == ["A, B", "C"])
        #expect(throws: DSHInteractionError.invalidResponse) { try multi.nativeAnswers(for: QuestionPromptResponse(answer: "Ambiguous")) }
        #expect(throws: DSHInteractionError.invalidResponse) {
            try interaction.nativeAnswers(for: QuestionPromptResponse(structuredAnswers: [
                "plan-review": StructuredQuestionAnswer(selectedOptions: ["Approve", "Keep planning"])
            ]))
        }
        multi.questions?[1].id = "exact-id-1"
        #expect(multi.questionPrompt == nil)
        multi.requestID = "not-a-uuid"
        #expect(multi.presentationID == nil)
    }

    @Test
    func unconfirmedCachedRowsCannotAdmitPrivateInteractions() async throws {
        let peer = try InteractionPeer()
        defer { peer.stop() }
        let socket = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socket)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: socket)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { timeout.cancel() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()
        let commands = BridgeCommandClient(socketURL: socket)
        _ = try commands.send(.processDSHHook(peer.hook(.sessionStart, sessionID: "anchor")))
        _ = try #require(try await iterator.next())
        try peer.waitForSubscription()
        let cached = AgentSession(id: "unconfirmed", title: "DSH", tool: .dsh, origin: .live, phase: .running, summary: "Old cache", updatedAt: .now, jumpTarget: peer.hook(.heartbeat, sessionID: "unconfirmed").defaultJumpTarget)
        server.updateStateSnapshot(SessionState(sessions: [cached]))
        let request = DSHInteraction(requestID: UUID().uuidString.lowercased(), kind: .question, status: .pending, questions: [DSHInteractionQuestion(id: "one", question: "Synthetic?", options: [DSHInteractionOption(label: "A")])])
        try peer.publish(sessionID: cached.id, interaction: request)
        _ = try commands.send(.processDSHHook(peer.hook(.sessionStart, sessionID: "barrier")))
        guard case let .sessionStarted(barrier) = try #require(try await iterator.next()) else {
            Issue.record("An unconfirmed cached session admitted an actionable event")
            return
        }
        #expect(barrier.sessionID == "barrier")
        _ = try commands.send(.processDSHHook(peer.hook(.sessionStart, sessionID: cached.id)))
        guard case let .sessionStarted(root) = try #require(try await iterator.next()),
              case let .questionAsked(question) = try #require(try await iterator.next()) else {
            Issue.record("A proven root did not recover its buffered request")
            return
        }
        #expect(root.piMetadata?.isSubagent == false)
        #expect(question.prompt.id == request.presentationID)
    }

    @Test
    func registrationRacesAndTerminalLifecycleReleaseOwnership() async throws {
        let peer = try InteractionPeer()
        defer { peer.stop() }
        let bridgeURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: bridgeURL)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: bridgeURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { deadline.cancel() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()
        let commands = BridgeCommandClient(socketURL: bridgeURL)
        _ = try commands.send(.processDSHHook(peer.hook(.sessionStart, sessionID: "anchor")))
        _ = try #require(try await iterator.next())
        try peer.waitForSubscription()
        let id = UUID()
        let request = DSHInteraction(requestID: id.uuidString.lowercased(), kind: .question, status: .pending,
                                     questions: [DSHInteractionQuestion(id: "native", question: "Explain")])
        try peer.publish(sessionID: "new-session", interaction: request)
        _ = try commands.send(.processDSHHook(peer.hook(.sessionStart, sessionID: "new-session")))
        guard case .sessionStarted = try #require(try await iterator.next()),
              case let .questionAsked(question) = try #require(try await iterator.next()) else {
            Issue.record("Buffered request did not follow session registration")
            return
        }
        #expect(question.prompt.id == id)
        _ = try commands.send(.processDSHHook(peer.hook(.sessionEnd, sessionID: "new-session")))
        guard case let .sessionCompleted(completed) = try #require(try await iterator.next()) else {
            Issue.record("Expected terminal lifecycle event")
            return
        }
        #expect(completed.isSessionEnd == true)
        try peer.waitForResponse()
        #expect(peer.responses.last?.requestID == request.requestID)
        #expect(peer.responses.last?.decision == "delegate")
        await #expect(throws: DSHInteractionError.staleRequest) {
            try await server.answerDSHQuestion(sessionID: "new-session", requestID: id, response: QuestionPromptResponse(answer: "Late"))
        }
        // Never leave a host-owned request invisible if no matching lifecycle arrives.
        var orphan = request
        orphan.requestID = UUID().uuidString.lowercased()
        try peer.publish(sessionID: "never-registered", interaction: orphan)
        try peer.waitForResponse()
        #expect(peer.responses.last?.requestID == orphan.requestID)
        #expect(peer.responses.last?.decision == "delegate")
        #expect(peer.responses.allSatisfy { $0.answers == nil && $0.decision == "delegate" })
        server.stop()
        try peer.waitForObserverDisconnect()
    }

    @Test
    func typedResultsRetainMarkdownAndNonSuccessTurnReasons() async throws {
        let bridgeURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: bridgeURL)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: bridgeURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { deadline.cancel() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()
        let commands = BridgeCommandClient(socketURL: bridgeURL)
        _ = try commands.send(.processDSHHook(DSHHookPayload(hookEventName: .sessionStart, sessionID: "results", cwd: "/tmp/project")))
        _ = try #require(try await iterator.next())
        let wire = Data("""
        {"hook_event_name":"PostToolUse","session_id":"results","cwd":"/tmp/project","turn_id":3,"is_subagent":false,
        "interaction_result":{"kind":"plan","outcome":"declined","call_id":"plan-call"}}
        """.utf8)
        let result = try JSONDecoder().decode(DSHHookPayload.self, from: wire)
        #expect(result.interactionResult?.outcome == .declined)
        #expect(result.turnID == 3)
        _ = try commands.send(.processDSHHook(result))
        guard case let .activityUpdated(activity) = try #require(try await iterator.next()) else { Issue.record("Expected typed interaction result")
            return
        }
        #expect(activity.summary == result.postToolUseSummary)
        let markdown = "# Complete result\n\n" + String(repeating: "- Full assistant markdown retained.\n", count: 100)
        let completion = DSHHookPayload(hookEventName: .stop, sessionID: "results", cwd: "/tmp/project", lastAssistantMessage: markdown,
                                        turnID: 3, turnOutcome: "completed", interactionResult: result.interactionResult)
        _ = try commands.send(.processDSHHook(completion))
        guard case let .piSessionMetadataUpdated(metadata) = try #require(try await iterator.next()),
              case let .sessionCompleted(completed) = try #require(try await iterator.next()) else { Issue.record("Expected full result and completion")
            return
        }
        #expect(metadata.piMetadata.lastAssistantMessage == markdown)
        #expect(completed.summary == completion.completionSummary)
        for reason in ["error", "aborted", "blocked", "max-tokens", "interrupted", "forked", "extension-reason"] {
            let hook = DSHHookPayload(hookEventName: .stop, sessionID: "results", cwd: "/tmp/project", turnID: 4, turnOutcome: reason)
            _ = try commands.send(.processDSHHook(hook))
            guard case let .piSessionMetadataUpdated(update) = try #require(try await iterator.next()),
                  case let .sessionCompleted(end) = try #require(try await iterator.next()) else { Issue.record("Expected non-success outcome metadata")
                return
            }
            #expect(update.piMetadata.lastAssistantMessage == hook.completionSummary)
            #expect(update.piMetadata.lastAssistantMessage != markdown)
            #expect(end.summary == hook.completionSummary)
            #expect(end.isInterrupt == (["aborted", "interrupted"].contains(reason) ? true : nil))
        }
    }

    @Test
    func turnScopedStopsPreserveNewerCardsAndCompleteBeforeResolvedFrames() async throws {
        let peer = try InteractionPeer()
        defer { peer.stop() }
        let bridgeURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: bridgeURL)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: bridgeURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { deadline.cancel() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()
        let commands = BridgeCommandClient(socketURL: bridgeURL)
        _ = try commands.send(.processDSHHook(peer.hook(.sessionStart, sessionID: "chat")))
        _ = try #require(try await iterator.next())
        try peer.waitForSubscription()
        var first = DSHInteraction(requestID: UUID().uuidString.lowercased(), kind: .question, status: .pending,
                                   questions: [DSHInteractionQuestion(id: "first", question: "First")], turnID: 3)
        var newer = DSHInteraction(requestID: UUID().uuidString.lowercased(), kind: .question, status: .pending,
                                   questions: [DSHInteractionQuestion(id: "newer", question: "Newer")], turnID: 4)
        try peer.publish(sessionID: "chat", interaction: first)
        _ = try #require(try await iterator.next())
        try peer.publish(sessionID: "chat", interaction: newer)
        var stop = peer.hook(.stop, sessionID: "chat")
        stop.turnID = 2
        _ = try commands.send(.processDSHHook(stop))
        _ = try commands.send(.processDSHHook(peer.hook(.heartbeat, sessionID: "chat")))
        guard case .sessionHeartbeat = try #require(try await iterator.next()) else { Issue.record("Old turn Stop changed pending state")
            return
        }
        stop.turnID = 3
        _ = try commands.send(.processDSHHook(stop))
        guard case .actionableStateResolved = try #require(try await iterator.next()),
              case let .questionAsked(question) = try #require(try await iterator.next()) else { Issue.record("Expected only older turn to resolve")
            return
        }
        #expect(question.prompt.id == newer.presentationID)
        first.status = .resolved
        try peer.publish(sessionID: "chat", interaction: first)
        stop.turnID = 5
        _ = try commands.send(.processDSHHook(stop))
        guard case .sessionCompleted = try #require(try await iterator.next()) else { Issue.record("Current turn completion was lost before its resolved frame")
            return
        }
        newer.status = .resolved
        try peer.publish(sessionID: "chat", interaction: newer)
        _ = try commands.send(.processDSHHook(peer.hook(.heartbeat, sessionID: "chat")))
        guard case .sessionHeartbeat = try #require(try await iterator.next()) else { Issue.record("Late resolved frame changed completed state")
            return
        }
        #expect(peer.responses.isEmpty)
        await #expect(throws: DSHInteractionError.staleRequest) {
            try await server.answerDSHQuestion(sessionID: "chat", requestID: try #require(newer.presentationID), response: QuestionPromptResponse(answer: "Late"))
        }
    }

    @Test(arguments: [false, true])
    func rejectedDelegationRevokesOnlyItsObserverGeneration(delayedFailure: Bool) async throws {
        let peer = try InteractionPeer()
        defer { peer.stop() }
        let bridgeURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: bridgeURL)
        try server.start()
        defer { server.stop() }
        let observer = LocalBridgeClient(socketURL: bridgeURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { deadline.cancel() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()
        let commands = BridgeCommandClient(socketURL: bridgeURL)
        _ = try commands.send(.processDSHHook(peer.hook(.sessionStart, sessionID: "chat")))
        _ = try #require(try await iterator.next())
        try peer.waitForSubscription()
        let oldObserver = try #require(peer.observerID)
        let firstID = UUID()
        var request = DSHInteraction(requestID: firstID.uuidString.lowercased(), kind: .question, status: .pending,
                                     questions: [DSHInteractionQuestion(id: "native", question: "Explain")])
        try peer.publish(sessionID: "chat", interaction: request)
        guard case .questionAsked = try #require(try await iterator.next()) else { Issue.record("Expected visible request")
            return
        }
        let queuedID = UUID()
        request.requestID = queuedID.uuidString.lowercased()
        try peer.publish(sessionID: "chat", interaction: request)
        peer.acknowledgement = false
        peer.holdNextResponse = delayedFailure
        request.requestID = UUID().uuidString.lowercased()
        request.questions?.append(DSHInteractionQuestion(id: "native", question: "Duplicate ID"))
        try peer.publish(sessionID: "chat", interaction: request)
        try peer.waitForResponse()
        #expect(peer.responses.last?.decision == "delegate")
        if delayedFailure { peer.disconnectObserver() }
        try peer.waitForObserverDisconnect()
        guard case .actionableStateResolved = try #require(try await iterator.next()) else {
            Issue.record("Failed delegation must clear visible and queued requests")
            return
        }
        for id in [firstID, queuedID] {
            await #expect(throws: DSHInteractionError.staleRequest) {
                try await server.answerDSHQuestion(sessionID: "chat", requestID: id, response: QuestionPromptResponse(answer: "Stale"))
            }
        }
        if delayedFailure {
            _ = try commands.send(.processDSHHook(peer.hook(.heartbeat, sessionID: "chat")))
            guard case .sessionHeartbeat = try #require(try await iterator.next()) else { Issue.record("Expected reconnect heartbeat")
                return
            }
            try peer.waitForSubscription()
            let newObserver = try #require(peer.observerID)
            #expect(newObserver != oldObserver)
            let newID = UUID()
            request = DSHInteraction(requestID: newID.uuidString.lowercased(), kind: .question, status: .pending,
                                     questions: [DSHInteractionQuestion(id: "new-native", question: "New generation")])
            try peer.publish(sessionID: "chat", interaction: request)
            guard case .questionAsked = try #require(try await iterator.next()) else { Issue.record("Expected new generation request")
                return
            }
            peer.acknowledgement = true
            peer.releaseDelayedResponse()
            // Allow the deliberately delayed old failure to reach the bridge queue.
            try await Task.sleep(for: .milliseconds(100))
            try await server.answerDSHQuestion(sessionID: "chat", requestID: newID, response: QuestionPromptResponse(answer: "Explicit new answer"))
            #expect(peer.responses.last?.observerID == newObserver)
            #expect(peer.responses.last?.requestID == request.requestID)
        }
    }

    @Test
    func exactResponsesQueueResolutionAndLeaseCleanup() async throws {
        let peer = try InteractionPeer()
        defer { peer.stop() }
        let bridgeURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: bridgeURL)
        try server.start()
        defer { server.stop() }
        // The test sends lifecycle commands through the real public bridge interface.
        let observer = LocalBridgeClient(socketURL: bridgeURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { observer.disconnect() }
        }
        defer { deadline.cancel() }
        try await observer.send(.registerClient(role: .observer))
        var iterator = stream.makeAsyncIterator()
        let commandClient = BridgeCommandClient(socketURL: bridgeURL)
        for sessionID in ["one", "two"] {
            _ = try commandClient.send(.processDSHHook(peer.hook(.sessionStart, sessionID: sessionID)))
            guard case .sessionStarted = try #require(try await iterator.next()) else { Issue.record("Expected lifecycle registration")
                return
            }
        }
        try peer.waitForSubscription()
        let questionID = UUID()
        let approvalID = UUID()
        let question = DSHInteraction(
            requestID: questionID.uuidString.lowercased(), kind: .question, status: .pending,
            questions: [DSHInteractionQuestion(id: "native-q", question: "Choose", options: [DSHInteractionOption(label: "A, B")])]
        )
        try peer.publish(sessionID: "one", interaction: question)
        var state = SessionState(sessions: [AgentSession(id: "one", title: "DSH", tool: .dsh, phase: .running, summary: "", updatedAt: .now)])
        let asked = try #require(try await iterator.next())
        state.apply(asked)
        #expect(state.session(id: "one")?.questionPrompt?.id == questionID)
        let approval = DSHInteraction(requestID: approvalID.uuidString.lowercased(), kind: .approval, status: .pending, toolName: "bash", reason: "Run tests")
        try peer.publish(sessionID: "one", interaction: approval)
        // An old turn's FIFO Stop can arrive after a new pending stream frame.
        _ = try commandClient.send(.processDSHHook(peer.hook(.stop, sessionID: "one")))
        _ = try commandClient.send(.answerQuestion(sessionID: "one", response: QuestionPromptResponse(answer: "must not route")))
        _ = try commandClient.send(.resolvePermission(sessionID: "one", resolution: .allowOnce()))
        await #expect(throws: DSHInteractionError.staleRequest) {
            try await server.answerDSHQuestion(sessionID: "two", requestID: questionID, response: QuestionPromptResponse(answer: "Wrong session"))
        }
        await #expect(throws: DSHInteractionError.staleRequest) {
            try await server.resolveDSHPermission(sessionID: "one", requestID: approvalID, resolution: .allowOnce())
        }
        #expect(peer.responses.isEmpty)
        peer.acknowledgement = false
        await #expect(throws: DSHInteractionError.staleRequest) {
            try await server.answerDSHQuestion(sessionID: "one", requestID: questionID, response: QuestionPromptResponse(answer: "Retryable"))
        }
        peer.acknowledgement = true
        try await server.answerDSHQuestion(sessionID: "one", requestID: questionID, response: QuestionPromptResponse(structuredAnswers: [
            "native-q": StructuredQuestionAnswer(selectedOptions: ["A, B"], customText: "Keep comma intact")
        ]))
        let reply = try #require(peer.responses.last)
        #expect(reply.sessionID == "one")
        #expect(reply.requestID == question.requestID)
        #expect(reply.observerID == peer.observerID)
        #expect(reply.answers == [DSHInteractionAnswer(id: "native-q", selected: ["A, B"], custom: "Keep comma intact")])
        #expect(reply.decision == nil)
        // Ack and unrelated resolutions must not clear this card or expose the queued approval.
        var resolved = question
        resolved.status = .resolved
        try peer.publish(sessionID: "two", interaction: resolved)
        _ = try commandClient.send(.processDSHHook(peer.hook(.heartbeat, sessionID: "one")))
        let heartbeat = try #require(try await iterator.next())
        guard case .sessionHeartbeat = heartbeat else { Issue.record("A generic command, ack, or unrelated resolution changed the card")
            return
        }
        state.apply(heartbeat)
        #expect(state.session(id: "one")?.questionPrompt?.id == questionID)
        try peer.publish(sessionID: "one", interaction: resolved)
        state.apply(try #require(try await iterator.next()))
        #expect(state.session(id: "one")?.questionPrompt == nil)
        let permission = try #require(try await iterator.next())
        state.apply(permission)
        #expect(state.session(id: "one")?.permissionRequest?.id == approvalID)
        await #expect(throws: DSHInteractionError.staleRequest) {
            try await server.answerDSHQuestion(sessionID: "one", requestID: questionID, response: QuestionPromptResponse(answer: "Late"))
        }
        try await server.resolveDSHPermission(sessionID: "one", requestID: approvalID, resolution: .deny())
        #expect(peer.responses.last?.decision == "rejected")
        peer.disconnectObserver()
        state.apply(try #require(try await iterator.next()))
        #expect(state.session(id: "one")?.permissionRequest == nil)
        await #expect(throws: DSHInteractionError.staleRequest) {
            try await server.resolveDSHPermission(sessionID: "one", requestID: approvalID, resolution: .allowOnce())
        }
    }
}

private struct InteractionReply: Decodable, Sendable {
    var type: String
    var observerID: String?
    var sessionID: String?
    var requestID: String?
    var answers: [DSHInteractionAnswer]?
    var decision: String?
    enum CodingKeys: String, CodingKey {
        case type, answers, decision
        case observerID = "observer_id"
        case sessionID = "session_id"
        case requestID = "request_id"
    }
}

private final class InteractionPeer: @unchecked Sendable {
    let directory: URL
    let socketURL: URL
    private let listener: Int32
    private let lock = NSLock()
    private let workers = DispatchGroup()
    private let ready = DispatchSemaphore(value: 0)
    private let pong = DispatchSemaphore(value: 0)
    private let responded = DispatchSemaphore(value: 0)
    private let observerDisconnected = DispatchSemaphore(value: 0)
    private let delayedResponse = DispatchSemaphore(value: 0)
    private var stopped = false
    private var connections: Set<Int32> = []
    private var observer: Int32?
    private var subscriptionID: String?
    private var replies: [InteractionReply] = []
    private var acceptsResponse = true
    private var delayNextResponse = false

    var holdNextResponse: Bool {
        get { lock.withLock { delayNextResponse } }
        set { lock.withLock { delayNextResponse = newValue } }
    }

    func releaseDelayedResponse() { delayedResponse.signal() }

    var observerID: String? { lock.withLock { subscriptionID } }
    var responses: [InteractionReply] { lock.withLock { replies } }
    var acknowledgement: Bool {
        get { lock.withLock { acceptsResponse } }
        set { lock.withLock { acceptsResponse = newValue } }
    }

    init() throws {
        directory = URL(fileURLWithPath: "/tmp/oi-dsh-focus-\(UUID().uuidString.prefix(12))", isDirectory: true)
        socketURL = directory.appendingPathComponent("focus.sock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0,
              try withUnixSocketAddress(path: socketURL.path, { bind(listener, $0, $1) }) == 0,
              chmod(socketURL.path, 0o600) == 0, listen(listener, 16) == 0 else { throw DSHInteractionError.unavailable }
        workers.enter()
        DispatchQueue.global().async { [self] in
            defer { workers.leave() }
            while !lock.withLock({ stopped }) {
                var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                guard poll(&descriptor, 1, 100) > 0 else { continue }
                let fd = accept(listener, nil, nil)
                guard fd >= 0 else { continue }
                lock.withLock { _ = connections.insert(fd) }
                workers.enter()
                DispatchQueue.global().async { [self] in
                    defer {
                        lock.withLock { _ = connections.remove(fd) }
                        close(fd)
                        workers.leave()
                    }
                    try? disableSocketSigPipe(fd)
                    serve(fd)
                }
            }
        }
    }

    func hook(_ event: RuntimeHookEventName, sessionID: String) -> DSHHookPayload {
        DSHHookPayload(hookEventName: event, sessionID: sessionID, cwd: "/tmp/project", webOrigin: "http://127.0.0.1:3080/", webFocusSocket: socketURL.path)
    }

    func waitForSubscription() throws {
        guard ready.wait(timeout: .now() + 2) == .success else { throw DSHInteractionError.timedOut }
    }

    func waitForObserverDisconnect() throws {
        guard observerDisconnected.wait(timeout: .now() + 2) == .success else { throw DSHInteractionError.timedOut }
    }

    func waitForResponse() throws {
        guard responded.wait(timeout: .now() + 3) == .success else { throw DSHInteractionError.timedOut }
    }

    func publish(sessionID: String, interaction: DSHInteraction) throws {
        let connection = lock.withLock { (observer, subscriptionID) }
        guard let fd = connection.0, let id = connection.1 else { throw DSHInteractionError.unavailable }
        var data = try JSONEncoder().encode(DSHInteractionFrame(type: "interaction", sessionID: sessionID, interaction: interaction)) + Data([10])
        data += try JSONEncoder().encode(DSHInteractionFrame(type: "interaction_ping", observerID: id, nonce: UUID().uuidString)) + Data([10])
        try writeAll(data, to: fd)
        guard pong.wait(timeout: .now() + 2) == .success else { throw DSHInteractionError.timedOut }
    }

    func disconnectObserver() {
        lock.withLock { if let observer { _ = shutdown(observer, SHUT_RDWR) } }
    }

    private func serve(_ fd: Int32) {
        var buffer = Data()
        guard let data = readLine(fd, buffer: &buffer),
              let request = try? JSONDecoder().decode(InteractionReply.self, from: data) else { return }
        if request.type == "observe_interactions", let id = request.observerID {
            defer { observerDisconnected.signal() }
            lock.withLock { observer = fd
                subscriptionID = id
            }
            let frame = DSHInteractionFrame(type: "interaction_ready", protocolVersion: 1, observerID: id)
            guard let data = try? JSONEncoder().encode(frame) else { return }
            try? writeAll(data + Data([10]), to: fd)
            ready.signal()
            while let line = readLine(fd, buffer: &buffer) {
                if let frame = try? JSONDecoder().decode(DSHInteractionFrame.self, from: line), frame.type == "interaction_pong" {
                    pong.signal()
                }
            }
        } else if request.type == "respond_interaction" {
            let behavior = lock.withLock { replies.append(request)
                let hold = delayNextResponse
                delayNextResponse = false
                return (acceptsResponse, hold)
            }
            responded.signal()
            if behavior.1 { _ = delayedResponse.wait(timeout: .now() + 3) }
            let response = behavior.0 ? "{\"ok\":true}\n" : "{\"ok\":false,\"error\":\"stale-request\"}\n"
            try? writeAll(Data(response.utf8), to: fd)
        }
    }

    private func readLine(_ fd: Int32, buffer: inout Data) -> Data? {
        while !lock.withLock({ stopped }) {
            if let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return line
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 100) > 0 else { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = read(fd, &bytes, bytes.count)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: bytes.prefix(count))
        }
        return nil
    }

    func stop() {
        delayedResponse.signal()
        lock.withLock {
            stopped = true
            for fd in connections { _ = shutdown(fd, SHUT_RDWR) }
        }
        guard workers.wait(timeout: .now() + 3) == .success else { Issue.record("Interaction peer did not stop")
            return
        }
        close(listener)
        precondition(directory.path.hasPrefix("/tmp/oi-dsh-focus-"))
        try? FileManager.default.removeItem(at: directory)
    }
}
