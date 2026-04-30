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
}
