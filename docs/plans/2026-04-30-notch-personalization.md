# Notch Personalization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a slot-based widget system for the closed notch — animated companion (left, fixed) plus a configurable widget per slot (right on built-in display; center+right on external) — with project-chip, agent-tool-icon, and `$ spent today` (via shell-out to user-installed `codeburn`) widgets.

**Architecture:** Pure-Swift slot dispatcher + four small SwiftUI views replacing the hard-coded `headerRow` in `IslandPanelView.swift`. Three new core types: `NotchWidgetConfig` (persisted via UserDefaults like the existing `islandPixelShapeStyle`), `ProjectColorRegistry` (FNV-1a hash with per-project override, persisted to Application Support JSON), and `CodeburnClient` (`@Observable` subprocess wrapper behind a `CodeburnRunner` protocol so tests inject fakes). Companion is the existing `IslandPixelGlyph` plus a small overlay layer driven by a pure state machine.

**Tech Stack:** Swift 6.2 · SwiftUI · `@Observable` (Swift Observation) · Swift Testing (`#expect`) · UserDefaults · `Process` for subprocess.

**Reference design:** `docs/plans/2026-04-30-notch-personalization-design.md`

**Branch:** `feat/notch-personalization` (already created)

---

## Conventions for every task

- All tests use **Swift Testing**, not XCTest. Pattern: `import Testing` · `struct Foo { @Test func bar() throws { #expect(...) } }`.
- Run all tests: `swift test`
- Run a single test: `swift test --filter <TestStructName>/<testFunctionName>`
- Type-check without running: `swift build`
- Each task is a single commit. Use Conventional Commits: `feat(scope): …`, `test(scope): …`, `refactor(scope): …`.
- Never skip pre-commit hooks. If a hook fails, fix the cause and create a *new* commit (not `--amend`).
- Stage only the files the task touches — never `git add -A`.

---

## Task 1: `NotchWidgetKind` enum + `NotchWidgetConfig` value type

**Files:**
- Create: `Sources/OpenIslandCore/NotchWidget.swift`
- Create: `Tests/OpenIslandCoreTests/NotchWidgetTests.swift`

**Step 1: Write the failing test**

```swift
// Tests/OpenIslandCoreTests/NotchWidgetTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

struct NotchWidgetTests {
    @Test
    func defaultConfigPreservesLegacyBehavior() {
        let config = NotchWidgetConfig.default
        #expect(config.rightSlot == .sessionCount)
        #expect(config.centerSlotExternal == .none)
    }

    @Test
    func configRoundTripsThroughJSON() throws {
        let original = NotchWidgetConfig(rightSlot: .projectChip, centerSlotExternal: .dollarSpentToday)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NotchWidgetConfig.self, from: encoded)
        #expect(decoded == original)
    }

    @Test
    func widgetKindHasStableRawValues() {
        // Stable raw values matter for UserDefaults persistence across versions.
        #expect(NotchWidgetKind.none.rawValue == "none")
        #expect(NotchWidgetKind.sessionCount.rawValue == "sessionCount")
        #expect(NotchWidgetKind.projectChip.rawValue == "projectChip")
        #expect(NotchWidgetKind.agentToolIcon.rawValue == "agentToolIcon")
        #expect(NotchWidgetKind.dollarSpentToday.rawValue == "dollarSpentToday")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NotchWidgetTests`
Expected: FAIL — `NotchWidgetKind` / `NotchWidgetConfig` not defined.

**Step 3: Write minimal implementation**

```swift
// Sources/OpenIslandCore/NotchWidget.swift
import Foundation

public enum NotchWidgetKind: String, Codable, CaseIterable, Sendable {
    case none
    case sessionCount
    case projectChip
    case agentToolIcon
    case dollarSpentToday
}

public struct NotchWidgetConfig: Codable, Equatable, Sendable {
    public var rightSlot: NotchWidgetKind
    public var centerSlotExternal: NotchWidgetKind

    public init(rightSlot: NotchWidgetKind, centerSlotExternal: NotchWidgetKind) {
        self.rightSlot = rightSlot
        self.centerSlotExternal = centerSlotExternal
    }

    public static let `default` = NotchWidgetConfig(
        rightSlot: .sessionCount,
        centerSlotExternal: .none
    )
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter NotchWidgetTests`
Expected: PASS — 3/3.

**Step 5: Commit**

```bash
git add Sources/OpenIslandCore/NotchWidget.swift Tests/OpenIslandCoreTests/NotchWidgetTests.swift
git commit -m "feat(core): add NotchWidgetKind + NotchWidgetConfig"
```

---

## Task 2: `ProjectColorRegistry` — pure logic + persistence

