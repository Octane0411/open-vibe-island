import Foundation
import Testing
@testable import OpenIslandCore

struct CodexAppServerDecodingTests {
    @Test
    func codexThreadDecodesObjectSourceAsUnknown() throws {
        let json = Data(
            """
            {
              "id": "019e6cb5-46dc-7e11-ad95-e1df0de7cdb7",
              "cwd": "/Users/pojue/Documents/Codex",
              "name": "Investigate Open Island",
              "preview": "Looking at Codex app-server output.",
              "modelProvider": "openai",
              "createdAt": 1779940000000,
              "updatedAt": 1779940300000,
              "ephemeral": false,
              "path": "/Users/pojue/.codex/sessions/2026/05/28/rollout.jsonl",
              "status": {
                "type": "notLoaded"
              },
              "source": {
                "kind": "subagent",
                "parentThreadId": "019e6cb5-46dc-7e11-ad95-e1df0de7cdb7"
              },
              "turns": []
            }
            """.utf8
        )

        let thread = try JSONDecoder().decode(CodexThread.self, from: json)

        #expect(thread.source == .unknown)
    }

    @Test
    func serverInitiatedCommandApprovalRequestEmitsNotificationInsteadOfBeingTreatedAsResponse() throws {
        let client = CodexAppServerClient()
        let received = LockedCodexAppServerNotifications()
        client.onNotification = { received.append($0) }

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","id":41,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-1","reason":"needs shell","command":["git","status"],"cwd":"/tmp/project"}}

            """.utf8
        ))

        let notification = try #require(received.snapshot().first)
        guard case let .approvalRequested(request) = notification else {
            Issue.record("Expected approvalRequested notification, got \(notification)")
            return
        }

        #expect(request.requestID == 41)
        #expect(request.kind == .commandExecution)
        #expect(request.threadID == "thread-1")
        #expect(request.command == ["git", "status"])
        #expect(request.cwd == "/tmp/project")
    }

    @Test
    func resolvesCommandApprovalByWritingJsonRpcDecisionResponse() throws {
        let client = CodexAppServerClient()
        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting

        let request = CodexAppServerApprovalRequest(
            requestID: 42,
            kind: .commandExecution,
            threadID: "thread-1"
        )

        try client.resolveApprovalRequest(request, resolution: .allowOnce())
        pipe.fileHandleForWriting.closeFile()

        let line = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        let json = try #require(line?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])

        #expect(object["id"] as? Int == 42)
        #expect(result["decision"] as? String == "accept")
    }

    @Test
    func resolvesPermissionApprovalWithRequestedPermissionsSubset() throws {
        let client = CodexAppServerClient()
        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","id":43,"method":"item/permissions/requestApproval","params":{"threadId":"thread-1","itemId":"item-1","cwd":"/tmp/project","reason":"needs workspace","permissions":{"fileSystem":{"write":["/tmp/project"]},"network":{"enabled":true}}}}

            """.utf8
        ))

        let request = CodexAppServerApprovalRequest(
            requestID: 43,
            kind: .permissions,
            threadID: "thread-1",
            permissions: .object([
                "fileSystem": .object(["write": .array([.string("/tmp/project")])]),
                "network": .object(["enabled": .boolean(true)]),
            ])
        )

        try client.resolveApprovalRequest(request, resolution: .allowOnce())
        pipe.fileHandleForWriting.closeFile()

        let line = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        let json = try #require(line?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])
        let permissions = try #require(result["permissions"] as? [String: Any])

        #expect(object["id"] as? Int == 43)
        #expect(permissions["fileSystem"] != nil)
        #expect(permissions["network"] != nil)
    }

    @Test
    func readsAccountRateLimitsFromAppServerMainSnapshot() async throws {
        let client = CodexAppServerClient()
        client.requestTimeoutSeconds = 1
        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting

        let task = Task {
            try await client.readAccountRateLimits()
        }

        let requestLine = pipe.fileHandleForReading.availableData
        let requestObject = try #require(JSONSerialization.jsonObject(with: requestLine) as? [String: Any])
        let requestID = try #require(requestObject["id"] as? Int)
        #expect(requestObject["method"] as? String == "account/rateLimits/read")

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","id":\(requestID),"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":53,"windowDurationMins":300,"resetsAt":1780571047},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1781139840},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"pro","rateLimitReachedType":null},"rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1780588623},"secondary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":1781175423},"credits":null,"planType":"pro","rateLimitReachedType":null}}}}

            """.utf8
        ))

        let snapshot = try #require(await task.value)

        #expect(snapshot.sourceFilePath == "codex-app-server")
        #expect(snapshot.limitID == "codex")
        #expect(snapshot.planType == "pro")
        #expect(snapshot.windows.map(\.label) == ["5h", "7d"])
        #expect(snapshot.windows.map(\.roundedUsedPercentage) == [53, 10])
    }

    @Test
    func accountRateLimitsUpdatedNotificationEmitsUsageSnapshot() throws {
        let client = CodexAppServerClient()
        let received = LockedCodexAppServerNotifications()
        client.onNotification = { received.append($0) }

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":52,"windowDurationMins":300,"resetsAt":1780571047},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1781139840},"planType":"pro"}}}

            """.utf8
        ))

        let notification = try #require(received.snapshot().first)
        guard case let .accountRateLimitsUpdated(snapshot) = notification else {
            Issue.record("Expected accountRateLimitsUpdated notification, got \(notification)")
            return
        }

        #expect(snapshot.sourceFilePath == "codex-app-server-notification")
        #expect(snapshot.limitID == "codex")
        #expect(snapshot.windows.map(\.roundedUsedPercentage) == [52, 10])
    }

    @Test
    func itemStartedCommandExecutionNotificationEmitsToolActivity() throws {
        let client = CodexAppServerClient()
        let received = LockedCodexAppServerNotifications()
        client.onNotification = { received.append($0) }

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","method":"item/started","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"item-1","type":"commandExecution","command":["zsh","-lc","swift test --filter CodexSessionTrackingTests"],"cwd":"/tmp/project","status":"inProgress"}}}

            """.utf8
        ))

        let notification = try #require(received.snapshot().first)
        guard case let .itemStarted(activity) = notification else {
            Issue.record("Expected itemStarted notification, got \(notification)")
            return
        }

        #expect(activity.threadID == "thread-1")
        #expect(activity.toolName == "exec_command")
        #expect(activity.preview == "swift test --filter CodexSessionTrackingTests")
    }

    @Test
    func commandExecutionOutputDeltaEmitsToolActivityHeartbeat() throws {
        let client = CodexAppServerClient()
        let received = LockedCodexAppServerNotifications()
        client.onNotification = { received.append($0) }

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","method":"item/commandExecution/outputDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-1","delta":"Building for debugging...\\n[1/3] Compiling"}}

            """.utf8
        ))

        let notification = try #require(received.snapshot().first)
        guard case let .itemOutputDelta(activity) = notification else {
            Issue.record("Expected itemOutputDelta notification, got \(notification)")
            return
        }

        #expect(activity.threadID == "thread-1")
        #expect(activity.turnID == "turn-1")
        #expect(activity.itemID == "item-1")
        #expect(activity.toolName == "exec_command")
        #expect(activity.preview == "Building for debugging... [1/3] Compiling")
    }

    @Test
    func fileChangePatchUpdatedEmitsEditingActivity() throws {
        let client = CodexAppServerClient()
        let received = LockedCodexAppServerNotifications()
        client.onNotification = { received.append($0) }

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","method":"item/fileChange/patchUpdated","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-2","patch":"*** Begin Patch\\n*** Update File: Sources/OpenIslandApp/Views/IslandPanelView.swift\\n@@\\n-old\\n+new\\n*** End Patch"}}

            """.utf8
        ))

        let notification = try #require(received.snapshot().first)
        guard case let .itemPatchUpdated(activity) = notification else {
            Issue.record("Expected itemPatchUpdated notification, got \(notification)")
            return
        }

        #expect(activity.threadID == "thread-1")
        #expect(activity.turnID == "turn-1")
        #expect(activity.itemID == "item-2")
        #expect(activity.toolName == "apply_patch")
        #expect(activity.preview == "IslandPanelView.swift")
    }

    @Test
    func agentMessageDeltaEmitsAssistantDelta() throws {
        let client = CodexAppServerClient()
        let received = LockedCodexAppServerNotifications()
        client.onNotification = { received.append($0) }

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"item-3","delta":"正在整理 reducer 规则"}}

            """.utf8
        ))

        let notification = try #require(received.snapshot().first)
        guard case let .agentMessageDelta(delta) = notification else {
            Issue.record("Expected agentMessageDelta notification, got \(notification)")
            return
        }

        #expect(delta.threadID == "thread-1")
        #expect(delta.turnID == "turn-1")
        #expect(delta.itemID == "item-3")
        #expect(delta.text == "正在整理 reducer 规则")
    }

    @Test
    func rawResponseItemCompletedFunctionCallEmitsToolActivity() throws {
        let client = CodexAppServerClient()
        let received = LockedCodexAppServerNotifications()
        client.onNotification = { received.append($0) }

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","method":"rawResponseItem/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"call-1","type":"function_call","name":"exec_command","arguments":{"cmd":"swift test --filter CodexSessionTrackingTests"}}}}

            """.utf8
        ))

        let notification = try #require(received.snapshot().first)
        guard case let .rawResponseItemCompleted(item) = notification else {
            Issue.record("Expected rawResponseItemCompleted notification, got \(notification)")
            return
        }

        #expect(item.threadID == "thread-1")
        #expect(item.turnID == "turn-1")
        #expect(item.itemID == "call-1")
        #expect(item.toolName == "exec_command")
        #expect(item.preview == "swift test --filter CodexSessionTrackingTests")
        #expect(item.assistantText == nil)
    }

    @Test
    func rawResponseItemCompletedAssistantMessageEmitsAssistantText() throws {
        let client = CodexAppServerClient()
        let received = LockedCodexAppServerNotifications()
        client.onNotification = { received.append($0) }

        client.handleIncomingData(Data(
            """
            {"jsonrpc":"2.0","method":"rawResponseItem/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"msg-1","type":"message","role":"assistant","content":[{"type":"output_text","text":"已经完成 reducer 对齐。"}]}}}

            """.utf8
        ))

        let notification = try #require(received.snapshot().first)
        guard case let .rawResponseItemCompleted(item) = notification else {
            Issue.record("Expected rawResponseItemCompleted notification, got \(notification)")
            return
        }

        #expect(item.threadID == "thread-1")
        #expect(item.turnID == "turn-1")
        #expect(item.itemID == "msg-1")
        #expect(item.toolName == nil)
        #expect(item.preview == nil)
        #expect(item.assistantText == "已经完成 reducer 对齐。")
    }
}

private final class LockedCodexAppServerNotifications: @unchecked Sendable {
    private let lock = NSLock()
    private var notifications: [CodexAppServerNotification] = []

    func append(_ notification: CodexAppServerNotification) {
        lock.lock()
        notifications.append(notification)
        lock.unlock()
    }

    func snapshot() -> [CodexAppServerNotification] {
        lock.lock()
        let copy = notifications
        lock.unlock()
        return copy
    }
}
