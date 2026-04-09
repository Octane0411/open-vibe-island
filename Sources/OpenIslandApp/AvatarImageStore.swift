import AppKit
import Foundation
import UniformTypeIdentifiers

enum AvatarImageStore {
    static let maxImportBytes = 10 * 1024 * 1024
    static let maxPixelDimension: CGFloat = 256

    private static let directoryName = "OpenIsland"
    private static let fileName = "custom-avatar.png"

    enum ImportError: LocalizedError {
        case unsupportedImage
        case fileTooLarge(limitBytes: Int)
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedImage:
                return "The selected file is not a supported static image."
            case .fileTooLarge(let limitBytes):
                let limitMB = limitBytes / (1024 * 1024)
                return "The selected file is too large. Choose an image under \(limitMB) MB."
            case .encodeFailed:
                return "Open Island could not process that image."
            }
        }
    }

    static func currentImage(fileManager: FileManager = .default) -> NSImage? {
        let url = avatarURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    static func removeCurrentImage(fileManager: FileManager = .default) throws {
        let url = avatarURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    static func importImage(from sourceURL: URL, fileManager: FileManager = .default) throws -> NSImage {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let fileSize = values.fileSize, fileSize > maxImportBytes {
            throw ImportError.fileTooLarge(limitBytes: maxImportBytes)
        }

        if let contentType = values.contentType {
            let supportedTypes: [UTType] = [.png, .jpeg, .heic, .tiff]
            guard supportedTypes.contains(where: { contentType.conforms(to: $0) }) else {
                throw ImportError.unsupportedImage
            }
        }

        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            throw ImportError.unsupportedImage
        }

        let normalizedImage = normalizedAvatarImage(from: sourceImage)
        let targetURL = avatarURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard
            let tiffData = normalizedImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ImportError.encodeFailed
        }

        try pngData.write(to: targetURL, options: .atomic)
        return normalizedImage
    }

    private static func avatarURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return appSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func normalizedAvatarImage(from sourceImage: NSImage) -> NSImage {
        let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            ?? NSImage(size: sourceImage.size).cgImage(forProposedRect: nil, context: nil, hints: nil)

        guard let cgImage else {
            return sourceImage
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let squareSide = min(width, height)
        let cropRect = CGRect(
            x: (width - squareSide) / 2,
            y: (height - squareSide) / 2,
            width: squareSide,
            height: squareSide
        ).integral

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return sourceImage
        }

        let targetSize = CGSize(width: maxPixelDimension, height: maxPixelDimension)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: croppedCGImage, size: targetSize)
            .draw(in: CGRect(origin: .zero, size: targetSize))
        image.unlockFocus()
        return image
    }
}