**Files:**
- Create: `Sources/OpenIslandCore/ProjectColorRegistry.swift`
- Create: `Tests/OpenIslandCoreTests/ProjectColorRegistryTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/OpenIslandCoreTests/ProjectColorRegistryTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

struct ProjectColorRegistryTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("project-colors-\(UUID().uuidString).json")
    }

    @Test
    func sameKeyHashesToSameColorAcrossInstances() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = ProjectColorRegistry(storeURL: url)
        let b = ProjectColorRegistry(storeURL: url)
        #expect(a.color(for: "/Users/x/Repo") == b.color(for: "/Users/x/Repo"))
    }

    @Test
    func differentKeysGetDifferentColors() {
        let registry = ProjectColorRegistry(storeURL: tempURL())
        let c1 = registry.color(for: "/Users/x/Repo")
        let c2 = registry.color(for: "/Users/x/Other")
        #expect(c1 != c2)
    }

    @Test
    func overrideIsPersistedAndReturnedOverHash() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = ProjectColorRegistry(storeURL: url)
        let key = "/Users/x/Repo"
        registry.setColor(.init(red: 0.9, green: 0.1, blue: 0.2), for: key)

        let reloaded = ProjectColorRegistry(storeURL: url)
        let stored = reloaded.color(for: key)
        #expect(abs(stored.red - 0.9) < 0.001)
        #expect(abs(stored.green - 0.1) < 0.001)
        #expect(abs(stored.blue - 0.2) < 0.001)
    }

    @Test
    func resetAllRestoresHashing() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = ProjectColorRegistry(storeURL: url)
        let key = "/Users/x/Repo"
        let original = registry.color(for: key)
        registry.setColor(.init(red: 1, green: 1, blue: 1), for: key)
        registry.resetAll()
        #expect(registry.color(for: key) == original)
    }

    @Test
    func corruptStoreStartsFreshAndDoesNotThrow() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try "this is not json".write(to: url, atomically: true, encoding: .utf8)

        let registry = ProjectColorRegistry(storeURL: url)
        _ = registry.color(for: "/Users/x/Repo")  // must not throw
    }

    @Test
    func pruneRemovesUnreferencedKeys() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = ProjectColorRegistry(storeURL: url)
        _ = registry.color(for: "/a")
        _ = registry.color(for: "/b")
        _ = registry.color(for: "/c")
        registry.pruneUnusedKeys(activePaths: ["/a", "/c"])
        #expect(registry.knownKeys().sorted() == ["/a", "/c"])
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectColorRegistryTests`
Expected: FAIL — `ProjectColorRegistry` not defined.

**Step 3: Write minimal implementation**

```swift
// Sources/OpenIslandCore/ProjectColorRegistry.swift
import Foundation

public struct ProjectColor: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
}

public final class ProjectColorRegistry: @unchecked Sendable {
    private let storeURL: URL
    private var overrides: [String: ProjectColor] = [:]
    private let queue = DispatchQueue(label: "open-island.project-colors")

    public init(storeURL: URL) {
        self.storeURL = storeURL
        self.overrides = Self.load(from: storeURL)
    }

    public func color(for key: String) -> ProjectColor {
        queue.sync {
            if let override = overrides[key] { return override }
            return Self.hashColor(for: key)
        }
    }

    public func setColor(_ color: ProjectColor, for key: String) {
        queue.sync {
            overrides[key] = color
            persist()
        }
    }

    public func resetAll() {
        queue.sync {
            overrides.removeAll()
            persist()
        }
    }

    public func pruneUnusedKeys(activePaths: Set<String>) {
        queue.sync {
            overrides = overrides.filter { activePaths.contains($0.key) }
            persist()
        }
    }

    public func knownKeys() -> [String] {
        queue.sync { Array(overrides.keys) }
    }

    // MARK: - Private

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(overrides)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Persisting is best-effort — corruption recovery handles re-init next launch.
        }
    }

    private static func load(from url: URL) -> [String: ProjectColor] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: ProjectColor].self, from: data)
        } catch {
            return [:]
        }
    }

    /// FNV-1a 64-bit hash → HSL hue (fixed S=0.55, L=0.6) → RGB.
    static func hashColor(for key: String) -> ProjectColor {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let hue = Double(hash % 360) / 360.0
        return hslToRGB(h: hue, s: 0.55, l: 0.6)
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> ProjectColor {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        default:    (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        return ProjectColor(red: r1 + m, green: g1 + m, blue: b1 + m)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ProjectColorRegistryTests`
Expected: PASS — 6/6.

**Step 5: Commit**

```bash
git add Sources/OpenIslandCore/ProjectColorRegistry.swift Tests/OpenIslandCoreTests/ProjectColorRegistryTests.swift
git commit -m "feat(core): add ProjectColorRegistry with hash + override persistence"
```

---

## Task 3: `CodeburnRunner` protocol + `CodeburnSnapshot`

**Files:**
- Create: `Sources/OpenIslandCore/CodeburnTypes.swift`
- Create: `Tests/OpenIslandCoreTests/CodeburnSnapshotTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/OpenIslandCoreTests/CodeburnSnapshotTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

struct CodeburnSnapshotTests {
    @Test
    func parsesValidStatusJSON() throws {
        let json = """
        { "today": { "cost": 3.42, "currency": "USD" },
          "month": { "cost": 87.10, "currency": "USD" } }
        """.data(using: .utf8)!

        let snapshot = try CodeburnSnapshot.parse(statusJSON: json)
        #expect(snapshot.todayCost == 3.42)
        #expect(snapshot.currency == "USD")
    }

    @Test
    func missingTodayCostThrows() {
        let json = "{}".data(using: .utf8)!
        #expect(throws: CodeburnSnapshot.ParseError.self) {
            _ = try CodeburnSnapshot.parse(statusJSON: json)
        }
    }

    @Test
    func malformedJSONThrows() {
        let json = "not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try CodeburnSnapshot.parse(statusJSON: json)
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodeburnSnapshotTests`
Expected: FAIL — `CodeburnSnapshot` not defined.

**Step 3: Write minimal implementation**

