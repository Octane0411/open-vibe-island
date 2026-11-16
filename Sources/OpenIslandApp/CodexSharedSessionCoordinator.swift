import Foundation
import OpenIslandCore

/// Observes the existing CLI daemon. Listing/reading threads never resumes a
/// conversation, acquires its writer lock, starts a turn, or answers a request.
@MainActor
final class CodexSharedSessionCoordinator {
    var onThreads: (([CodexThread]) -> Void)?
    private var task: Task<Void, Never>?
    private var client: CodexAppServerClient?

    func startIfNeeded() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    if self.client == nil {
                        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
                            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
                        let socket = URL(fileURLWithPath: home).appendingPathComponent("app-server-control/app-server-control.sock")
                        guard FileManager.default.fileExists(atPath: socket.path) else {
                            try await Task.sleep(for: .seconds(10))
                            continue
                        }
                        let client = CodexAppServerClient(usesSharedDaemon: true)
                        self.client = client
                        try await client.start()
                    }
                    if let client = self.client {
                        self.onThreads?(try await client.listLoadedThreads())
                    }
                } catch {
                    self.client?.stop()
                    self.client = nil
                    self.onThreads?([])
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
