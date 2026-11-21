import Foundation
import os

/// Precedence rules for the human-facing title of a Claude Code session.
///
/// 1. The last `custom-title` record in the transcript (written by `/rename`
///    and by renaming the session in Claude Desktop).
/// 2. The title Claude Desktop keeps in its own session index (covers
///    Desktop auto-generated titles that never reach the transcript).
/// 3. The last `ai-title` record in the transcript.
///
/// Returns `nil` when none is available so callers keep their existing
/// headline (workspace + initial prompt).
public enum ClaudeSessionTitleResolver {
    public static func resolve(
        customTitle: String?,
        desktopTitle: String?,
        aiTitle: String?
    ) -> String? {
        for candidate in [customTitle, desktopTitle, aiTitle] {
            if let title = normalized(candidate) {
                return title
            }
        }
        return nil
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }
}

/// Title records Claude Code appends to a session transcript.
enum ClaudeTranscriptTitleRecord: Equatable {
    case custom(String)
    case ai(String)

    /// Byte markers used to skip JSON parsing for lines that cannot be
    /// title records.
    static let markers: [Data] = [Data("custom-title".utf8), Data("ai-title".utf8)]

    static func parse(_ object: [String: Any]) -> ClaudeTranscriptTitleRecord? {
        switch object["type"] as? String {
        case "custom-title":
            guard let title = ClaudeSessionTitleResolver.normalized(object["customTitle"] as? String) else {
                return nil
            }
            return .custom(title)
        case "ai-title":
            guard let title = ClaudeSessionTitleResolver.normalized(object["aiTitle"] as? String) else {
                return nil
            }
            return .ai(title)
        default:
            return nil
        }
    }
}

/// Last `custom-title` / `ai-title` seen in a transcript.
public struct ClaudeTranscriptTitles: Equatable, Sendable {
    public var customTitle: String?
    public var aiTitle: String?

    public init(customTitle: String? = nil, aiTitle: String? = nil) {
        self.customTitle = customTitle
        self.aiTitle = aiTitle
    }

    mutating func apply(_ record: ClaudeTranscriptTitleRecord) {
        switch record {
        case let .custom(title):
            customTitle = title
        case let .ai(title):
            aiTitle = title
        }
    }
}

/// Incrementally scans live transcripts for title records.
///
/// Keeps a per-file cursor so each call reads only bytes appended since the
/// previous call (a full scan happens once per transcript, or again if the
/// file shrinks). Lines are JSON-parsed only when they contain a title
/// marker, so tool-output-heavy transcripts stay cheap.
final class ClaudeTranscriptTitleScanner: Sendable {
    private struct Cursor {
        var offset: UInt64 = 0
        var pending = Data()
        var titles = ClaudeTranscriptTitles()
    }

    private static let chunkSize = 256 * 1_024
    private let cursors = OSAllocatedUnfairLock(initialState: [String: Cursor]())

    func titles(forTranscriptAt path: String) -> ClaudeTranscriptTitles {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            return cursors.withLock { $0[path]?.titles } ?? ClaudeTranscriptTitles()
        }

        var cursor = cursors.withLock { $0[path] } ?? Cursor()
        if size < cursor.offset {
            // Truncated or replaced: start over.
            cursor = Cursor()
        }

        if size > cursor.offset,
           let handle = FileHandle(forReadingAtPath: path) {
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: cursor.offset)
                while let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty {
                    cursor.offset += UInt64(chunk.count)
                    cursor.pending.append(chunk)
                    Self.consumeCompleteLines(from: &cursor)
                }
            } catch {
                // Keep whatever was read; retry from the new offset next time.
            }
        }

        let finalCursor = cursor
        cursors.withLock { $0[path] = finalCursor }
        return finalCursor.titles
    }

    private static func consumeCompleteLines(from cursor: inout Cursor) {
        let newline = UInt8(ascii: "\n")
        var lineStart = cursor.pending.startIndex
        while let newlineIndex = cursor.pending[lineStart...].firstIndex(of: newline) {
            let line = cursor.pending[lineStart..<newlineIndex]
            lineStart = cursor.pending.index(after: newlineIndex)
            guard !line.isEmpty,
                  ClaudeTranscriptTitleRecord.markers.contains(where: { line.range(of: $0) != nil }),
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let record = ClaudeTranscriptTitleRecord.parse(object) else {
                continue
            }
            cursor.titles.apply(record)
        }
        if lineStart != cursor.pending.startIndex {
            cursor.pending = Data(cursor.pending[lineStart...])
        }
    }
}

