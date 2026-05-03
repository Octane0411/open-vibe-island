import Foundation
import Testing
@testable import OpenIslandCore

struct ProjectColorRegistryTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("project-colors-\(UUID().uuidString).json")
    }

    @Test
    func sameKeyHashesToSameColorAcrossInstances() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = ProjectColorRegistry(storeURL: url)
        let b = ProjectColorRegistry(storeURL: url)
        #expect(a.color(for: "/Users/x/Repo") == b.color(for: "/Users/x/Repo"))
    }

    @Test
    func differentKeysGetDifferentColors() {
        let registry = ProjectColorRegistry(storeURL: tempURL())
        let c1 = registry.color(for: "/Users/x/Repo")
        let c2 = registry.color(for: "/Users/x/Other")
        #expect(c1 != c2)
    }

    @Test
    func overrideIsPersistedAndReturnedOverHash() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = ProjectColorRegistry(storeURL: url)
        let key = "/Users/x/Repo"
        registry.setColor(.init(red: 0.9, green: 0.1, blue: 0.2), for: key)

        let reloaded = ProjectColorRegistry(storeURL: url)
        let stored = reloaded.color(for: key)
        #expect(abs(stored.red - 0.9) < 0.001)
        #expect(abs(stored.green - 0.1) < 0.001)
        #expect(abs(stored.blue - 0.2) < 0.001)
    }

    @Test
    func resetAllRestoresHashing() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = ProjectColorRegistry(storeURL: url)
        let key = "/Users/x/Repo"
        let original = registry.color(for: key)
        registry.setColor(.init(red: 1, green: 1, blue: 1), for: key)
        registry.resetAll()
        #expect(registry.color(for: key) == original)
    }

    @Test
    func corruptStoreStartsFreshAndDoesNotThrow() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "this is not json".write(to: url, atomically: true, encoding: .utf8)

        let registry = ProjectColorRegistry(storeURL: url)
        _ = registry.color(for: "/Users/x/Repo")  // must not throw
    }

    @Test
    func pruneRemovesUnreferencedKeys() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = ProjectColorRegistry(storeURL: url)
        _ = registry.color(for: "/a")
        _ = registry.color(for: "/b")
        _ = registry.color(for: "/c")
        registry.pruneUnusedKeys(activePaths: ["/a", "/c"])
        #expect(registry.knownKeys().sorted() == ["/a", "/c"])
    }
}
