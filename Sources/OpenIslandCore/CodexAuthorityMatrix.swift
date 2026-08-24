import Foundation

/// The six orthogonal dimensions of Codex session state.
///
/// Splitting the session this way is what makes arbitration tractable. A scalar
/// priority over sources cannot work, because no source dominates: the
/// app-server is authoritative for run state yet cannot see the terminal, while
/// hooks are authoritative for the terminal yet cannot see a desktop thread
/// close. Ranking sources per *facet* lets each one win exactly where it can
/// actually observe the truth, and stay out of the way everywhere else.
public enum CodexFacet: String, CaseIterable, Sendable {
    case surface
    case placement
    case lifecycle
    case actionable
    case narrative
    case liveness
}

/// Which source may write which facet, and who wins when two of them try.
///
/// This is deliberately a single declarative table rather than conditionals
/// spread across the source adapters. Every behavioural question about "who
/// decides X" is answered by reading one function, and changing the answer is a
/// one-line edit with a matching test.
public enum CodexAuthorityMatrix {
    /// Ranked writers for a facet, strongest first. A source absent from the
    /// list may never write that facet.
    ///
    /// The ordering encodes what each channel can physically observe:
    ///
    /// - `surface` — only `session_meta` carries `originator`/`source`, so the
    ///   rollout wins; the app-server's `thread.source` is a weaker echo.
    /// - `placement` — hooks alone see the terminal. Process observation can
    ///   contribute a working directory and nothing more.
    /// - `lifecycle` — the app-server reports turn boundaries directly; hooks
    ///   infer them from tool-use edges. The rollout is always behind.
    /// - `actionable` — approvals moved into the hook system entirely.
    /// - `narrative` — a user-assigned thread name beats a prompt scraped from
    ///   the transcript.
    /// - `liveness` — `thread/closed` is definitive; a live process is good
    ///   evidence; a `Stop` hook is weaker. The rollout may not participate,
    ///   because "the file went away" means the session was archived, not that
    ///   it ended.
    public static func writers(for facet: CodexFacet) -> [CodexSource] {
        switch facet {
        case .surface:
            [.rollout, .appServer]
        case .placement:
            [.hook, .process]
        case .lifecycle:
            [.appServer, .hook]
        case .actionable:
            [.hook]
        case .narrative:
            [.appServer, .rollout, .hook]
        case .liveness:
            [.appServer, .process, .hook]
        }
    }

    /// Rank of `source` for `facet`; lower is stronger. `nil` means the source
    /// has no authority over that facet at all.
    public static func rank(of source: CodexSource, for facet: CodexFacet) -> Int? {
        writers(for: facet).firstIndex(of: source)
    }

    public static func canWrite(_ source: CodexSource, _ facet: CodexFacet) -> Bool {
        rank(of: source, for: facet) != nil
    }

    /// Whether an incoming write should replace what is already stored.
    ///
    /// - A source with no authority is always rejected.
    /// - Provisional values — written during cold-start replay, when the
    ///   rollout is the only source that exists yet — are replaced by the first
    ///   real write from any authorized source, regardless of rank.
    /// - A stronger source always wins over a weaker one.
    /// - Between equal sources, the higher sequence number wins, so late
    ///   delivery cannot rewind state.
    public static func shouldAccept(
        incoming: CodexSource,
        incomingSeq: UInt64,
        heldBy: CodexSource?,
        heldSeq: UInt64,
        heldIsProvisional: Bool,
        facet: CodexFacet
    ) -> Bool {
        guard let incomingRank = rank(of: incoming, for: facet) else {
            return false
        }
        guard let heldBy else {
            return true
        }
        if heldIsProvisional {
            return true
        }
        guard let heldRank = rank(of: heldBy, for: facet) else {
            return true
        }
        if incomingRank != heldRank {
            return incomingRank < heldRank
        }
        return incomingSeq >= heldSeq
    }
}

/// Cold start has no app-server connection and no hooks yet — the rollout
/// transcript is all there is. Rather than carve an exception into the matrix,
/// the store runs in replay mode: the rollout may fill any facet, but every
/// value it writes is marked provisional and yields to the first authoritative
/// write that follows.
public enum CodexReplayMode: Equatable, Sendable {
    /// Restoring history at launch. The rollout may write any facet, provisionally.
    case replaying
    /// A live source has been heard from. Normal authority rules apply.
    case live
}