```swift
// Sources/OpenIslandCore/CodeburnTypes.swift
import Foundation

public struct CodeburnSnapshot: Equatable, Sendable {
    public var todayCost: Double
    public var currency: String
    public var observedAt: Date

    public init(todayCost: Double, currency: String, observedAt: Date) {
        self.todayCost = todayCost
        self.currency = currency
        self.observedAt = observedAt
    }

    public enum ParseError: Error { case missingField(String) }

    public static func parse(statusJSON: Data, now: Date = Date()) throws -> CodeburnSnapshot {
        let object = try JSONSerialization.jsonObject(with: statusJSON)
        guard let root = object as? [String: Any],
              let today = root["today"] as? [String: Any] else {
            throw ParseError.missingField("today")
        }
        guard let cost = (today["cost"] as? NSNumber)?.doubleValue else {
            throw ParseError.missingField("today.cost")
        }
        let currency = (today["currency"] as? String) ?? "USD"
        return CodeburnSnapshot(todayCost: cost, currency: currency, observedAt: now)
    }
}

public enum CodeburnState: Equatable, Sendable {
    case notProbed
    case notInstalled
    case unavailable(reason: String)
    case ok(CodeburnSnapshot)
}

public protocol CodeburnRunner: Sendable {
    /// Probe whether codeburn is on PATH. Returns version string, or nil.
    func probeVersion() async -> String?
    /// Run `codeburn status --format json`. Returns raw stdout bytes.
    func runStatus(timeout: TimeInterval) async throws -> Data
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter CodeburnSnapshotTests`
Expected: PASS — 3/3.

**Step 5: Commit**

```bash
git add Sources/OpenIslandCore/CodeburnTypes.swift Tests/OpenIslandCoreTests/CodeburnSnapshotTests.swift
git commit -m "feat(core): add CodeburnSnapshot parser + CodeburnRunner protocol"
```

---

## Task 4: `CodeburnClient` state machine (driven by injected runner)

**Files:**
- Create: `Sources/OpenIslandCore/CodeburnClient.swift`
- Create: `Tests/OpenIslandCoreTests/CodeburnClientTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/OpenIslandCoreTests/CodeburnClientTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

actor FakeCodeburnRunner: CodeburnRunner {
    var versionToReturn: String?
    var statusJSONToReturn: Data?
    var statusErrorToThrow: (any Error)?
    var statusCallCount = 0
    var probeCallCount = 0

    init(version: String? = nil, statusJSON: Data? = nil) {
        self.versionToReturn = version
        self.statusJSONToReturn = statusJSON
    }

    func probeVersion() async -> String? { probeCallCount += 1; return versionToReturn }
    func runStatus(timeout: TimeInterval) async throws -> Data {
        statusCallCount += 1
        if let err = statusErrorToThrow { throw err }
        return statusJSONToReturn ?? Data()
    }
    func setStatusError(_ err: any Error) { statusErrorToThrow = err }
    func setStatusJSON(_ data: Data) { statusJSONToReturn = data; statusErrorToThrow = nil }
}

struct CodeburnClientTests {
    private let goodJSON = """
    { "today": { "cost": 1.23, "currency": "USD" } }
    """.data(using: .utf8)!

    @Test
    func absentBinaryYieldsNotInstalled() async {
        let runner = FakeCodeburnRunner(version: nil)
        let client = CodeburnClient(runner: runner)
        await client.refresh()
        #expect(client.state == .notInstalled)
    }

    @Test
    func presentBinaryWithGoodOutputYieldsOk() async {
        let runner = FakeCodeburnRunner(version: "1.0.0", statusJSON: goodJSON)
        let client = CodeburnClient(runner: runner)
        await client.refresh()
        if case .ok(let snap) = client.state {
            #expect(snap.todayCost == 1.23)
        } else {
            Issue.record("expected .ok, got \(client.state)")
        }
    }

    @Test
    func subprocessFailureYieldsUnavailable() async {
        let runner = FakeCodeburnRunner(version: "1.0.0")
        await runner.setStatusError(NSError(domain: "test", code: 1))
        let client = CodeburnClient(runner: runner)
        await client.refresh()
        if case .unavailable = client.state { } else {
            Issue.record("expected .unavailable, got \(client.state)")
        }
    }

    @Test
    func singleFlightDropsOverlappingTicks() async {
        let runner = FakeCodeburnRunner(version: "1.0.0", statusJSON: goodJSON)
        let client = CodeburnClient(runner: runner)
        async let a: Void = client.refresh()
        async let b: Void = client.refresh()
        _ = await (a, b)
        let calls = await runner.statusCallCount
        #expect(calls <= 1)  // single-flight guarantees at most one call
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodeburnClientTests`
Expected: FAIL — `CodeburnClient` not defined.

**Step 3: Write minimal implementation**

```swift
// Sources/OpenIslandCore/CodeburnClient.swift
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
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter CodeburnClientTests`
Expected: PASS — 4/4.

**Step 5: Commit**

```bash
git add Sources/OpenIslandCore/CodeburnClient.swift Tests/OpenIslandCoreTests/CodeburnClientTests.swift
git commit -m "feat(core): add CodeburnClient state machine with fake runner support"
```

---

## Task 5: `ProcessCodeburnRunner` — real subprocess implementation

**Files:**
- Modify: `Sources/OpenIslandCore/CodeburnClient.swift`

**Note:** No tests for this — real subprocess invocation is covered by manual smoke. The runner protocol is what's testable; this is the thin glue.

**Step 1: Append implementation**

```swift
// Append to Sources/OpenIslandCore/CodeburnClient.swift

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
```

**Step 2: Verify it builds**

Run: `swift build`
Expected: success.

**Step 3: Commit**

```bash
git add Sources/OpenIslandCore/CodeburnClient.swift
git commit -m "feat(core): add ProcessCodeburnRunner shelling out to codeburn binary"
```

---

## Task 6: Companion state machine

