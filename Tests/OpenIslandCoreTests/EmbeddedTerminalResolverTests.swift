import Foundation
import Testing
@testable import OpenIslandCore

struct EmbeddedTerminalResolverTests {

    // MARK: - resolveHostContext

    @Test
    func detectsVSCodeAncestor() {
        // hook CLI (1000) → claude (900) → zsh (500) →
        // Code Helper (Plugin) (300) → Code Helper (250) →
        // Electron (200) → Visual Studio Code (100).
        let parents: [pid_t: pid_t] = [
            900: 500,
            500: 300,
            300: 250,
            250: 200,
            200: 100,
            100: 1,
        ]
        let commands: [pid_t: String] = [
            900: "claude",
            500: "-zsh",
            300: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)",
            250: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper",
            200: "/Applications/Visual Studio Code.app/Contents/Frameworks/Electron Framework.framework/Versions/A/Electron",
            100: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
            1: "launchd",
        ]

        let ctx = EmbeddedTerminalResolver.resolveHostContext(
            startingFrom: 900,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        // The walker stops at the FIRST ancestor whose command classifies.
        // For a tree where every helper carries the VS Code .app path,
        // that's the immediate parent of zsh (300). The shellPID is the
        // last pid before that — 500 (zsh).
        #expect(ctx?.host == .vscodeFamily(bundleID: "com.microsoft.VSCode", displayName: "VS Code"))
        #expect(ctx?.hostPID == 300)
        #expect(ctx?.shellPID == 500)
    }

