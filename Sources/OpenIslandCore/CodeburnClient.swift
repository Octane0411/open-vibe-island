import Foundation
import Observation

@MainActor
@Observable
public final class CodeburnClient {
    public private(set) var state: CodeburnState = .notProbed
    private let runner: any CodeburnRunner
    private var inFlight = false
    private var probedVersion: String?
    private var hasProbed = false

    public init(runner: any CodeburnRunner) {
        self.runner = runner
    }

    public func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        if !hasProbed {
            probedVersion = await runner.probeVersion()
            hasProbed = true
            if probedVersion == nil {
                state = .notInstalled
                return
            }
        }
        if probedVersion == nil {
            state = .notInstalled
            return
        }

        do {
            let data = try await runner.runStatus(timeout: 5)
            let snap = try CodeburnSnapshot.parse(statusJSON: data)
            state = .ok(snap)
        } catch {
            state = .unavailable(reason: String(describing: error))
        }
    }
}
