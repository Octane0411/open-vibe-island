import CoreGraphics
import Foundation

@MainActor
final class IdleActivityMonitor {
    private var timer: Timer?
    private let idleThreshold: TimeInterval = 60

    private(set) var isUserAway: Bool = false
    private(set) var idleSeconds: TimeInterval = 0

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        idleSeconds = 0
    }

    private func poll() {
        let seconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: .init(rawValue: ~0)!
        )
        idleSeconds = seconds
        isUserAway = seconds >= idleThreshold
    }
}
