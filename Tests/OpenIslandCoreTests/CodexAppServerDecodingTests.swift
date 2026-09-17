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
}
