import Foundation
import Testing
@testable import OpenIslandCore

struct ClaudeSessionMetadataPIDTests {
    @Test
    func claudeSessionMetadataCarriesAgentPIDThroughCodec() throws {
        let metadata = ClaudeSessionMetadata(
            transcriptPath: "/tmp/claude.jsonl",
            agentPID: 4_242
        )

        let encoded = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(ClaudeSessionMetadata.self, from: encoded)

        #expect(decoded.agentPID == 4_242)
        #expect(decoded.transcriptPath == "/tmp/claude.jsonl")
    }

    @Test
    func claudeSessionMetadataWithOnlyAgentPIDIsNotEmpty() {
        let metadata = ClaudeSessionMetadata(agentPID: 42)

        #expect(metadata.isEmpty == false)
    }

    @Test
    func claudeSessionMetadataEmptyIsTrueWhenAllNil() {
        let metadata = ClaudeSessionMetadata()

        #expect(metadata.isEmpty == true)
    }

    @Test
    func defaultClaudeMetadataIncludesAgentPIDFromPayload() {
        let payload = ClaudeHookPayload(
            cwd: "/tmp/demo",
            hookEventName: .sessionStart,
            sessionID: "s1",
            agentPID: 777
        )

        let metadata = payload.defaultClaudeMetadata

        #expect(metadata.agentPID == 777)
    }
}
