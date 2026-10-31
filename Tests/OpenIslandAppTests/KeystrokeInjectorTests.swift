import Foundation
import Testing
@testable import OpenIslandApp

@Suite(.serialized)
struct KeystrokeInjectorTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OPEN_ISLAND_RUN_WARP_TAB_INTEGRATION"] == "1"))
    func liveWarpTabAdvanceSmokeTest() {
        // Explicit opt-in only: activates Warp and clicks its next-tab menu.
        // Run in an isolated macOS account; this is a manual smoke check.
        let injector = DefaultKeystrokeInjector()
        injector.sendCmdShiftRightBracket()  // no XCTAssert — if this crashes the test fails
    }

    @Test
    func spyKeystrokerRecordsCalls() {
        let spy = KeystrokeInjectorSpy()
        spy.sendCmdShiftRightBracket()
        spy.sendCmdShiftRightBracket()
        #expect(spy.callCount == 2)
    }
}

final class KeystrokeInjectorSpy: KeystrokeInjector, @unchecked Sendable {
    var callCount = 0
    func sendCmdShiftRightBracket() {
        callCount += 1
    }
}