**Files:**
- Create: `Sources/OpenIslandCore/CompanionState.swift`
- Create: `Tests/OpenIslandCoreTests/CompanionStateTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/OpenIslandCoreTests/CompanionStateTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

struct CompanionStateTests {
    @Test
    func noSessionsIsIdle() {
        let s = CompanionState.derive(spotlightPhase: nil, recentlyCompleted: false)
        #expect(s == .idle)
    }

    @Test
    func runningPhaseIsWorking() {
        let s = CompanionState.derive(spotlightPhase: .running, recentlyCompleted: false)
        #expect(s == .working)
    }

    @Test
    func waitingForApprovalIsWaiting() {
        let s = CompanionState.derive(spotlightPhase: .waitingForApproval, recentlyCompleted: false)
        #expect(s == .waiting)
    }

    @Test
    func waitingForAnswerIsWaiting() {
        let s = CompanionState.derive(spotlightPhase: .waitingForAnswer, recentlyCompleted: false)
        #expect(s == .waiting)
    }

    @Test
    func recentlyCompletedIsCelebrating() {
        let s = CompanionState.derive(spotlightPhase: .completed, recentlyCompleted: true)
        #expect(s == .celebrating)
    }

    @Test
    func longCompletedIsIdle() {
        let s = CompanionState.derive(spotlightPhase: .completed, recentlyCompleted: false)
        #expect(s == .idle)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter CompanionStateTests`
Expected: FAIL — `CompanionState` not defined.

**Step 3: Write minimal implementation**

```swift
// Sources/OpenIslandCore/CompanionState.swift
import Foundation

public enum CompanionState: String, Equatable, Sendable {
    case idle
    case working
    case waiting
    case celebrating

    public static func derive(
        spotlightPhase: SessionPhase?,
        recentlyCompleted: Bool
    ) -> CompanionState {
        guard let phase = spotlightPhase else { return .idle }
        switch phase {
        case .running:
            return .working
        case .waitingForApproval, .waitingForAnswer:
            return .waiting
        case .completed:
            return recentlyCompleted ? .celebrating : .idle
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter CompanionStateTests`
Expected: PASS — 6/6.

**Step 5: Commit**

```bash
git add Sources/OpenIslandCore/CompanionState.swift Tests/OpenIslandCoreTests/CompanionStateTests.swift
git commit -m "feat(core): add CompanionState derivation from session phase"
```

---

## Task 7: Project chip widget view

**Files:**
- Create: `Sources/OpenIslandApp/Views/NotchWidgets/ProjectChipWidget.swift`

**Note:** SwiftUI views aren't unit-tested in this codebase (existing pattern). Manual visual verification later.

**Step 1: Write the implementation**

```swift
// Sources/OpenIslandApp/Views/NotchWidgets/ProjectChipWidget.swift
import SwiftUI
import OpenIslandCore

struct ProjectChipWidget: View {
    let workspaceName: String?
    let workspaceKey: String?
    let registry: ProjectColorRegistry
    let availableWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(swiftUIColor)
                .frame(width: 8, height: 8)

            if let name = workspaceName, availableWidth >= compactThreshold {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: availableWidth, alignment: .trailing)
    }

    private var compactThreshold: CGFloat { 60 }

    private var swiftUIColor: Color {
        guard let key = workspaceKey else {
            return Color.gray.opacity(0.6)
        }
        let c = registry.color(for: key)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
```

**Step 2: Verify it builds**

Run: `swift build`
Expected: success.

**Step 3: Commit**

```bash
git add Sources/OpenIslandApp/Views/NotchWidgets/ProjectChipWidget.swift
git commit -m "feat(app): add ProjectChipWidget view with compact fallback"
```

---

## Task 8: Agent-tool icon widget view

**Files:**
- Create: `Sources/OpenIslandApp/Views/NotchWidgets/AgentToolIconWidget.swift`

**Step 1: Write the implementation**

```swift
// Sources/OpenIslandApp/Views/NotchWidgets/AgentToolIconWidget.swift
import SwiftUI
import OpenIslandCore

struct AgentToolIconWidget: View {
    let tool: AgentTool?

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 16, height: 16)
    }

    /// Map agent tool to SF Symbol. Phase 1 uses generic glyphs; Phase 2 can
    /// swap in branded asset images per agent.
    private var symbolName: String {
        guard let tool else { return "circle.dashed" }
        switch tool {
        case .claude:    return "sparkles"
        case .codex:     return "chevron.left.forwardslash.chevron.right"
        case .cursor:    return "cursorarrow.rays"
        case .gemini:    return "diamond"
        case .opencode:  return "curlybraces"
        case .qoder:     return "wand.and.stars"
        case .qwen:      return "circle.hexagongrid"
        case .factory:   return "hammer"
        case .codebuddy: return "person.2"
        case .kimi:      return "moon.stars"
        @unknown default: return "circle.dashed"
        }
    }

    private var tint: Color {
        guard tool != nil else { return .white.opacity(0.4) }
        return .white.opacity(0.85)
    }
}
```

**Note:** before running, verify the `AgentTool` enum cases match what's in `OpenIslandCore/AgentSession.swift`. Use:

```bash
grep -nE "case \." Sources/OpenIslandCore/AgentSession.swift | grep -A 20 "AgentTool"
```

If a case doesn't exist or there are extras, adjust the switch — the goal is **exhaustiveness**, not symbol-quality.

**Step 2: Verify it builds**

Run: `swift build`
Expected: success.

**Step 3: Commit**

```bash
git add Sources/OpenIslandApp/Views/NotchWidgets/AgentToolIconWidget.swift
git commit -m "feat(app): add AgentToolIconWidget view"
```

---

## Task 9: Dollar-spent widget view (with not-installed graceful path)

**Files:**
- Create: `Sources/OpenIslandApp/Views/NotchWidgets/DollarSpentWidget.swift`

**Step 1: Write the implementation**

