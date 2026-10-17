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
            let processRuntimeRoot: URL
            if let configuredRoot = environment[
                "OPENISLAND_PROCESS_RUNTIME_ROOT"
            ] {
                processRuntimeRoot = URL(
                    fileURLWithPath: configuredRoot,
                    isDirectory: true
                )
            } else {
                processRuntimeRoot = try GraphLocalProcessLaunchStore
                    .defaultRootURL()
            }
            let launchStore = try GraphLocalProcessLaunchStore(
                rootURL: processRuntimeRoot
            )
            let executor = SupervisedLocalProcessExecutor(
                launchStore: launchStore
            )
            let inspector = DefaultGraphTemporalInspector(
                readStore: store,
                snapshotStore: store,
                evidenceSource: GraphLocalProcessEvidenceSource(
                    launchStore: launchStore
                )
            )
            let mutator = DefaultGraphMutationService(
                eventStore: store,
                readStore: store
            )
            let orchestrator = DefaultGraphOrchestrationService(
                eventStore: store,
                schedulingRepository: DefaultGraphSchedulingRepository(
                    eventStore: store
                ),
                executorRepository: DefaultGraphExecutorRepository(
                    eventStore: store
                ),
                executor: executor,
                confirmationPolicy: LocalProcessExecutionConfirmationPolicy()
            )
            let context = GraphCLIContextDiscovery.discover(
                environment: environment,
                workingDirectory: FileManager.default.currentDirectoryPath
            )
            let runner = GraphCLICommandRunner(
                inspector: inspector,
                mutator: mutator,
                orchestrator: orchestrator,
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
