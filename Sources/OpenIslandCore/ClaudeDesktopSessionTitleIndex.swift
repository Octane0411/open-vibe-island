import Foundation
import os

/// Read-only index of session titles that Claude Desktop keeps for its
/// Code-tab sessions.
///
/// Claude Desktop writes one JSON file per session at
/// `~/Library/Application Support/Claude/claude-code-sessions/<uuid>/<uuid>/local_<uuid>.json`.
/// Each file carries `cliSessionId` (the Claude Code session id used by hooks
/// and transcripts) and `title`. Desktop auto-generates many of these titles
/// and never writes them to the transcript, so this index is the only local
/// source for them.
///
/// The files can be large (hundreds of KB, mostly MCP tool tables), so the
/// index only reads a small prefix of each file and walks the top-level keys
/// instead of parsing the whole document. Parsed results are cached per file
/// and keyed by modification date: a refresh re-reads only new or changed
/// files, and directory rescans are throttled.
///
/// Thread-safe. `refreshIfNeeded` performs file IO and must not be called
/// from the main thread; `title(forCLISessionID:)` only reads the cache.
public final class ClaudeDesktopSessionTitleIndex: Sendable {
    public static var defaultBaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    /// Process-wide index over the real Claude Desktop directory, shared by
    /// transcript discovery and the live bridge so the initial scan happens once.
    public static let shared = ClaudeDesktopSessionTitleIndex()

    private struct FileEntry {
        var modifiedAt: Date
        var cliSessionID: String?
        var title: String?
    }

    private struct State {
        var files: [String: FileEntry] = [:]
        var titlesByCLISessionID: [String: String] = [:]
        var lastScanAt: Date?
    }

    private let baseURL: URL
    private let minimumRescanInterval: TimeInterval
    private let prefixByteCount: Int
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Serializes scans so two callers never walk the directory at once.
    private let scanLock = NSLock()

    public init(
        baseURL: URL = ClaudeDesktopSessionTitleIndex.defaultBaseURL,
        minimumRescanInterval: TimeInterval = 5,
        prefixByteCount: Int = 16 * 1_024
    ) {
        self.baseURL = baseURL
        self.minimumRescanInterval = minimumRescanInterval
        self.prefixByteCount = max(prefixByteCount, 64)
    }

    /// Cached title for a Claude Code session id, or `nil` when unknown.
    /// Never touches the filesystem.
    public func title(forCLISessionID sessionID: String) -> String? {
        state.withLock { $0.titlesByCLISessionID[sessionID] }
    }

    /// Whether a refresh right now would be throttled.
    public func isThrottled(now: Date = .now) -> Bool {
        state.withLock { state in
            guard let lastScanAt = state.lastScanAt else { return false }
            return now.timeIntervalSince(lastScanAt) < minimumRescanInterval
        }
    }

    /// Seconds until the throttle window ends (0 when not throttled).
    public func remainingThrottleInterval(now: Date = .now) -> TimeInterval {
        state.withLock { state in
            guard let lastScanAt = state.lastScanAt else { return 0 }
            return max(0, minimumRescanInterval - now.timeIntervalSince(lastScanAt))
        }
    }

    /// Rescans the directory unless a scan happened within the throttle
    /// window (or `force` is set). Only new or modified files are read.
    ///
    /// - Returns: `true` when the title map changed.
    @discardableResult
    public func refreshIfNeeded(now: Date = .now, force: Bool = false) -> Bool {
        scanLock.lock()
        defer { scanLock.unlock() }

        let (previousFiles, previousTitles, shouldScan) = state.withLock { state -> ([String: FileEntry], [String: String], Bool) in
            if !force,
               let lastScanAt = state.lastScanAt,
               now.timeIntervalSince(lastScanAt) < minimumRescanInterval {
                return ([:], [:], false)
            }
            return (state.files, state.titlesByCLISessionID, true)
        }
        guard shouldScan else { return false }

        var files: [String: FileEntry] = [:]
        for (path, modifiedAt) in sessionFiles() {
            if let cached = previousFiles[path], cached.modifiedAt == modifiedAt {
                files[path] = cached
                continue
            }
            let parsed = Self.parseSessionFile(atPath: path, prefixByteCount: prefixByteCount)
            files[path] = FileEntry(
                modifiedAt: modifiedAt,
                cliSessionID: parsed.cliSessionID,
                title: parsed.title
            )
        }

        // If several files point at the same CLI session (forks, re-opens),
        // the most recently modified one wins.
        var titles: [String: String] = [:]
        var winningModifiedAt: [String: Date] = [:]
        for entry in files.values {
            guard let sessionID = entry.cliSessionID, let title = entry.title else { continue }
            if let current = winningModifiedAt[sessionID], current >= entry.modifiedAt {
                continue
            }
            winningModifiedAt[sessionID] = entry.modifiedAt
            titles[sessionID] = title
        }

        let finalFiles = files
        let finalTitles = titles
        state.withLock { state in
            state.files = finalFiles
            state.titlesByCLISessionID = finalTitles
            state.lastScanAt = now
        }
        return titles != previousTitles
    }

    // MARK: - Directory walk