/// Resolves titles for live Claude Code sessions off the caller's thread.
///
/// Callers (the bridge) read `cachedTitle(forSessionID:)` synchronously and
/// call `requestRefresh` on hook events. Refreshes run on a private utility
/// queue — transcript scan plus a throttled Claude Desktop index refresh —
/// and the change handler fires whenever a session's resolved title changes.
/// When the Desktop index was throttled and has no title for the session yet,
/// one delayed retry is scheduled for the end of the throttle window, which
/// catches Desktop naming a session a few seconds after its first prompt.
public final class ClaudeSessionTitleService: Sendable {
    public typealias ChangeHandler = @Sendable (_ sessionID: String, _ title: String) -> Void

    private struct State {
        var titles: [String: String] = [:]
        /// Sessions queued for refresh → latest known transcript path.
        var pending: [String: String?] = [:]
        var delayedRetries: Set<String> = []
        var handler: ChangeHandler?
    }

    private let desktopIndex: ClaudeDesktopSessionTitleIndex?
    private let transcriptScanner = ClaudeTranscriptTitleScanner()
    private let workQueue = DispatchQueue(label: "app.openisland.claude-session-titles", qos: .utility)
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(desktopIndex: ClaudeDesktopSessionTitleIndex? = .shared) {
        self.desktopIndex = desktopIndex
    }

    public func setChangeHandler(_ handler: ChangeHandler?) {
        state.withLock { $0.handler = handler }
    }

    public func cachedTitle(forSessionID sessionID: String) -> String? {
        state.withLock { $0.titles[sessionID] }
    }

    /// Schedules an asynchronous re-resolution. Requests for a session that
    /// is already queued are coalesced.
    public func requestRefresh(sessionID: String, transcriptPath: String?) {
        let shouldSchedule = state.withLock { state -> Bool in
            let alreadyQueued = state.pending[sessionID] != nil
            state.pending[sessionID] = .some(transcriptPath)
            return !alreadyQueued
        }
        guard shouldSchedule else { return }
        workQueue.async { [self] in
            drain(sessionID: sessionID)
        }
    }

    /// Resolves synchronously on the calling thread (tests, background callers).
    @discardableResult
    public func refreshNow(sessionID: String, transcriptPath: String?) -> String? {
        resolveAndPublish(sessionID: sessionID, transcriptPath: transcriptPath, allowDelayedRetry: false)
    }

    private func drain(sessionID: String) {
        let entry = state.withLock { $0.pending.removeValue(forKey: sessionID) }
        guard let entry else { return }
        resolveAndPublish(sessionID: sessionID, transcriptPath: entry, allowDelayedRetry: true)
    }

    @discardableResult
    private func resolveAndPublish(
        sessionID: String,
        transcriptPath: String?,
        allowDelayedRetry: Bool
    ) -> String? {
        var desktopTitle: String?
        if let desktopIndex {
            desktopIndex.refreshIfNeeded()
            desktopTitle = desktopIndex.title(forCLISessionID: sessionID)
        }

        let transcriptTitles = transcriptPath
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { transcriptScanner.titles(forTranscriptAt: $0) }
            ?? ClaudeTranscriptTitles()

        let resolved = ClaudeSessionTitleResolver.resolve(
            customTitle: transcriptTitles.customTitle,
            desktopTitle: desktopTitle,
            aiTitle: transcriptTitles.aiTitle
        )

        if allowDelayedRetry,
           desktopTitle == nil,
           let desktopIndex,
           desktopIndex.isThrottled() {
            scheduleDelayedRetry(
                sessionID: sessionID,
                transcriptPath: transcriptPath,
                after: desktopIndex.remainingThrottleInterval() + 0.1
            )
        }

        guard let resolved else {
            return state.withLock { $0.titles[sessionID] }
        }

        let handler = state.withLock { state -> ChangeHandler? in
            guard state.titles[sessionID] != resolved else { return nil }
            state.titles[sessionID] = resolved
            return state.handler
        }
        handler?(sessionID, resolved)
        return resolved
    }

    private func scheduleDelayedRetry(sessionID: String, transcriptPath: String?, after delay: TimeInterval) {
        let shouldSchedule = state.withLock { state -> Bool in
            state.delayedRetries.insert(sessionID).inserted
        }
        guard shouldSchedule else { return }
        workQueue.asyncAfter(deadline: .now() + delay) { [self] in
            state.withLock { _ = $0.delayedRetries.remove(sessionID) }
            resolveAndPublish(sessionID: sessionID, transcriptPath: transcriptPath, allowDelayedRetry: false)
        }
    }
}
