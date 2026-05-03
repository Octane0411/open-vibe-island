import Foundation
import Testing
@testable import OpenIslandCore

@MainActor
struct ContextUsageRegistryTests {
    @Test
    func cacheHitDoesNotReParse() async {
        var calls = 0
        let registry = ContextUsageRegistry(reader: { _ in
            calls += 1
            return ContextUsage(used: 100, window: 200_000)
        })
        registry.recordUsage(sessionID: "s1", transcriptPath: "/tmp/a.jsonl")
        _ = registry.usage(for: "s1")
        _ = registry.usage(for: "s1")
        #expect(calls == 1)
    }

    @Test
    func recordOverwritesPreviousValueForSession() {
        var values = [100, 500]
        let registry = ContextUsageRegistry(reader: { _ in
            ContextUsage(used: values.removeFirst(), window: 200_000)
        })
        registry.recordUsage(sessionID: "s1", transcriptPath: "/tmp/a.jsonl")
        #expect(registry.usage(for: "s1")?.used == 100)
        registry.invalidate(sessionID: "s1")
        registry.recordUsage(sessionID: "s1", transcriptPath: "/tmp/a.jsonl")
        #expect(registry.usage(for: "s1")?.used == 500)
    }

    @Test
    func pruneRemovesOnlyInactiveSessions() {
        let registry = ContextUsageRegistry(reader: { _ in
            ContextUsage(used: 1, window: 200_000)
        })
        registry.recordUsage(sessionID: "a", transcriptPath: "/tmp/a.jsonl")
        registry.recordUsage(sessionID: "b", transcriptPath: "/tmp/b.jsonl")
        registry.recordUsage(sessionID: "c", transcriptPath: "/tmp/c.jsonl")
        registry.prune(activeSessionIDs: ["a", "c"])
        #expect(registry.usage(for: "a") != nil)
        #expect(registry.usage(for: "b") == nil)
        #expect(registry.usage(for: "c") != nil)
    }

    @Test
    func unknownSessionReturnsNil() {
        let registry = ContextUsageRegistry(reader: { _ in nil })
        #expect(registry.usage(for: "missing") == nil)
    }
}
