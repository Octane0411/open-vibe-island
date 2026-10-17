import Darwin
import Foundation

private struct Configuration {
    var role = "architect"
    var outputPath: String?
    var inputPaths: [String] = []
    var emitStderr = false
    var failureCode: Int32?
    var waitForCancellation = false
    var ignoreTermination = false
    var largeOutputBytes = 0
    var invalidUTF8 = false
    var failOnceDirectory: String?

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--role" where index + 1 < arguments.count:
                role = arguments[index + 1]
                index += 2
            case "--output" where index + 1 < arguments.count:
                outputPath = arguments[index + 1]
                index += 2
            case "--input" where index + 1 < arguments.count:
                inputPaths.append(arguments[index + 1])
                index += 2
            case "--stderr":
                emitStderr = true
                index += 1
            case "--failure-code" where index + 1 < arguments.count:
                failureCode = Int32(arguments[index + 1])
                index += 2
            case "--wait-for-cancellation":
                waitForCancellation = true
                index += 1
            case "--ignore-term":
                ignoreTermination = true
                index += 1
            case "--large-output" where index + 1 < arguments.count:
                largeOutputBytes = Int(arguments[index + 1]) ?? 0
                index += 2
            case "--invalid-utf8":
                invalidUTF8 = true
                index += 1
            case "--fail-once-directory" where index + 1 < arguments.count:
                failOnceDirectory = arguments[index + 1]
                index += 2
            default:
                index += 1
            }
        }
    }
}

@main
private enum OpenIslandProcessFixtureAgent {
    static func main() throws {
        let configuration = Configuration(
            arguments: Array(CommandLine.arguments.dropFirst())
        )
        if configuration.waitForCancellation {
            if configuration.ignoreTermination {
                signal(SIGTERM, SIG_IGN)
            }
            print("fixture role=\(configuration.role) waiting for cancellation")
            fflush(stdout)
            while true { pause() }
        }
        let inputs = try configuration.inputPaths.map { path -> Any in
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONSerialization.jsonObject(with: data)
        }
        if configuration.emitStderr {
            FileHandle.standardError.write(
                Data("fixture diagnostic role=\(configuration.role)\n".utf8)
            )
        }
        if let directory = configuration.failOnceDirectory {
            let marker = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(
                    ".openisland-fixture-\(configuration.role)-failed-once"
                )
            if !FileManager.default.fileExists(atPath: marker.path) {
                try Data("failed-once\n".utf8).write(
                    to: marker,
                    options: .atomic
                )
                FileHandle.standardError.write(
                    Data("scripted fail-once role=\(configuration.role)\n".utf8)
                )
                Darwin.exit(configuration.failureCode ?? 23)
            }
        }
        if configuration.invalidUTF8 {
            FileHandle.standardOutput.write(Data([0x66, 0x80, 0x6f, 0x0a]))
        }
        if configuration.largeOutputBytes > 0 {
            let chunk = Data(repeating: UInt8(ascii: "x"), count: 4_096)
            var remaining = configuration.largeOutputBytes
            while remaining > 0 {
                let count = min(remaining, chunk.count)
                FileHandle.standardOutput.write(chunk.prefix(count))
                remaining -= count
            }
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            print(
                "fixture role=\(configuration.role) inputs=\(inputs.count)"
            )
        }
        if let code = configuration.failureCode,
           configuration.failOnceDirectory == nil {
            FileHandle.standardError.write(
                Data("scripted failure code=\(code)\n".utf8)
            )
            Darwin.exit(code)
        }
        guard let outputPath = configuration.outputPath else {
            Darwin.exit(0)
        }
        let result = deterministicResult(
            role: configuration.role,
            inputs: inputs
        )
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: outputURL, options: .atomic)
    }

    private static func deterministicResult(
        role: String,
        inputs: [Any]
    ) -> [String: Any] {
        switch role {
        case "architect":
            return [
                "agent": role,
                "sections": [
                    "scope",
                    "source-hierarchy",
                    "dose-calculation-requirements",
                    "quality-controls",
                ],
                "status": "complete",
            ]
        case "researcher":
            return [
                "agent": role,
                "inputCount": inputs.count,
                "findings": [
                    ["id": "finding-1", "section": "scope"],
                    ["id": "finding-2", "section": "quality-controls"],
                ],
                "status": "complete",
            ]
        case "graph":
            return [
                "agent": role,
                "inputCount": inputs.count,
                "nodes": ["finding-1", "finding-2"],
                "edges": [["from": "finding-1", "to": "finding-2"]],
                "status": "complete",
            ]
        case "reviewer":
            return [
                "agent": role,
                "inputCount": inputs.count,
                "verdict": "pass",
                "status": "complete",
            ]
        default:
            return [
                "agent": role,
                "inputCount": inputs.count,
                "status": "complete",
            ]
        }
    }
}
