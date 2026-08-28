import Foundation

/// A facet value together with the provenance needed to arbitrate the next
/// write against it.
public struct CodexFacetSlot<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var writtenBy: CodexSource
    public var seq: UInt64
    public var observedAt: Date
    /// Written during cold-start replay. Yields to the first authoritative write.
    public var isProvisional: Bool

    public init(
        value: Value,
        writtenBy: CodexSource,
        seq: UInt64,
        observedAt: Date,
        isProvisional: Bool
    ) {
        self.value = value
        self.writtenBy = writtenBy
        self.seq = seq
        self.observedAt = observedAt
        self.isProvisional = isProvisional
    }
}

/// The assembled state of one Codex session.
///
/// Each facet is stored independently with its own writer and sequence, so a
/// source that is blind to a dimension simply never touches it. This is the
/// structural fix for the class of bug where a transcript scrape overwrote a
/// user-assigned thread name, or a vanished rollout file marked a live desktop
/// session complete.
public struct CodexSessionFacets: Equatable, Sendable {
    public var sessionKey: String
    public var surface: CodexFacetSlot<CodexSurface>?
    public var workspace: CodexFacetSlot<CodexWorkspace>?
    public var placement: CodexFacetSlot<CodexPlacement>?
    public var lifecycle: CodexFacetSlot<CodexLifecycle>?
    public var actionable: CodexFacetSlot<CodexActionable>?
    public var narrative: CodexFacetSlot<CodexNarrative>?
    public var liveness: CodexFacetSlot<CodexLiveness>?
    public var firstSeenAt: Date
    public var lastUpdatedAt: Date

    public init(sessionKey: String, firstSeenAt: Date, lastUpdatedAt: Date) {
        self.sessionKey = sessionKey
        self.firstSeenAt = firstSeenAt
        self.lastUpdatedAt = lastUpdatedAt
    }

    /// Whether this session should appear in the user-visible list. Subagent
    /// threads and internal daemons are tracked but never surfaced.
    public var isUserVisible: Bool {
        surface?.value.isUserVisible ?? true
    }

    public var isDesktopApp: Bool {
        surface?.value.isDesktopApp ?? false
    }
}

/// Which facets a single observation actually changed.
public struct CodexFacetChange: Equatable, Sendable {
    public var accepted: Set<CodexFacet>
    public var rejected: Set<CodexFacet>
    public var isNewSession: Bool

    public init(
        accepted: Set<CodexFacet> = [],
        rejected: Set<CodexFacet> = [],
        isNewSession: Bool = false
    ) {
        self.accepted = accepted
        self.rejected = rejected
        self.isNewSession = isNewSession
    }

    public var didChange: Bool { !accepted.isEmpty || isNewSession }
}

