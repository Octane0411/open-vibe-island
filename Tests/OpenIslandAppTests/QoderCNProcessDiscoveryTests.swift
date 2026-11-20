import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// Process discovery for the Qoder CN desktop app. Sessions are hook-managed;
/// discovery reports one whole-app snapshot (ZCode shape) so process-assisted
/// liveness can keep non-ended sessions alive.
struct QoderCNProcessDiscoveryTests {
    @Test
    func discoversQoderCNMainBinaryAsWholeAppSnapshot() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  900 1 ?? /Applications/Qoder CN.app/Contents/MacOS/Qoder CN
                """
            }
            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.tool == .qoderCN)
        #expect(snapshots.first?.terminalApp == "Qoder CN")
    }

    @Test
    func electronHelpersAreNotMistakenForQoderCN() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  903 900 ?? /Applications/Qoder CN.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper
                  904 900 ?? /Applications/Qoder CN.app/Contents/Frameworks/Qoder CN Helper (GPU).app/Contents/MacOS/Qoder CN Helper (GPU)
                """
            }
            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.filter { $0.tool == .qoderCN }.isEmpty)
    }
}
