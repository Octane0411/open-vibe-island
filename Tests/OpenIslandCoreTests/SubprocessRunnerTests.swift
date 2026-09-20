import Foundation
import Testing
@testable import OpenIslandCore

struct SubprocessRunnerTests {
    @Test
    func capturesStandardOutput() throws {
        let result = try #require(
            SubprocessRunner.run(executablePath: "/bin/echo", arguments: ["hello runner"])
        )
        #expect(result.exitStatus == 0)
        #expect(result.timedOut == false)
        #expect(
            result.standardOutput?.trimmingCharacters(in: .whitespacesAndNewlines) == "hello runner"
        )
    }

    @Test
    func reportsNonZeroExitStatus() throws {
        let result = try #require(
            SubprocessRunner.run(executablePath: "/usr/bin/false", arguments: [])
        )
        #expect(result.exitStatus != 0)
        #expect(SubprocessRunner.output(executablePath: "/usr/bin/false", arguments: []) == nil)
    }

    @Test
    func killsChildWhenTimeoutElapses() throws {
        let start = Date()
        let result = try #require(
            SubprocessRunner.run(executablePath: "/bin/sleep", arguments: ["5"], timeout: 0.2)
        )
        let elapsed = Date().timeIntervalSince(start)
        #expect(result.timedOut)
        #expect(result.exitStatus != 0)
        #expect(elapsed >= 0.15)
        #expect(elapsed < 2.0)
    }

    @Test
    func drainsBothPipesWithoutDeadlocking() throws {
        // Both streams carry more than a pipe buffer; reading only after the
        // process exits would deadlock here.
        let script = "head -c 150000 /dev/zero | tr '\\0' 'e' 1>&2; head -c 150000 /dev/zero | tr '\\0' 'o'"
        let result = try #require(
            SubprocessRunner.run(executablePath: "/bin/sh", arguments: ["-c", script], timeout: 10)
        )
        #expect(result.exitStatus == 0)
        #expect(result.timedOut == false)
        #expect(result.standardOutput?.count == 150000)
    }

    @Test
    func staysFarBelowFoundationPollingOverhead() {
        // Regression guard: Foundation's Process.waitUntilExit() polls the run
        // loop at ~15 Hz and costs about 67ms per call, so six trivial runs
        // through it take 400ms or more. A spawn path that does not poll the
        // run loop finishes them in tens of milliseconds.
        let start = Date()
        for _ in 0..<6 {
            let result = SubprocessRunner.run(executablePath: "/usr/bin/true", arguments: [])
            #expect(result?.exitStatus == 0)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.3)
    }
}