```swift
// Sources/OpenIslandApp/Views/NotchWidgets/DollarSpentWidget.swift
import SwiftUI
import OpenIslandCore

struct DollarSpentWidget: View {
    let state: CodeburnState

    var body: some View {
        switch state {
        case .ok(let snap):
            Text(format(snap.todayCost, currency: snap.currency))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

        case .notInstalled, .notProbed:
            Button(action: openInstallURL) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Install codeburn to enable $ tracking")

        case .unavailable:
            Text("$—")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func format(_ cost: Double, currency: String) -> String {
        let symbol = (currency == "USD") ? "$" : ""
        if cost < 10 {
            return String(format: "\(symbol)%.2f", cost)
        }
        return String(format: "\(symbol)%.1f", cost)
    }

    private func openInstallURL() {
        if let url = URL(string: "https://github.com/getagentseal/codeburn#install") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

**Step 2: Verify it builds**

Run: `swift build`
Expected: success.

**Step 3: Commit**

```bash
git add Sources/OpenIslandApp/Views/NotchWidgets/DollarSpentWidget.swift
git commit -m "feat(app): add DollarSpentWidget with graceful install hint"
```

---

## Task 10: Companion overlay view (Phase 1 — overlays on existing avatar)

**Files:**
- Create: `Sources/OpenIslandApp/Views/NotchWidgets/CompanionStateOverlay.swift`

**Step 1: Write the implementation**

```swift
// Sources/OpenIslandApp/Views/NotchWidgets/CompanionStateOverlay.swift
import SwiftUI
import OpenIslandCore

struct CompanionStateOverlay: View {
    let state: CompanionState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            switch state {
            case .idle:
                glyph("zzz", tint: .white.opacity(0.4))
            case .working:
                glyph("gear", tint: .cyan.opacity(0.85))
                    .rotationEffect(.degrees(rotation))
                    .onAppear { animateRotation() }
            case .waiting:
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulseScale)
                    .onAppear { animatePulse() }
            case .celebrating:
                glyph("sparkles", tint: .yellow)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityLabel(accessibilityText)
    }

    @State private var rotation: Double = 0
    @State private var pulseScale: CGFloat = 1

    private func glyph(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(tint)
    }

    private func animateRotation() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private func animatePulse() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.4
        }
    }

    private var accessibilityText: String {
        switch state {
        case .idle: "Idle"
        case .working: "Working"
        case .waiting: "Waiting for input"
        case .celebrating: "Just finished"
        }
    }
}
```

**Step 2: Verify it builds**

Run: `swift build`
Expected: success.

**Step 3: Commit**

```bash
git add Sources/OpenIslandApp/Views/NotchWidgets/CompanionStateOverlay.swift
git commit -m "feat(app): add Phase 1 CompanionStateOverlay (overlays on existing avatar)"
```

---

## Task 11: `NotchSlotHost` dispatcher

**Files:**
- Create: `Sources/OpenIslandApp/Views/NotchWidgets/NotchSlotHost.swift`

**Step 1: Write the implementation**

```swift
// Sources/OpenIslandApp/Views/NotchWidgets/NotchSlotHost.swift
import SwiftUI
import OpenIslandCore

struct NotchSlotHost: View {
    let kind: NotchWidgetKind
    let availableWidth: CGFloat

    // Inputs each widget may need. Pass through from IslandPanelView.
    let liveSessionCount: Int
    let spotlightTool: AgentTool?
    let spotlightWorkspaceName: String?
    let spotlightWorkspaceKey: String?
    let projectColorRegistry: ProjectColorRegistry
    let codeburnState: CodeburnState

    var body: some View {
        switch kind {
        case .none:
            Color.clear.frame(width: availableWidth, height: 1)
        case .sessionCount:
            ClosedCountBadge(liveCount: liveSessionCount, tint: .white.opacity(0.85))
        case .projectChip:
            ProjectChipWidget(
                workspaceName: spotlightWorkspaceName,
                workspaceKey: spotlightWorkspaceKey,
                registry: projectColorRegistry,
                availableWidth: availableWidth
            )
        case .agentToolIcon:
            AgentToolIconWidget(tool: spotlightTool)
        case .dollarSpentToday:
            DollarSpentWidget(state: codeburnState)
        }
    }
}
```

**Step 2: Verify it builds**

Run: `swift build`
Expected: success — including `ClosedCountBadge` resolves (already exists in `IslandPanelView.swift`; if it's defined nested, lift it to file scope OR reference the existing definition; do whatever makes the compiler happy with the smallest surface change).

**Step 3: Commit**

```bash
git add Sources/OpenIslandApp/Views/NotchWidgets/NotchSlotHost.swift
git commit -m "feat(app): add NotchSlotHost dispatcher view"
```

---

## Task 12: Wire `NotchWidgetConfig` + `ProjectColorRegistry` + `CodeburnClient` into `AppModel`

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift`

**Step 1: Read the current `AppModel.swift` UserDefaults pattern**

```bash
grep -nE "DefaultsKey|UserDefaults.standard.set|UserDefaults.standard.bool" Sources/OpenIslandApp/AppModel.swift | head -20
```

Mirror the pattern used by `islandPixelShapeStyle` (a `didSet` that writes the rawValue).

**Step 2: Add fields**

Add to `AppModel`:

```swift
// Sources/OpenIslandApp/AppModel.swift — additions

private static let notchWidgetConfigDefaultsKey = "notch.widgetConfig"

var notchWidgetConfig: NotchWidgetConfig = .default {
    didSet {
        guard notchWidgetConfig != oldValue else { return }
        if let data = try? JSONEncoder().encode(notchWidgetConfig) {
            UserDefaults.standard.set(data, forKey: Self.notchWidgetConfigDefaultsKey)
        }
        // Lazily start codeburn polling when the $ widget is selected.
        updateCodeburnPolling()
    }
}

let projectColorRegistry: ProjectColorRegistry = {
    let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!.appendingPathComponent("OpenIsland", isDirectory: true)
    return ProjectColorRegistry(storeURL: supportDir.appendingPathComponent("project-colors.json"))
}()

private(set) var codeburnClient: CodeburnClient? = nil
private var codeburnTimerTask: Task<Void, Never>? = nil
```

