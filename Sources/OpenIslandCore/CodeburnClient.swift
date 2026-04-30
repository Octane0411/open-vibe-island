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

public struct ProcessCodeburnRunner: CodeburnRunner {
    public init() {}

    public func probeVersion() async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codeburn", "--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value
    }

    public func runStatus(timeout: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["codeburn", "status", "--format", "json"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    throw NSError(domain: "codeburn", code: Int(process.terminationStatus))
                }
                return pipe.fileHandleForReading.readDataToEndOfFile()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NSError(domain: "codeburn", code: -1, userInfo: [NSLocalizedDescriptionKey: "timeout"])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
