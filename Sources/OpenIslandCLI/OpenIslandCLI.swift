import Darwin
import Foundation
import OpenIslandCore

@main
struct OpenIslandCLI {
    static func main() async {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGINT) { _ in
            Darwin._exit(GraphCLIExitCode.interrupted.rawValue)
        }

        let stdout = GraphCLIFileDescriptorSink(
            fileDescriptor: STDOUT_FILENO
        )
        let stderr = GraphCLIFileDescriptorSink(
            fileDescriptor: STDERR_FILENO
        )

        do {
            let environment = ProcessInfo.processInfo.environment
            let databasePath = try environment[
                "OPENISLAND_GRAPH_DATABASE_PATH"
            ] ?? SQLiteGraphExecutionStore.defaultDatabasePath()
            let store = try SQLiteGraphExecutionStore(
                databasePath: databasePath
            )
            let inspector = DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: store
            )
            let context = GraphCLIContextDiscovery.discover(
                environment: environment,
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let runner = GraphCLICommandRunner(
                inspector: inspector,
                stdout: stdout,
                stderr: stderr,
                context: context,
                telemetry: OSLogGraphCLITelemetrySink(),
                isOutputTTY: isatty(STDOUT_FILENO) == 1
            )
            let code = await runner.run(
                arguments: Array(CommandLine.arguments.dropFirst())
            )
            Darwin.exit(code.rawValue)
        } catch {
            _ = stderr.write(
                Data(
                    "error[persistence]: \(error.localizedDescription)\n"
                        .utf8
                )
            )
            Darwin.exit(GraphCLIExitCode.persistenceFailure.rawValue)
        }
    }
}
