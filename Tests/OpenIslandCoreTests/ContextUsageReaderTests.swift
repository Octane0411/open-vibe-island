import Foundation
import Testing
@testable import OpenIslandCore

struct ContextUsageReaderTests {
    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    @Test
    func parsesLastAssistantUsageBlock() throws {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":1000,"cache_read_input_tokens":500,"cache_creation_input_tokens":2500,"output_tokens":50}}}"#
        ].joined(separator: "\n")
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(lines)))
        #expect(usage.used == 4000)
        #expect(usage.window == 160_000)
    }

    @Test
    func skipsNonAssistantTurnsScanningBackwards() throws {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":1}}}"#,
            #"{"type":"queue-operation","operation":"enqueue"}"#,
            #"{"type":"user","message":{"role":"user","content":"q"}}"#
        ].joined(separator: "\n")
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(lines)))
        #expect(usage.used == 100)
    }

    @Test
    func returnsNilWhenNoAssistantUsage() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"queue-operation","operation":"dequeue"}"#
        ].joined(separator: "\n")
        #expect(ContextUsageReader.parse(transcriptData: data(lines)) == nil)
    }

    @Test
    func handlesMissingCacheFields() throws {
        let line = #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":150,"output_tokens":5}}}"#
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(line)))
        #expect(usage.used == 150)
    }

    @Test
    func skipsMalformedLines() throws {
        let lines = [
            "this is not json",
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":42}}}"#,
            "another garbage line"
        ].joined(separator: "\n")
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(lines)))
        #expect(usage.used == 42)
    }

    @Test
    func detects1mVariantWindow() throws {
        let line = #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7[1m]","usage":{"input_tokens":300000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":1}}}"#
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(line)))
        #expect(usage.used == 300_000)
        #expect(usage.window == 800_000)
        #expect(abs(usage.percentLeft - 62.5) < 0.01)
    }

    @Test
    func picksLatestAssistantTurnNotEarlier() throws {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":100,"output_tokens":1}}}"#,
            #"{"type":"user","message":{"role":"user","content":"more"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":2000,"output_tokens":50}}}"#
        ].joined(separator: "\n")
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(lines)))
        #expect(usage.used == 2000)
    }
}
