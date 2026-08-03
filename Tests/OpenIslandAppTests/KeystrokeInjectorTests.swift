import Testing
@testable import OpenIslandApp

struct KeystrokeInjectorTests {
    @Test
    func testDefaultInjectorPostsCmdShiftRightBracketWithoutCrashing() {
        // We can't observe actual OS-level CGEvent delivery in a unit test,
        // but constructing and posting the event without throwing/crashing
        // covers the init-time correctness of the keycode and flags.
        let injector = DefaultKeystrokeInjector()
        injector.sendCmdShiftRightBracket()  // no assertion — if this crashes the test fails
    }

    @Test
    func testSpyKeystrokerRecordsCalls() {
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
