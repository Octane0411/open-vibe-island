import Foundation
import Testing
@testable import OpenIslandCore

struct ContextWindowTableTests {
    @Test
    func opus47Returns160K() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7") == 160_000)
    }

    @Test
    func opus47With1mSuffixReturns1M() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7[1m]") == 800_000)
    }

    @Test
    func sonnetReturns160K() {
        #expect(ContextWindowTable.window(for: "claude-sonnet-4-6") == 160_000)
    }

    @Test
    func haikuReturns160K() {
        #expect(ContextWindowTable.window(for: "claude-haiku-4-5-20251001") == 160_000)
    }

    @Test
    func unknownModelReturns160KDefault() {
        #expect(ContextWindowTable.window(for: "some-future-model") == 160_000)
    }

    @Test
    func emptyOrNilReturns160KDefault() {
        #expect(ContextWindowTable.window(for: "") == 160_000)
        #expect(ContextWindowTable.window(for: nil) == 160_000)
    }

    @Test
    func observedUsedAbove400KTriggers1M() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7", observedUsed: 400_000) == 800_000)
    }

    @Test
    func observedUsedAbove165KTriggers1M() {
        // 200K-context sessions auto-compact around 160K, so a transcript
        // exceeding the detection threshold without compaction must be 1M.
        #expect(ContextWindowTable.window(for: "claude-opus-4-7", observedUsed: 180_000) == 800_000)
    }

    @Test
    func observedUsedAt165KStaysDefault() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7", observedUsed: 165_000) == 160_000)
    }

    @Test
    func observedUsedBelow165KStaysDefault() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7", observedUsed: 150_000) == 160_000)
    }

    @Test
    func suffix1MStaysAt800KEvenWithSmallObserved() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7[1m]", observedUsed: 1000) == 800_000)
    }
}
