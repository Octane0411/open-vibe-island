import Foundation
import Testing
@testable import OpenIslandCore

struct CursorSessionRegistryTests {
    @Test
    func cursorTrackedSessionRecordRejectsEndedAndDemoSessionsForLiveRestore() {
        let liveRecord = CursorTrackedSessionRecord(
            sessionID: "cursor-live-1",
            title: "Cursor · live",
            origin: .live,
            attachmentState: .attached,
            summary: "Working",
            phase: .running,
            updatedAt: .now
        )
        let demoRecord = CursorTrackedSessionRecord(
            sessionID: "cursor-demo-1",
            title: "Cursor · demo",
            origin: .demo,
            attachmentState: .attached,
            summary: "Working",
            phase: .running,
            updatedAt: .now
        )
        let endedRecord = CursorTrackedSessionRecord(
            sessionID: "cursor-ended-1",
            title: "Cursor · ended",
            origin: .live,
            attachmentState: .stale,
            summary: "Finished",
            phase: .completed,
            updatedAt: .now,
            isSessionEnded: true
        )

        #expect(liveRecord.shouldRestoreToLiveState)
        #expect(!demoRecord.shouldRestoreToLiveState)
        #expect(!endedRecord.shouldRestoreToLiveState)
    }
}
