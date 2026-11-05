import Foundation
import Testing
@testable import OpenIslandCore

struct CodexDisplayMetadataTests {
    @Test
    func turnContextAddsDisplayMetadataWithoutChangingLifecycle() throws {
        var snapshot = CodexRolloutSnapshot(phase: .completed, isCompleted: true)
        CodexRolloutReducer.apply(line: #"{"type":"session_meta","payload":{"source":{"subAgent":{"thread_spawn":{"parent_thread_id":"parent"}}}}}"#, to: &snapshot)
        CodexRolloutReducer.apply(line: #"{"type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}"#, to: &snapshot)
        #expect(snapshot.phase == .completed)
        #expect(snapshot.isCompleted)
        #expect(snapshot.metadata.model == "gpt-test")
        #expect(snapshot.metadata.reasoningEffort == "high")
        #expect(snapshot.metadata.parentThreadID == "parent")
        let restored = try JSONDecoder().decode(CodexSessionMetadata.self, from: JSONEncoder().encode(snapshot.metadata))
        #expect(restored == snapshot.metadata)
    }

    @Test
    func modernThreadFieldsPreserveIdentityAndOptionalDisplayContext() throws {
        let json = #"{"id":"child","cwd":"/tmp","preview":"task","modelProvider":"openai","createdAt":1,"updatedAt":1,"ephemeral":false,"status":{"type":"active"},"source":"app-server","parentThreadId":"root","agentNickname":"Ada","agentRole":"reviewer","model":"gpt-test","reasoningEffort":"high"}"#
        let child = try JSONDecoder().decode(CodexThread.self, from: Data(json.utf8))
        #expect(child.isSubagent)
        #expect(!CodexLiveSessionPolicy.shouldShow(child))
        #expect(child.subagentParentID == "root")
        #expect(child.updatingActivityTimestamp(100).model == "gpt-test")
        #expect(child.updatingActivityTimestamp(100).reasoningEffort == "high")
        #expect(child.updatingActivityTimestamp(100).agentNickname == "Ada")
    }
}
