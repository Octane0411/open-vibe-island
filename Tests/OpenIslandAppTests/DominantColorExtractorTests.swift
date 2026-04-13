import Testing
import SwiftUI
import AppKit
@testable import OpenIslandApp

struct DominantColorExtractorTests {
    @Test func redImageReturnsSomewhatReddishColor() {
        let image = solidColorImage(nsColor: .red)
        let color = DominantColorExtractor.extract(from: image)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let nsColor = NSColor(color).usingColorSpace(.sRGB)!
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > 0.5)
        #expect(r > g)
        #expect(r > b)
    }

    @Test func blueImageReturnsSomewhatBluishColor() {
        let image = solidColorImage(nsColor: .blue)
        let color = DominantColorExtractor.extract(from: image)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let nsColor = NSColor(color).usingColorSpace(.sRGB)!
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(b > 0.5)
        #expect(b > r)
        #expect(b > g)
    }

    @Test func nilImageReturnsFallback() {
        let color = DominantColorExtractor.extractOrFallback(from: nil)
        _ = color  // just verify no crash
    }

    @Test func extractIsPure() {
        let image = solidColorImage(nsColor: .green)
        let c1 = DominantColorExtractor.extract(from: image)
        let c2 = DominantColorExtractor.extract(from: image)
        #expect(c1 == c2)
    }

    // MARK: Helpers

    private func solidColorImage(nsColor: NSColor) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        nsColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