In the AppModel `init` (or whatever loads other UserDefaults values):

```swift
if let data = UserDefaults.standard.data(forKey: Self.notchWidgetConfigDefaultsKey),
   let decoded = try? JSONDecoder().decode(NotchWidgetConfig.self, from: data) {
    notchWidgetConfig = decoded
}
updateCodeburnPolling()
```

Add helper methods:

```swift
private func updateCodeburnPolling() {
    let needsCodeburn = notchWidgetConfig.rightSlot == .dollarSpentToday
        || notchWidgetConfig.centerSlotExternal == .dollarSpentToday
    if needsCodeburn {
        if codeburnClient == nil {
            codeburnClient = CodeburnClient(runner: ProcessCodeburnRunner())
        }
        startCodeburnTimerIfNeeded()
    } else {
        codeburnTimerTask?.cancel()
        codeburnTimerTask = nil
    }
}

private func startCodeburnTimerIfNeeded() {
    guard codeburnTimerTask == nil, let client = codeburnClient else { return }
    codeburnTimerTask = Task { @MainActor in
        while !Task.isCancelled {
            await client.refresh()
            try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s
        }
    }
}
```

**Step 3: Verify it builds**

Run: `swift build`
Expected: success.

**Step 4: Commit**

```bash
git add Sources/OpenIslandApp/AppModel.swift
git commit -m "feat(app): wire NotchWidgetConfig, ProjectColorRegistry, CodeburnClient into AppModel"
```

---

## Task 13: Refactor `headerRow` in `IslandPanelView.swift` to use slots

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift` (around lines 358–417 — the closed-state `headerRow` body)

**Approach:** This is the riskiest task. Do the refactor in one tight pass. Keep the existing left-side island-icon block exactly as it is for now (companion overlay is layered later). Replace **only** the right-side `ClosedCountBadge` with a `NotchSlotHost(kind: model.notchWidgetConfig.rightSlot, ...)`.

**Step 1: Identify the right-side block to replace**

In current `headerRow`:

```swift
if hasClosedPresence {
    let attentionBalanceWidth: CGFloat = closedSpotlightSession?.phase.requiresAttention == true ? 18 : 0
    ClosedCountBadge(
        liveCount: model.liveSessionCount,
        tint: closedSpotlightSession?.phase.requiresAttention == true ? .orange : scoutTint
    )
    .matchedGeometryEffect(id: "right-indicator", in: notchNamespace, isSource: true)
    .frame(width: max(sideWidth, countBadgeWidth) + attentionBalanceWidth)
}
```

**Step 2: Replace with**

```swift
if hasClosedPresence {
    let attentionBalanceWidth: CGFloat = closedSpotlightSession?.phase.requiresAttention == true ? 18 : 0
    let slotWidth = max(sideWidth, countBadgeWidth) + attentionBalanceWidth
    NotchSlotHost(
        kind: model.notchWidgetConfig.rightSlot,
        availableWidth: slotWidth,
        liveSessionCount: model.liveSessionCount,
        spotlightTool: closedSpotlightSession?.tool,
        spotlightWorkspaceName: closedSpotlightSession?.jumpTarget?.workspaceName,
        spotlightWorkspaceKey: closedSpotlightSession?.jumpTarget?.workingDirectory
            ?? closedSpotlightSession?.jumpTarget?.workspaceName,
        projectColorRegistry: model.projectColorRegistry,
        codeburnState: model.codeburnClient?.state ?? .notProbed
    )
    .matchedGeometryEffect(id: "right-indicator", in: notchNamespace, isSource: true)
    .frame(width: slotWidth)
}
```

**Step 3: Verify the existing default rendering is unchanged**

Run: `swift build`
Expected: success.

Run the app (or its preview harness) and confirm: with `notchWidgetConfig.rightSlot == .sessionCount` (the default), the closed notch looks identical to before. The existing `matchedGeometryEffect` + `frame` still apply.

**Step 4: Commit**

```bash
git add Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "refactor(app): route closed-notch right slot through NotchSlotHost"
```

---

## Task 14: Add center-slot rendering for external displays

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift` (the section around `isExternalDisplayPlacement` and the existing center black bar)

**Step 1: Locate the center-bar block**

Find where the black center rectangle is rendered (currently around `Rectangle().fill(Color.black).frame(width: closedNotchWidth - NotchShape.closedTopRadius + (isPopping ? 18 : 0))`).

**Step 2: Overlay a `NotchSlotHost` on the black bar when on an external display**

Wrap or `.overlay` the existing center rectangle with a center-slot host, but only when `isExternalDisplayPlacement` is true:

```swift
} else {
    Rectangle()
        .fill(Color.black)
        .frame(width: closedNotchWidth - NotchShape.closedTopRadius + (isPopping ? 18 : 0))
        .overlay(
            ZStack {
                CentralActivityLabel(
                    toolName: closedSpotlightSession?.currentToolName,
                    preview: closedSpotlightSession?.currentCommandPreviewText,
                    isVisible: isExternalDisplayPlacement
                        && hasClosedPresence
                        && model.notchWidgetConfig.centerSlotExternal == .none
                )

                if isExternalDisplayPlacement && hasClosedPresence
                    && model.notchWidgetConfig.centerSlotExternal != .none {
                    NotchSlotHost(
                        kind: model.notchWidgetConfig.centerSlotExternal,
                        availableWidth: closedNotchWidth - NotchShape.closedTopRadius - 24,
                        liveSessionCount: model.liveSessionCount,
                        spotlightTool: closedSpotlightSession?.tool,
                        spotlightWorkspaceName: closedSpotlightSession?.jumpTarget?.workspaceName,
                        spotlightWorkspaceKey: closedSpotlightSession?.jumpTarget?.workingDirectory
                            ?? closedSpotlightSession?.jumpTarget?.workspaceName,
                        projectColorRegistry: model.projectColorRegistry,
                        codeburnState: model.codeburnClient?.state ?? .notProbed
                    )
                }
            }
        )
}
```