/// Holds per-session facets and applies observations through the authority
/// matrix.
///
/// The store is intentionally free of policy: it knows how to arbitrate writes
/// but nothing about `AgentEvent` or session presentation. Turning facets into
/// events is `CodexSessionProjector`'s job.
public final class CodexFacetStore: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: CodexSessionFacets] = [:]
    private var replayMode: CodexReplayMode = .replaying
    private let diagnostics: CodexDiagnostics?

    public init(diagnostics: CodexDiagnostics? = nil) {
        self.diagnostics = diagnostics
    }

    /// Leaves cold-start replay. Called on the first app-server connection or
    /// the first hook delivery — after this, rollout writes lose their
    /// blanket permission and every provisional value becomes replaceable.
    public func enterLiveMode() {
        lock.lock()
        replayMode = .live
        lock.unlock()
    }

    public var currentMode: CodexReplayMode {
        lock.lock()
        defer { lock.unlock() }
        return replayMode
    }

    public func session(for key: String) -> CodexSessionFacets? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[key]
    }

    public func allSessions() -> [CodexSessionFacets] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.values)
    }

    public func removeSession(for key: String) {
        lock.lock()
        sessions.removeValue(forKey: key)
        lock.unlock()
    }

    /// Apply one observation, returning which facets it actually changed.
    @discardableResult
    public func apply(
        _ observation: CodexObservation,
        sessionKey: String
    ) -> CodexFacetChange {
        lock.lock()
        defer { lock.unlock() }

        var change = CodexFacetChange()
        var facets: CodexSessionFacets
        if let existing = sessions[sessionKey] {
            facets = existing
        } else {
            facets = CodexSessionFacets(
                sessionKey: sessionKey,
                firstSeenAt: observation.observedAt,
                lastUpdatedAt: observation.observedAt
            )
            change.isNewSession = true
        }

        // During replay the rollout is the only witness available, so it may
        // fill every facet — provisionally.
        let isReplayWrite = replayMode == .replaying && observation.source == .rollout

        func write<Value: Equatable & Sendable>(
            _ facet: CodexFacet,
            _ slot: inout CodexFacetSlot<Value>?,
            _ incoming: Value,
            merge: ((Value, Value) -> Value)? = nil
        ) {
            let authorized = isReplayWrite
                || CodexAuthorityMatrix.canWrite(observation.source, facet)
            guard authorized else {
                change.rejected.insert(facet)
                diagnostics?.recordRejectedWrite(
                    facet: facet.rawValue,
                    attemptedBy: observation.source.displayName,
                    heldBy: slot?.writtenBy.displayName
                )
                return
            }

            let accept = isReplayWrite || CodexAuthorityMatrix.shouldAccept(
                incoming: observation.source,
                incomingSeq: observation.seq,
                heldBy: slot?.writtenBy,
                heldSeq: slot?.seq ?? 0,
                heldIsProvisional: slot?.isProvisional ?? false,
                facet: facet
            )
            guard accept else {
                change.rejected.insert(facet)
                diagnostics?.recordRejectedWrite(
                    facet: facet.rawValue,
                    attemptedBy: observation.source.displayName,
                    heldBy: slot?.writtenBy.displayName
                )
                return
            }

            let resolved: Value
            if let merge, let existing = slot?.value {
                resolved = merge(existing, incoming)
            } else {
                resolved = incoming
            }

            if let existing = slot, existing.value == resolved,
               existing.isProvisional == isReplayWrite {
                // Same value from an equally-or-more authoritative source —
                // refresh provenance without reporting a change.
                slot = CodexFacetSlot(
                    value: resolved,
                    writtenBy: observation.source,
                    seq: observation.seq,
                    observedAt: observation.observedAt,
                    isProvisional: isReplayWrite
                )
                return
            }

            slot = CodexFacetSlot(
                value: resolved,
                writtenBy: observation.source,
                seq: observation.seq,
                observedAt: observation.observedAt,
                isProvisional: isReplayWrite
            )
            change.accepted.insert(facet)
        }

        let patch = observation.patch

        if let surface = patch.surface {
            write(.surface, &facets.surface, surface)
        }
        if let workspace = patch.workspace {
            write(.workspace, &facets.workspace, workspace)
        }
        if let placement = patch.placement {
            write(.placement, &facets.placement, placement)
        }
        if let lifecycle = patch.lifecycle {
            write(.lifecycle, &facets.lifecycle, lifecycle)
        }
        if let actionable = patch.actionable {
            write(.actionable, &facets.actionable, actionable)
        }
        if let narrative = patch.narrative {
            // Narrative arrives in fragments — a title here, a prompt there —
            // so a partial update merges rather than replaces.
            write(.narrative, &facets.narrative, narrative) { existing, incoming in
                existing.merging(incoming)
            }
        }
        if let liveness = patch.liveness {
            write(.liveness, &facets.liveness, liveness)
        }

        if change.didChange {
            facets.lastUpdatedAt = max(facets.lastUpdatedAt, observation.observedAt)
        }
        sessions[sessionKey] = facets
        return change
    }
}
