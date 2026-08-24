import Foundation

/// Reads Codex rollout transcripts and turns them into observations.
///
/// The transcript is Codex's internal append-only log. It carries no
/// compatibility guarantee, its vocabulary shifts between releases, and a
/// single machine holds files written by many versions at once. Treating it as
/// a stable API is what produced the failure mode this refactor exists to fix.
///
/// So its role here is deliberately narrow. It is authoritative for two things
/// it genuinely is authoritative for — where a session came from
/// (`session_meta.originator`/`source`) and its working directory — and it
/// supplies a fallback title from the first user prompt. It may not decide run
/// phase, liveness, or approvals; `CodexAuthorityMatrix` enforces that.
///
/// During cold start, when no other source exists yet, the facet store's replay
/// mode temporarily lets it fill the gaps — provisionally, so the first
/// authoritative write replaces whatever it guessed.
public final class CodexRolloutSource: @unchecked Sendable {
    private let decoder: CodexRecordDecoder
    private let diagnostics: CodexDiagnostics?
    private let lock = NSLock()
    private var nextSeq: UInt64 = 0

    public init(diagnostics: CodexDiagnostics? = nil) {
        self.decoder = CodexRecordDecoder(diagnostics: diagnostics)
        self.diagnostics = diagnostics
    }

    private func allocateSeq() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        nextSeq += 1
        return nextSeq
    }

    /// What a pass over a transcript learned.
    public struct Reading: Equatable, Sendable {
        public var observation: CodexObservation?
        public var meta: CodexSessionMeta?
        /// True when the transcript belongs to a thread Codex spawned for
        /// itself. Callers can skip such files entirely on later passes.
        public var isSubagent: Bool

        public init(
            observation: CodexObservation? = nil,
            meta: CodexSessionMeta? = nil,
            isSubagent: Bool = false
        ) {
            self.observation = observation
            self.meta = meta
            self.isSubagent = isSubagent
        }
    }

    /// Fold a sequence of transcript lines into one observation.
    ///
    /// Folding rather than emitting per line keeps cold start proportional to
    /// the number of sessions rather than the number of records — a user's
    /// history runs to gigabytes, and replaying every tool call through the
    /// projector would be pure waste.
    public func read(
        lines: [String],
        transcriptPath: String? = nil,
        at timestamp: Date = .now
    ) -> Reading {
        var meta: CodexSessionMeta?
        var narrative = CodexNarrative(transcriptPath: transcriptPath)
        var sawInitialPrompt = false
        var lastRecordTimestamp: Date?

        for line in lines {
            guard let record = decoder.decode(line: line, cliVersion: meta?.cliVersion) else {
                continue
            }
            if let recordTime = record.timestamp {
                lastRecordTimestamp = recordTime
            }

            switch record.kind {
            case .sessionMeta:
                meta = record.meta

            case .userMessage:
                guard let text = record.text, !text.isEmpty else { continue }
                if !sawInitialPrompt {
                    narrative.initialUserPrompt = text
                    sawInitialPrompt = true
                }
                narrative.lastUserPrompt = text

            case .assistantMessage:
                if let text = record.text, !text.isEmpty {
                    narrative.lastAssistantMessage = text
                }

            case .toolCallBegin:
                narrative.currentTool = record.toolName
                narrative.currentCommandPreview = record.commandPreview

            case .toolCallEnd:
                // Leave the tool name in place: the session row reads better
                // showing what just ran than showing nothing at all.
                narrative.currentCommandPreview = nil

            case .reasoning, .turnStarted, .turnEnded, .tokenCount,
                 .subAgentActivity, .turnContext, .worldState,
                 .threadBookkeeping, .interAgentMetadata:
                // Recognized and deliberately not folded into a facet: these
                // carry no state this source is allowed to write.
                continue
            }
        }

        guard let meta else {
            // Without a header there is no identity, so nothing can be reported.
            return Reading()
        }

        let surface = CodexIdentityResolver.surface(
            originator: meta.originator,
            source: meta.source,
            threadSource: meta.threadSource,
            parentThreadID: meta.parentThreadID,
            diagnostics: diagnostics
        )

        var patch = CodexFacetPatch()
        patch.surface = surface
        patch.workspace = CodexWorkspace(workingDirectory: meta.cwd)
        if !narrative.isEmpty {
            patch.narrative = narrative
        }

        let observation = CodexObservation(
            ref: .sessionID(meta.sessionID),
            source: .rollout,
            seq: allocateSeq(),
            observedAt: lastRecordTimestamp ?? meta.timestamp ?? timestamp,
            patch: patch,
            cliVersion: meta.cliVersion
        )

        return Reading(
            observation: observation,
            meta: meta,
            isSubagent: surface.isSubagent
        )
    }

    /// How much of each end of a transcript cold start reads.
    ///
    /// Transcripts grow without bound — a real corpus runs to gigabytes — but
    /// everything cold start needs sits at the two ends: `session_meta` and the
    /// opening prompt are in the first records, recent activity is in the last.
    /// Reading whole files instead took roughly seven minutes over one user's
    /// history; bounded reads bring the same restore down to seconds.
    public static let headReadLimit = 64 * 1024
    public static let tailReadLimit = 128 * 1024
    /// `session_meta` is a single line, but not a small one — it can embed the
    /// full system instructions and run past a hundred kilobytes. When the
    /// header does not fit the normal head read, the read grows until it does
    /// rather than abandoning the transcript.
    public static let headReadCeiling = 4 * 1024 * 1024

    /// Read a transcript for cold-start restore, touching only its two ends.
    ///
    /// Live updates should not come through here — they fold only the bytes
    /// appended since the previous read.
    public func read(fileAt url: URL, at timestamp: Date = .now) -> Reading {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Reading()
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let head = Self.headReadLimit
        let tail = Self.tailReadLimit

        var lines: [String] = []
        if size <= UInt64(head + tail) {
            try? handle.seek(toOffset: 0)
            let data = (try? handle.readToEnd()) ?? Data()
            lines = Self.lines(from: data, dropFirstPartial: false)
        } else {
            var headLimit = head
            var headLines = Self.readHead(handle, limit: headLimit)
            // Grow the head read until the header is inside it. A transcript
            // whose first line alone exceeds the ceiling is left unread rather
            // than pulled entirely into memory.
            while !Self.containsSessionMeta(headLines), headLimit < Self.headReadCeiling {
                headLimit = min(headLimit * 4, Self.headReadCeiling)
                headLines = Self.readHead(handle, limit: headLimit)
            }
            lines = headLines

            try? handle.seek(toOffset: size - UInt64(tail))
            let tailData = (try? handle.read(upToCount: tail)) ?? Data()
            // The tail almost certainly starts mid-record; that fragment is not
            // valid JSON and would otherwise be counted as drift.
            lines.append(contentsOf: Self.lines(from: tailData, dropFirstPartial: true))
        }

        return read(lines: lines, transcriptPath: url.path, at: timestamp)
    }

    static func readHead(_ handle: FileHandle, limit: Int) -> [String] {
        try? handle.seek(toOffset: 0)
        let data = (try? handle.read(upToCount: limit)) ?? Data()
        return lines(from: data, dropFirstPartial: false)
    }

    static func containsSessionMeta(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("\"session_meta\"") }
    }

    static func lines(from data: Data, dropFirstPartial: Bool) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }
        var result = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if dropFirstPartial, !result.isEmpty {
            result.removeFirst()
        }
        return result
    }
}
