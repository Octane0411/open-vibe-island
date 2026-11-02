import Foundation
import Testing
@testable import OpenIslandCore

struct CodexAppServerLifecycleTests {
    @Test
    func desktopExecutableResolvesBothBundleLayoutsWithoutUsingPathCLI() {
        let bundle = URL(fileURLWithPath: "/Applications/Renamed Desktop.app")
        let nested = bundle.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        let legacy = bundle.appendingPathComponent("Contents/Resources/codex")
        #expect(CodexAppServerClient.executableURL(in: bundle, isExecutable: { $0 == nested.path }) == nested)
        #expect(CodexAppServerClient.executableURL(in: bundle, isExecutable: { $0 == legacy.path }) == legacy)
        #expect(CodexAppServerClient.executableURL(in: bundle, isExecutable: { _ in true }) == nested)
        #expect(CodexAppServerClient.executableURL(in: bundle, isExecutable: { _ in false }) == nil)
    }

    @Test
    func loadedThreadListUsesIDsAndPagination() throws {
        let page = try CodexAppServerClient.decodeLoadedThreadListResponse(
            Data(#"{"data":["thread-a","thread-b"],"nextCursor":"next"}"#.utf8)
        )
        #expect(page.ids == ["thread-a", "thread-b"])
        #expect(page.threads.isEmpty)
        #expect(page.nextCursor == "next")
        #expect(throws: DecodingError.self) {
            try CodexAppServerClient.decodeLoadedThreadListResponse(Data(#"{"unexpected":[]}"#.utf8))
        }
    }

    @Test
    func loadedThreadsAreReadWithoutHydratingTurnHistory() async throws {
        let client = CodexAppServerClient()
        let pipe = Pipe()
        client.stdin = pipe.fileHandleForWriting
        client.requestTimeoutSeconds = 2
        defer {
            client.stop()
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        let server = Task.detached { () throws -> [String] in
            var methods: [String] = []
            for _ in 0..<3 {
                let data = pipe.fileHandleForReading.availableData
                let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let method = try #require(request["method"] as? String)
                methods.append(method)
                let params = try #require(request["params"] as? [String: Any])
                let result: [String: Any]
                if method == "thread/read" {
                    #expect(params["threadId"] as? String == "desktop-session")
                    #expect(params["includeTurns"] as? Bool == false)
                    result = ["thread": ["id": "desktop-session", "cwd": "/tmp/project", "preview": "Fix detection", "modelProvider": "openai", "createdAt": 1, "updatedAt": 2, "ephemeral": false, "status": ["type": "idle"], "source": "vscode"]]
                } else if methods.count == 1 {
                    result = ["data": ["desktop-session"], "nextCursor": "next"]
                } else {
                    #expect(params["cursor"] as? String == "next")
                    result = ["data": [], "nextCursor": NSNull()]
                }
                var response = try JSONSerialization.data(withJSONObject: ["id": try #require(request["id"] as? Int), "result": result])
                response.append(10)
                client.handleIncomingData(response)
            }
            return methods
        }
        let threads = try await client.listLoadedThreads()
        #expect(threads.map(\.id) == ["desktop-session"])
        #expect(try await server.value == ["thread/loaded/list", "thread/read", "thread/loaded/list"])
    }

    @Test(arguments: ["data", "threads"])
    func threadListDecodesCurrentAndLegacyResponseKeys(responseKey: String) throws {
        let response = """
        {
          "\(responseKey)": [{
            "id": "desktop-session",
            "cwd": "/Users/u/project",
            "preview": "Fix desktop detection",
            "modelProvider": "openai",
            "createdAt": 1,
            "updatedAt": 2,
            "ephemeral": false,
            "status": { "type": "idle" },
            "source": "vscode"
          }]
        }
        """

        let threads = try CodexAppServerClient.decodeThreadListResponse(Data(response.utf8))

        #expect(threads.count == 1)
        #expect(threads.first?.id == "desktop-session")
        #expect(threads.first?.source == .vscode)
    }

    @Test
    func outputHandlersUnregisterAtEndOfFile() async throws {
        let client = CodexAppServerClient()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        defer {
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
        }

        client.configureOutputHandlers(
            stdout: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading
        )

        try stdoutPipe.fileHandleForWriting.close()
        try stderrPipe.fileHandleForWriting.close()

        #expect(await waitUntil {
            stdoutPipe.fileHandleForReading.readabilityHandler == nil
                && stderrPipe.fileHandleForReading.readabilityHandler == nil
        })
    }

    @Test
    func stopUnregistersOutputHandlers() throws {
        let client = CodexAppServerClient()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        defer {
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
        }

        client.configureOutputHandlers(
            stdout: stdoutPipe.fileHandleForReading,
            stderr: stderrPipe.fileHandleForReading
        )

        client.stop()

        #expect(stdoutPipe.fileHandleForReading.readabilityHandler == nil)
        #expect(stderrPipe.fileHandleForReading.readabilityHandler == nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
