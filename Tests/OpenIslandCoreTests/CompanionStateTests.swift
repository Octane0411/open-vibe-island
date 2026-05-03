import Foundation
import Testing
@testable import OpenIslandCore

struct CompanionStateTests {
    @Test
    func noSessionsIsIdle() {
        let s = CompanionState.derive(spotlightPhase: nil, recentlyCompleted: false)
        #expect(s == .idle)
    }

    @Test
    func runningPhaseIsWorking() {
        let s = CompanionState.derive(spotlightPhase: .running, recentlyCompleted: false)
        #expect(s == .working)
    }

    @Test
    func waitingForApprovalIsWaiting() {
        let s = CompanionState.derive(spotlightPhase: .waitingForApproval, recentlyCompleted: false)
        #expect(s == .waiting)
    }

    @Test
    func waitingForAnswerIsWaiting() {
        let s = CompanionState.derive(spotlightPhase: .waitingForAnswer, recentlyCompleted: false)
        #expect(s == .waiting)
    }

    @Test
    func recentlyCompletedIsCelebrating() {
        let s = CompanionState.derive(spotlightPhase: .completed, recentlyCompleted: true)
        #expect(s == .celebrating)
    }

    @Test
    func longCompletedIsIdle() {
        let s = CompanionState.derive(spotlightPhase: .completed, recentlyCompleted: false)
        #expect(s == .idle)
    }

    // MARK: - isWithinCelebratingWindow

    @Test
    func celebratingWindowIsFalseWhenNoCompletion() {
        #expect(!CompanionState.isWithinCelebratingWindow(now: Date(), lastCompletion: nil))
    }

    @Test
    func celebratingWindowIsTrueAtZeroElapsed() {
        let ts = Date()
        #expect(CompanionState.isWithinCelebratingWindow(now: ts, lastCompletion: ts))
    }

    @Test
    func celebratingWindowIsTrueJustBeforeBoundary() {
        let ts = Date()
        let now = ts.addingTimeInterval(CompanionState.celebratingWindow - 0.001)
        #expect(CompanionState.isWithinCelebratingWindow(now: now, lastCompletion: ts))
    }

    @Test
    func celebratingWindowIsFalseAtBoundary() {
        let ts = Date()
        let now = ts.addingTimeInterval(CompanionState.celebratingWindow)
        #expect(!CompanionState.isWithinCelebratingWindow(now: now, lastCompletion: ts))
    }

    @Test
    func celebratingWindowIsFalseLongAfter() {
        let ts = Date()
        let now = ts.addingTimeInterval(CompanionState.celebratingWindow + 100)
        #expect(!CompanionState.isWithinCelebratingWindow(now: now, lastCompletion: ts))
    }

    @Test
    func celebratingWindowRespectsCustomWindow() {
        let ts = Date()
        // Custom 2-second window: still active at 1.5s, expired at 2.0s.
        #expect(CompanionState.isWithinCelebratingWindow(
            now: ts.addingTimeInterval(1.5), lastCompletion: ts, window: 2.0
        ))
        #expect(!CompanionState.isWithinCelebratingWindow(
            now: ts.addingTimeInterval(2.0), lastCompletion: ts, window: 2.0
        ))
    }
}