    @Test
    func detectsCursorByBundlePathNotBinaryName() {
        // Cursor's binary inside Contents/MacOS/ is also named "Cursor",
        // but the discriminator that matters is the .app path — which is
        // what classify() looks at. A naive binary-name match would
        // confuse Cursor with VS Code (both ship Electron-based helpers
        // named "Code Helper"). Pin the path-based dispatch.
        let parents: [pid_t: pid_t] = [
            900: 500,
            500: 200,
            200: 1,
        ]
        let commands: [pid_t: String] = [
            900: "claude",
            500: "-zsh",
            200: "/Applications/Cursor.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper",
            1: "launchd",
        ]

        let ctx = EmbeddedTerminalResolver.resolveHostContext(
            startingFrom: 900,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        #expect(ctx?.host == .vscodeFamily(
            bundleID: "com.todesktop.230313mzl4w4u92",
            displayName: "Cursor"
        ))
    }

    @Test
    func detectsObsidianAncestor() {
        // Obsidian is the case the resolver fundamentally exists to
        // cover — its terminal plugin doesn't set TERM_PROGRAM, so
        // env-var inference returns nil and the process tree is the
        // only signal.
        let parents: [pid_t: pid_t] = [
            900: 500,
            500: 200,
            200: 1,
        ]
        let commands: [pid_t: String] = [
            900: "claude",
            500: "-zsh",
            200: "/Applications/Obsidian.app/Contents/MacOS/Obsidian",
            1: "launchd",
        ]

        let ctx = EmbeddedTerminalResolver.resolveHostContext(
            startingFrom: 900,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        #expect(ctx?.host == .obsidian)
        #expect(ctx?.hostPID == 200)
        #expect(ctx?.shellPID == 500)
    }

    @Test
    func detectsJetBrainsGoLand() {
        let parents: [pid_t: pid_t] = [
            900: 500,
            500: 200,
            200: 1,
        ]
        let commands: [pid_t: String] = [
            900: "claude",
            500: "-zsh",
            200: "/Applications/GoLand.app/Contents/MacOS/goland",
            1: "launchd",
        ]

        let ctx = EmbeddedTerminalResolver.resolveHostContext(
            startingFrom: 900,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        #expect(ctx?.host == .jetbrains(bundleID: "com.jetbrains.goland", displayName: "GoLand"))
    }

    @Test
    func returnsNilWhenAncestorChainIsAStandaloneTerminal() {
        // Ghostty-hosted claude — must return nil so the env-var
        // inference path stays in charge. The resolver is a fallback,
        // not a competing classifier.
        let parents: [pid_t: pid_t] = [
            900: 500,
            500: 150,
            150: 1,
        ]
        let commands: [pid_t: String] = [
            900: "claude",
            500: "-zsh",
            150: "/Applications/Ghostty.app/Contents/MacOS/ghostty",
            1: "launchd",
        ]

        let ctx = EmbeddedTerminalResolver.resolveHostContext(
            startingFrom: 900,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        #expect(ctx == nil)
    }

    @Test
    func capsWalkDepthToPreventInfiniteLoops() {
        // A broken `ps` chain that cycles forever must terminate the walk
        // via the depth cap, not loop.
        let parents: [pid_t: pid_t] = [100: 200, 200: 100]
        let commands: [pid_t: String] = [:]

        let ctx = EmbeddedTerminalResolver.resolveHostContext(
            startingFrom: 100,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        #expect(ctx == nil)
    }

    @Test
    func returnsNilWhenAncestorIsLaunchd() {
        // Process inherited by launchd (e.g. backgrounded shell). No
        // app ancestor exists — the walker must return nil rather than
        // misclassifying.
        let parents: [pid_t: pid_t] = [900: 1]
        let commands: [pid_t: String] = [
            900: "claude",
            1: "launchd",
        ]

        let ctx = EmbeddedTerminalResolver.resolveHostContext(
            startingFrom: 900,
            parentPIDProvider: { parents[$0] },
            commandProvider: { commands[$0] }
        )

        #expect(ctx == nil)
    }

    // MARK: - classify

    @Test
    func classifyDistinguishesVSCodeFromInsiders() {
        // Insiders contains "code.app" in some helper paths but the
        // outer `.app` is `Visual Studio Code - Insiders.app`. The
        // Insiders check must run before the generic VS Code check.
        #expect(
            EmbeddedTerminalResolver.classify(
                command: "/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Electron"
            )
            == .vscodeFamily(bundleID: "com.microsoft.VSCodeInsiders", displayName: "VS Code Insiders")
        )
    }

    @Test
    func classifyDistinguishesTraeFromTraeCN() {
        #expect(
            EmbeddedTerminalResolver.classify(
                command: "/Applications/Trae CN.app/Contents/MacOS/Trae"
            )
            == .vscodeFamily(bundleID: "cn.trae.app", displayName: "Trae")
        )
        #expect(
            EmbeddedTerminalResolver.classify(
                command: "/Applications/Trae.app/Contents/MacOS/Trae"
            )
            == .vscodeFamily(bundleID: "com.trae.app", displayName: "Trae")
        )
    }

    @Test
    func classifyIgnoresStandaloneTerminals() {
        // The resolver is intentionally narrow — terminals like Ghostty,
        // Terminal.app, Warp, etc. must not be classified as embedded
        // hosts even though they too are .app bundles. They're handled
        // by the existing terminal-app dispatch path.
        #expect(EmbeddedTerminalResolver.classify(
            command: "/Applications/Ghostty.app/Contents/MacOS/ghostty"
        ) == nil)
        #expect(EmbeddedTerminalResolver.classify(
            command: "/Applications/Warp.app/Contents/MacOS/stable"
        ) == nil)
        #expect(EmbeddedTerminalResolver.classify(
            command: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
        ) == nil)
    }

    @Test
    func classifyIsCaseInsensitive() {
        // `ps` output is normally lowercase, but pin the case-insensitive
        // match so a future capitalization change doesn't silently break
        // detection.
        #expect(
            EmbeddedTerminalResolver.classify(
                command: "/APPLICATIONS/CURSOR.APP/Contents/MacOS/Cursor"
            )
            == .vscodeFamily(bundleID: "com.todesktop.230313mzl4w4u92", displayName: "Cursor")
        )
    }
}
