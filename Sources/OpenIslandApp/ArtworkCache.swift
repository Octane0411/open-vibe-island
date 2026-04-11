import AppKit
import Observation

/// Thread-safe image store backed by a Swift actor.
private actor ArtworkStore {
    private var cache: [URL: NSImage] = [:]

    func image(for url: URL) -> NSImage? {
        cache[url]
    }

    func store(_ image: NSImage, for url: URL) {
        cache[url] = image
    }
}

/// @MainActor-observable wrapper around ArtworkStore.
/// Views call `image(for:)` synchronously; downloads happen off-thread.
@MainActor
@Observable
final class ArtworkCache {
    private let store = ArtworkStore()
    private var inFlight: Set<URL> = []
    /// Observable trigger: incremented whenever a new image lands.
    private(set) var version: Int = 0

    /// Main-actor mirror for synchronous reads without async bridging.
    private var mainCache: [URL: NSImage] = [:]

    /// Returns cached NSImage if available. Triggers download if not cached.
    func image(for url: URL) -> NSImage? {
        if mainCache[url] == nil {
            prefetch(url)
        }
        return mainCache[url]
    }

    /// Trigger async load for `url` if not already cached or in-flight.
    func prefetch(_ url: URL) {
        guard mainCache[url] == nil, !inFlight.contains(url) else { return }
        inFlight.insert(url)
        Task {
            let image = await loadImage(url: url)
            if let image {
                await store.store(image, for: url)
                mainCache[url] = image
                version += 1
            }
            inFlight.remove(url)
        }
    }

    /// For testing: directly insert an image without network.
    func store(_ image: NSImage, for url: URL) async {
        await store.store(image, for: url)
        mainCache[url] = image
        version += 1
    }

    // MARK: Private

    private func loadImage(url: URL) async -> NSImage? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return NSImage(data: data)
            }.value
        }
        // Remote URL: use URLSession for proper async, timeout, and cancellation support
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }
}