The key invariant: if center slot is `.none`, the existing `CentralActivityLabel` keeps showing (zero behavior change). If a widget is picked, the activity label hides and the widget takes its place.

**Step 3: Verify it builds**

Run: `swift build`
Expected: success.

**Step 4: Commit**

```bash
git add Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat(app): render center-slot widget on external displays"
```

---

## Task 15: Layer `CompanionStateOverlay` on the existing left-side island icon

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift` (left-side block in `headerRow` — the `IslandPixelGlyph` / `OpenIslandIcon` area)

**Step 1: Compute the companion state**

Before the `headerRow` body, derive the state:

```swift
private var companionState: CompanionState {
    let recentlyCompleted = (model.lastCompletionTimestamp.map { Date().timeIntervalSince($0) < 8 }) ?? false
    return CompanionState.derive(
        spotlightPhase: closedSpotlightSession?.phase,
        recentlyCompleted: recentlyCompleted
    )
}
```

(`lastCompletionTimestamp` may not exist — if not, add it to AppModel as a `Date?` updated whenever a session transitions to `.completed`. Do that as part of this task.)

**Step 2: Add an overlay to the icon block (custom appearance mode only — Phase 1)**

Where today the code renders:

```swift
if model.isCustomAppearance {
    IslandPixelGlyph(...)
        .matchedGeometryEffect(...)
} else {
    OpenIslandIcon(...)
        .matchedGeometryEffect(...)
}
```

Wrap the custom branch in a ZStack adding the overlay:

```swift
if model.isCustomAppearance {
    ZStack(alignment: .bottomTrailing) {
        IslandPixelGlyph(
            tint: scoutTint,
            style: model.islandPixelShapeStyle,
            isAnimating: hasClosedActivity,
            customAvatarImage: model.customAvatarImage
        )
        .matchedGeometryEffect(id: "island-icon", in: notchNamespace, isSource: true)

        CompanionStateOverlay(state: companionState)
            .offset(x: 2, y: 2)
    }
} else {
    OpenIslandIcon(size: 14, isAnimating: hasClosedActivity, tint: scoutTint)
        .matchedGeometryEffect(id: "island-icon", in: notchNamespace, isSource: true)
}
```

This restricts overlays to the custom-appearance path — preserving the default look, per the design.

**Step 3: Verify it builds**

Run: `swift build`
Expected: success.

**Step 4: Commit**

```bash
git add Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat(app): layer CompanionStateOverlay on custom-avatar island icon"
```

---

## Task 16: Settings UI — "Notch widgets" section

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`
- Modify: `Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings` (or the equivalent `.strings` file used by `LanguageManager`)
- Modify: `Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/OpenIslandApp/Resources/zh-Hant.lproj/Localizable.strings`

**Step 1: Find the localization file format**

```bash
ls Sources/OpenIslandApp/Resources/en.lproj/
```

Open one existing `.strings` (or `.json`) file and mirror its format for the new keys.

**Step 2: Add localization keys** (English shown; mirror in zh-Hans / zh-Hant — translations can be the English string for now, marked `TODO: translate`)

```
"settings.notchWidgets.title" = "Notch widgets";
"settings.notchWidgets.rightSlot" = "Right slot";
"settings.notchWidgets.centerSlot" = "Center slot";
"settings.notchWidgets.centerSlotHint" = "External displays only";
"settings.notchWidgets.kind.none" = "None";
"settings.notchWidgets.kind.sessionCount" = "Session count";
"settings.notchWidgets.kind.projectChip" = "Project chip";
"settings.notchWidgets.kind.agentToolIcon" = "Agent tool icon";
"settings.notchWidgets.kind.dollarSpentToday" = "$ spent today";
"settings.notchWidgets.codeburnHint" = "Requires codeburn — click to install";
```

**Step 3: Add the new section to `AppearanceSettingsPane`**

Append after the "Status colors" section:

```swift
Section(lang.t("settings.notchWidgets.title")) {
    Picker(lang.t("settings.notchWidgets.rightSlot"), selection: Binding(
        get: { model.notchWidgetConfig.rightSlot },
        set: { newValue in
            model.notchWidgetConfig = NotchWidgetConfig(
                rightSlot: newValue,
                centerSlotExternal: model.notchWidgetConfig.centerSlotExternal
            )
        }
    )) {
        ForEach(NotchWidgetKind.allCases, id: \.self) { kind in
            Text(localizedKindName(kind)).tag(kind)
        }
    }

    Picker(lang.t("settings.notchWidgets.centerSlot"), selection: Binding(
        get: { model.notchWidgetConfig.centerSlotExternal },
        set: { newValue in
            model.notchWidgetConfig = NotchWidgetConfig(
                rightSlot: model.notchWidgetConfig.rightSlot,
                centerSlotExternal: newValue
            )
        }
    )) {
        ForEach(NotchWidgetKind.allCases, id: \.self) { kind in
            Text(localizedKindName(kind)).tag(kind)
        }
    }
    Text(lang.t("settings.notchWidgets.centerSlotHint"))
        .font(.caption)
        .foregroundStyle(.secondary)
}

private func localizedKindName(_ kind: NotchWidgetKind) -> String {
    switch kind {
    case .none:             return lang.t("settings.notchWidgets.kind.none")
    case .sessionCount:     return lang.t("settings.notchWidgets.kind.sessionCount")
    case .projectChip:      return lang.t("settings.notchWidgets.kind.projectChip")
    case .agentToolIcon:    return lang.t("settings.notchWidgets.kind.agentToolIcon")
    case .dollarSpentToday: return lang.t("settings.notchWidgets.kind.dollarSpentToday")
    }
}
```

