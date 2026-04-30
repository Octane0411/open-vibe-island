import Foundation
import Testing
@testable import OpenIslandCore

struct ContextWindowTableTests {
    @Test
    func opus47Returns200K() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7") == 200_000)
    }

    @Test
    func opus47With1mSuffixReturns1M() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7[1m]") == 1_000_000)
    }

    @Test
    func sonnetReturns200K() {
        #expect(ContextWindowTable.window(for: "claude-sonnet-4-6") == 200_000)
    }

    @Test
    func haikuReturns200K() {
        #expect(ContextWindowTable.window(for: "claude-haiku-4-5-20251001") == 200_000)
    }

    @Test
    func unknownModelReturns200KDefault() {
        #expect(ContextWindowTable.window(for: "some-future-model") == 200_000)
    }

    @Test
    func emptyOrNilReturns200KDefault() {
        #expect(ContextWindowTable.window(for: "") == 200_000)
        #expect(ContextWindowTable.window(for: nil) == 200_000)
    }
}
