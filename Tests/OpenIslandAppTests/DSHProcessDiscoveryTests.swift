import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// Process discovery for the DeepSeek Harness desktop app. Sessions are
/// hook-managed via the open-island-dsh plugin; discovery reports one
/// whole-app snapshot (ZCode shape) so process-assisted liveness can keep
/// non-ended sessions alive.
struct DSHProcessDiscoveryTests {
    @Test
    func discoversDSHMainBinaryAsWholeAppSnapshot() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  900 1 ?? /Applications/DeepSeek Harness.app/Contents/MacOS/DeepSeek Harness
                """
            }
            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.tool == .dsh)
        #expect(snapshots.first?.terminalApp == "DeepSeek Harness")
    }

    @Test
    func electronHelpersAreNotMistakenForDSH() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  902 900 ?? /Applications/DeepSeek Harness.app/Contents/Frameworks/DeepSeek Harness Helper (Renderer).app/Contents/MacOS/DeepSeek Harness Helper (Renderer)
                """
            }
            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.filter { $0.tool == .dsh }.isEmpty)
    }
}
