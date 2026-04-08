import Foundation

/// Shared utility for running shell commands and capturing output.
/// Replaces 4 duplicated implementations across the codebase.
public enum ShellProcess {
    /// Run an executable and return its trimmed stdout, or nil on failure.
    public static func output(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let result = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            return nil
        }

        return result
    }
}
