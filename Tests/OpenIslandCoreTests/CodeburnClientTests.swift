import Foundation
import Testing
@testable import OpenIslandCore

actor FakeCodeburnRunner: CodeburnRunner {
    var versionToReturn: String?
    var statusJSONToReturn: Data?
    var statusErrorToThrow: (any Error)?
    var statusCallCount = 0
    var probeCallCount = 0

    init(version: String? = nil, statusJSON: Data? = nil) {
        self.versionToReturn = version
        self.statusJSONToReturn = statusJSON
    }

    func probeVersion() async -> String? { probeCallCount += 1; return versionToReturn }
    func runStatus(timeout: TimeInterval) async throws -> Data {
        statusCallCount += 1
        if let err = statusErrorToThrow { throw err }
        return statusJSONToReturn ?? Data()
    }
    func setStatusError(_ err: any Error) { statusErrorToThrow = err }
    func setStatusJSON(_ data: Data) { statusJSONToReturn = data; statusErrorToThrow = nil }
}

struct CodeburnClientTests {
    private let goodJSON = """
    { "today": { "cost": 1.23, "currency": "USD" } }
    """.data(using: .utf8)!

    @Test
    func absentBinaryYieldsNotInstalled() async {
        let runner = FakeCodeburnRunner(version: nil)
        let client = await CodeburnClient(runner: runner)
        await client.refresh()
        let state = await client.state
        #expect(state == .notInstalled)
    }

    @Test
    func presentBinaryWithGoodOutputYieldsOk() async {
        let runner = FakeCodeburnRunner(version: "1.0.0", statusJSON: goodJSON)
        let client = await CodeburnClient(runner: runner)
        await client.refresh()
        let state = await client.state
        if case .ok(let snap) = state {
            #expect(snap.todayCost == 1.23)
        } else {
            Issue.record("expected .ok, got \(state)")
        }
    }

    @Test
    func subprocessFailureYieldsUnavailable() async {
        let runner = FakeCodeburnRunner(version: "1.0.0")
        await runner.setStatusError(NSError(domain: "test", code: 1))
        let client = await CodeburnClient(runner: runner)
        await client.refresh()
        let state = await client.state
        if case .unavailable = state { } else {
            Issue.record("expected .unavailable, got \(state)")
        }
    }

    @Test
    func singleFlightDropsOverlappingTicks() async {
        let runner = FakeCodeburnRunner(version: "1.0.0", statusJSON: goodJSON)
        let client = await CodeburnClient(runner: runner)
        async let a: Void = client.refresh()
        async let b: Void = client.refresh()
        _ = await (a, b)
        let calls = await runner.statusCallCount
        #expect(calls <= 1)
    }
}
