import Testing
import AppKit
@testable import OpenIslandApp

@MainActor
struct ArtworkCacheTests {
    @Test func cacheMissReturnsNil() {
        let cache = ArtworkCache()
        let url = URL(string: "https://example.com/art.jpg")!
        let result = cache.image(for: url)
        #expect(result == nil)
    }

    @Test func cacheHitReturnsSameImage() async {
        let cache = ArtworkCache()
        let url = URL(string: "https://example.com/art.jpg")!
        let image = NSImage(size: NSSize(width: 1, height: 1))
        await cache.store(image, for: url)
        let result = cache.image(for: url)
        #expect(result != nil)
    }

    @Test func versionIncrementOnStore() async {
        let cache = ArtworkCache()
        let initial = cache.version
        let url = URL(string: "https://example.com/b.jpg")!
        let image = NSImage(size: NSSize(width: 1, height: 1))
        await cache.store(image, for: url)
        #expect(cache.version == initial + 1)
    }

    @Test func differentURLsAreCachedSeparately() async {
        let cache = ArtworkCache()
        let url1 = URL(string: "https://example.com/a.jpg")!
        let url2 = URL(string: "https://example.com/b.jpg")!
        let img1 = NSImage(size: NSSize(width: 1, height: 1))
        let img2 = NSImage(size: NSSize(width: 2, height: 2))
        await cache.store(img1, for: url1)
        await cache.store(img2, for: url2)
        #expect(cache.image(for: url1) != nil)
        #expect(cache.image(for: url2) != nil)
    }

    @Test func cacheLoadsFileURL() async throws {
        let cache = ArtworkCache()
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_artwork_cache_\(UUID().uuidString).jpg")
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [:]) else {
            Issue.record("Could not create test JPEG")
            return
        }
        try jpg.write(to: tmpURL)
        cache.prefetch(tmpURL)
        try await Task.sleep(for: .milliseconds(300))
        #expect(cache.image(for: tmpURL) != nil)
        try? FileManager.default.removeItem(at: tmpURL)
    }
}