    /// `<base>/<uuid>/<uuid>/*.json` with modification dates. Missing or
    /// unreadable directories yield an empty list.
    private func sessionFiles() -> [(path: String, modifiedAt: Date)] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .isRegularFileKey]
        var results: [(path: String, modifiedAt: Date)] = []

        func children(of url: URL) -> [URL] {
            (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        func isDirectory(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }

        for first in children(of: baseURL) where isDirectory(first) {
            for second in children(of: first) where isDirectory(second) {
                for file in children(of: second) where file.pathExtension == "json" {
                    guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                          values.isRegularFile == true,
                          let modifiedAt = values.contentModificationDate else {
                        continue
                    }
                    results.append((file.path, modifiedAt))
                }
            }
        }
        return results
    }

    // MARK: - Parsing

    struct ParsedSessionFile: Equatable {
        var cliSessionID: String?
        var title: String?
    }

    static func parseSessionFile(atPath path: String, prefixByteCount: Int) -> ParsedSessionFile {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return ParsedSessionFile()
        }
        defer { try? handle.close() }

        let prefix = (try? handle.read(upToCount: prefixByteCount)) ?? Data()
        let wanted: Set<String> = ["cliSessionId", "title"]

        switch TopLevelJSONStringScanner.scan(prefix, keys: wanted) {
        case let .complete(values):
            return ParsedSessionFile(values)
        case .malformed:
            return ParsedSessionFile()
        case .truncated:
            // Title sits after the prefix (rare). Fall back to a full parse.
            var data = prefix
            if let rest = try? handle.readToEnd() {
                data.append(rest)
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ParsedSessionFile()
            }
            var values: [String: String] = [:]
            for key in wanted {
                if let value = object[key] as? String {
                    values[key] = value
                }
            }
            return ParsedSessionFile(values)
        }
    }
}

private extension ClaudeDesktopSessionTitleIndex.ParsedSessionFile {
    init(_ values: [String: String]) {
        let sessionID = values["cliSessionId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = values["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            cliSessionID: sessionID?.isEmpty == false ? sessionID : nil,
            title: title?.isEmpty == false ? title : nil
        )
    }
}

/// Minimal streaming walker over the top level of a JSON object that extracts
/// string values for a few keys without parsing nested values. Used to read
/// small fields from the head of large JSON files.
enum TopLevelJSONStringScanner {
    enum Result: Equatable {
        /// All wanted keys were found, or the object ended. Missing keys are absent.
        case complete([String: String])
        /// The buffer ended before the object did and not all keys were found.
        case truncated
        /// Not a JSON object.
        case malformed
    }

    static func scan(_ data: Data, keys: Set<String>) -> Result {
        let bytes = [UInt8](data)
        var index = 0
        var values: [String: String] = [:]

        func skipWhitespace() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D:
                    index += 1
                default:
                    return
                }
            }
        }

        /// Advances past a JSON string starting at `index` (which must be a quote).
        /// Returns the range including quotes, or nil if the buffer ended.
        func skipString() -> Range<Int>? {
            let start = index
            index += 1
            while index < bytes.count {
                switch bytes[index] {
                case 0x5C: // backslash
                    index += 2
                case 0x22: // quote
                    index += 1
                    return start..<index
                default:
                    index += 1
                }
            }
            return nil
        }

        /// Skips any non-string value. Returns false if the buffer ended.
        func skipValue() -> Bool {
            var depth = 0
            while index < bytes.count {
                let byte = bytes[index]
                switch byte {
                case 0x22:
                    guard skipString() != nil else { return false }
                    continue
                case 0x7B, 0x5B: // { [
                    depth += 1
                case 0x7D, 0x5D: // } ]
                    if depth == 0 { return true }
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        return true
                    }
                case 0x2C: // ,
                    if depth == 0 { return true }
                default:
                    break
                }
                index += 1
            }
            return false
        }

        func decodeString(_ range: Range<Int>) -> String? {
            let fragment = Data(bytes[range])
            return (try? JSONSerialization.jsonObject(with: fragment, options: [.fragmentsAllowed])) as? String
        }

        skipWhitespace()
        guard index < bytes.count else { return .truncated }
        guard bytes[index] == 0x7B else { return .malformed }
        index += 1

        while true {
            skipWhitespace()
            guard index < bytes.count else { return .truncated }
            if bytes[index] == 0x7D { return .complete(values) }
            guard bytes[index] == 0x22 else { return .malformed }
            guard let keyRange = skipString() else { return .truncated }
            guard let key = decodeString(keyRange) else { return .malformed }

            skipWhitespace()
            guard index < bytes.count else { return .truncated }
            guard bytes[index] == 0x3A else { return .malformed }
            index += 1
            skipWhitespace()
            guard index < bytes.count else { return .truncated }

            if bytes[index] == 0x22 {
                guard let valueRange = skipString() else { return .truncated }
                if keys.contains(key), let value = decodeString(valueRange) {
                    values[key] = value
                    if values.count == keys.count {
                        return .complete(values)
                    }
                }
            } else {
                guard skipValue() else { return .truncated }
            }

            skipWhitespace()
            guard index < bytes.count else { return .truncated }
            switch bytes[index] {
            case 0x2C:
                index += 1
            case 0x7D:
                return .complete(values)
            default:
                return .malformed
            }
        }
    }
}
