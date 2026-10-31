import Foundation

/// A checked multi-file edit. Originals survive in a private recovery directory.
/// Compare again immediately before each replace to detect external edits.
/// Recovery never overwrites a file that has changed since our own write.
struct ConfigurationTransaction {
    static let installationLock = NSLock()
    struct File {
        let url: URL
        let original: Data?
        let permissions: Int

        init(_ url: URL) throws {
            self.url = url
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw ConfigurationError.unsafeFile(url.path)
                }
                let data = try Data(contentsOf: url)
                permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
                original = data
            } catch CocoaError.fileReadNoSuchFile {
                original = nil
                permissions = 0o600
            }
        }

        func check() throws {
            guard try File(url).original == original else { throw ConfigurationError.concurrentEdit(url.path) }
        }
    }

    struct Change {
        let file: File
        let contents: Data?
        var permissions: Int? = nil
    }

    static func apply(_ proposed: [Change], recoveryRoot: URL) throws {
        let changes = proposed.filter { $0.file.original != $0.contents }
        guard !changes.isEmpty else { return }
        for change in changes { try change.file.check() }
        let backup = recoveryRoot.appendingPathComponent(".open-island-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var manifest: [[String: Any]] = []
        for (index, change) in changes.enumerated() {
            if let original = change.file.original {
                try original.write(to: backup.appendingPathComponent("\(index).original"), options: .atomic)
            }
            manifest.append(["path": change.file.url.path, "originalExists": change.file.original != nil, "permissions": change.file.permissions])
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: backup.appendingPathComponent("manifest.json"), options: .atomic)
        var applied: [Change] = []
        do {
            for change in changes {
                try change.file.check()
                // Record before writing so a failed chmod is also rolled back.
                applied.append(change)
                try replace(change.file.url, with: change.contents, permissions: change.permissions ?? change.file.permissions)
            }
        } catch {
            for change in applied.reversed() {
                if let current = try? File(change.file.url), current.original == change.contents {
                    try? replace(change.file.url, with: change.file.original, permissions: change.file.permissions)
                }
            }
            throw ConfigurationError.transactionFailed(backup.path, error.localizedDescription)
        }
    }

    private static func replace(_ url: URL, with contents: Data?, permissions: Int) throws {
        if let contents {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum ConfigurationError: Error, LocalizedError {
    case invalidFormat(String), unsafeFile(String), concurrentEdit(String), transactionFailed(String, String)
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let path): "Invalid configuration at \(path); the existing file was preserved."
        case .unsafeFile(let path): "Refusing to replace a non-regular file at \(path)."
        case .concurrentEdit(let path): "Configuration changed during installation: \(path). Retry after closing the editor."
        case .transactionFailed(let backup, let reason): "Installation failed: \(reason). Original files are available at \(backup)."
        }
    }
}
