import OpenIslandCore

/// Serializes synchronous platform actions off the main actor. Cancellation can
/// skip queued work, but cannot undo an OS action that has already started.
/// There is no suspension between the cancellation check and the action, so a
/// previous action cannot finish after a newer one has completed.
actor TerminalJumpExecutor {
    private let action: @Sendable (JumpTarget) throws -> String

    init(action: @escaping @Sendable (JumpTarget) throws -> String) {
        self.action = action
    }

    func run(_ target: JumpTarget) throws -> String {
        try Task.checkCancellation()
        return try action(target)
    }
}