**Step 4: Verify it builds**

Run: `swift build`
Expected: success.

**Step 5: Commit**

```bash
git add Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift Sources/OpenIslandApp/Resources/
git commit -m "feat(app): add Notch widgets settings section"
```

---

## Task 17: Settings UI — "Project colors" subsection

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`
- Modify: localization `.strings` files (en, zh-Hans, zh-Hant)

**Step 1: Add localization keys**

```
"settings.projectColors.title" = "Project colors";
"settings.projectColors.help" = "Auto-assigned. Click any swatch to pick a different color.";
"settings.projectColors.resetAll" = "Reset all to auto";
"settings.projectColors.removeUnused" = "Remove unused";
```

**Step 2: Add a collapsible section**

```swift
DisclosureGroup(lang.t("settings.projectColors.title")) {
    ForEach(model.projectColorRegistry.knownKeys().sorted(), id: \.self) { key in
        HStack {
            Circle()
                .fill(swiftUIColor(model.projectColorRegistry.color(for: key)))
                .frame(width: 14, height: 14)
                .onTapGesture {
                    presentColorPicker(for: key)
                }
            Text((key as NSString).lastPathComponent)
                .font(.system(size: 12))
            Spacer()
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    HStack {
        Button(lang.t("settings.projectColors.resetAll")) {
            model.projectColorRegistry.resetAll()
        }
        Button(lang.t("settings.projectColors.removeUnused")) {
            let active = Set(model.activeWorkspaceKeys)  // expose this on AppModel
            model.projectColorRegistry.pruneUnusedKeys(activePaths: active)
        }
    }
    Text(lang.t("settings.projectColors.help"))
        .font(.caption)
        .foregroundStyle(.secondary)
}

private func swiftUIColor(_ c: ProjectColor) -> Color {
    Color(red: c.red, green: c.green, blue: c.blue)
}

private func presentColorPicker(for key: String) {
    // Phase 1: use NSColorPanel; Phase 2 can switch to the 12-swatch grid
    // described in the design doc.
    let panel = NSColorPanel.shared
    panel.setTarget(self)
    panel.orderFront(nil)
    // Wiring NSColorPanel into a struct view requires an NSObject helper —
    // keep this as a TODO if the framing is awkward; for the first pass,
    // just advance to a stub button "Pick color…" and tackle full wiring in
    // a follow-up commit.
}
```

**Note:** if `NSColorPanel` integration is fiddly within SwiftUI here, ship Phase 1 with a 12-preset-swatch grid (no `NSColorPanel`) and defer free-form custom color to a follow-up. Don't block the section on the color picker — the swatch grid is sufficient and matches the design's "12 preset swatches + Custom…" plan.

`model.activeWorkspaceKeys` doesn't exist yet — add it as a computed property on `AppModel`:

```swift
var activeWorkspaceKeys: Set<String> {
    Set(sessions.compactMap { $0.jumpTarget?.workingDirectory ?? $0.jumpTarget?.workspaceName })
}
```

**Step 3: Verify it builds**

Run: `swift build`
Expected: success.

**Step 4: Commit**

```bash
git add Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/Resources/
git commit -m "feat(app): add Project colors settings subsection"
```

---

## Task 18: Manual smoke test + PR-ready cleanup

**Files:** none (verification only) — but read `docs/plans/2026-04-30-notch-personalization-design.md` and walk through every "Manual smoke (documented in PR)" item.

**Step 1: Build a release binary**

```bash
swift build -c release
```

Expected: success, no warnings introduced by this branch.

**Step 2: Run the app and verify**

- Default install: closed notch looks identical to `main`. ✓
- Settings → Appearance → Notch widgets → switch right slot to "Project chip": the right side shows `● <workspace>`. ✓
- Switch right slot to "$ spent today" with codeburn **not** installed: shows install ⓘ button, clicking opens GitHub. ✓
- `npm i -g codeburn`, wait 30s: widget populates with `$X.YZ`. ✓
- `npm uninstall -g codeburn`, wait 30s: widget falls back to install ⓘ without crash. ✓
- Plug in an external display (non-notched): center slot picker becomes editable; pick "Agent tool icon"; verify it renders only on the external surface. ✓
- Trigger an approval prompt in any agent: companion overlay (custom appearance mode only) shows the orange pulsing dot. ✓
- Complete a session: companion shows sparkle for ~8s, decays to idle. ✓

**Step 3: Run the full test suite one more time**

```bash
swift test
```

Expected: all green, including all tests added in this plan.

**Step 4: Push the branch**

```bash
git push -u origin feat/notch-personalization
```

**Step 5: Open a draft PR upstream (optional — your fork's call)**

Use the existing PR template if any (`gh pr view` style). Body should reference the design doc and list the manual smoke results.

---

## Out of scope for this plan (Phase 2 work)

- Curated CC0 pixel-pet library replacing the Phase 1 overlays. Will use the `pixel-art-sprite-sourcing` skill to source frames and a `sprite-sheet-animation-pipeline` to drive them through the same `CompanionState` contract.
- 12-swatch preset color picker UI (if Task 17 ships with `NSColorPanel`-only or a stub).
- `$` cost surfacing in the **opened** island.
- Rate-limit gauge widget (`.rateLimitGauge` enum case is reserved but not implemented in Phase 1).
