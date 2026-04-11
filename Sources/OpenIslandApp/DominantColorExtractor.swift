import AppKit
import SwiftUI

enum DominantColorExtractor {
    /// Extract dominant color from an NSImage by sampling an 8×8 downscaled version.
    /// Skips near-black and near-white pixels. Returns `.gray` on failure.
    static func extract(from image: NSImage) -> Color {
        let sampleSize = 8
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .gray
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: sampleSize * sampleSize * 4)
        guard let context = CGContext(
            data: &pixels,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: sampleSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .gray }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0

        for i in 0..<(sampleSize * sampleSize) {
            let base = i * 4
            let r = CGFloat(pixels[base]) / 255
            let g = CGFloat(pixels[base + 1]) / 255
            let b = CGFloat(pixels[base + 2]) / 255
            let brightness = (r + g + b) / 3
            // Skip near-black and near-white pixels
            guard brightness > 0.1 && brightness < 0.95 else { continue }
            totalR += r
            totalG += g
            totalB += b
            count += 1
        }

        guard count > 0 else { return .gray }
        return Color(
            red: Double(totalR / count),
            green: Double(totalG / count),
            blue: Double(totalB / count)
        )
    }

    static func extractOrFallback(from image: NSImage?) -> Color {
        guard let image else { return .gray }
        return extract(from: image)
    }
}
