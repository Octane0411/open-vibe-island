import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// Process discovery for the WorkBuddy desktop app. Sessions are hook-managed;
/// discovery reports one whole-app snapshot (ZCode shape) so process-assisted
/// liveness can keep non-ended sessions alive.
struct WorkBuddyProcessDiscoveryTests {
    @Test
    func discoversWorkBuddyMainBinaryAsWholeAppSnapshot() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  900 1 ?? /Applications/WorkBuddy.app/Contents/MacOS/WorkBuddy
                """
            }
            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.count == 1)
        #expect(snapshots.first?.tool == .workBuddy)
        #expect(snapshots.first?.terminalApp == "WorkBuddy")
    }

    @Test
    func electronHelpersAreNotMistakenForWorkBuddy() {
        let discovery = ActiveAgentProcessDiscovery { executablePath, arguments in
            if executablePath == "/bin/ps" {
                return """
                  903 900 ?? /Applications/WorkBuddy.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper
                  904 900 ?? /Applications/WorkBuddy.app/Contents/Frameworks/WorkBuddy Helper (GPU).app/Contents/MacOS/WorkBuddy Helper (GPU)
                """
            }
            return nil
        }

        let snapshots = discovery.discover()

        #expect(snapshots.filter { $0.tool == .workBuddy }.isEmpty)
    }
}
