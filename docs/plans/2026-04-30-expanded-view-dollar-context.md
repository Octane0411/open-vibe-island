# Expanded View — `$` Today + Context-Left Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `$` today pill to the opened-island header and a per-Claude-session context-left bar+number badge to each row in the expanded session list.

**Architecture:** Pure-Swift core types (`ContextUsage`, `ContextWindowTable`, `ContextUsageReader`) parse Claude transcript JSONLs in-memory. A `@MainActor @Observable ContextUsageRegistry` on `AppModel` caches per-session usage and watches transcript files via `DispatchSourceFileSystemObject` for live updates. Two small SwiftUI views (`DollarTodayPill`, `ContextLeftBadge`) render the data; `DollarTodayPill` reuses the existing `CodeburnClient` from the closed-notch work via a new `headerNeedsCodeburn` flag that participates in `updateCodeburnPolling()`'s lifecycle decision.

**Tech Stack:** Swift 6.2 · SwiftUI · `@Observable` · Swift Testing (`#expect`) · `Foundation.JSONSerialization` · `DispatchSourceFileSystemObject` for FSEvents-style watching.

**Reference design:** `docs/plans/2026-04-30-expanded-view-dollar-context-design.md`

**Branch:** continue on `feat/notch-personalization` (already up).

---

## Conventions for every task

- Swift Testing (`import Testing` / `@Test` / `#expect`), not XCTest.
- Run all tests: `swift test`.
- Run one test struct: `swift test --filter <StructName>`.
- Type-check only: `swift build`.
- One commit per task. Conventional Commits: `feat(scope):`, `test(scope):`, `refactor(scope):`.
- Stage only the files the task touches — never `git add -A` (avoids picking up the regenerated `Assets/Brand/**.png` that `launch-dev-app.sh` creates).
- Don't `--amend` if a hook fails; fix and create a new commit.

---

## Task 1: `ContextWindowTable` — model name → context window size

**Files:**
- Create: `Sources/OpenIslandCore/ContextUsage.swift` (this task adds the table only; later tasks extend the file)
- Create: `Tests/OpenIslandCoreTests/ContextWindowTableTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/OpenIslandCoreTests/ContextWindowTableTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

struct ContextWindowTableTests {
    @Test
    func opus47Returns200K() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7") == 200_000)
    }

    @Test
    func opus47With1mSuffixReturns1M() {
        #expect(ContextWindowTable.window(for: "claude-opus-4-7[1m]") == 1_000_000)
    }

    @Test
    func sonnetReturns200K() {
        #expect(ContextWindowTable.window(for: "claude-sonnet-4-6") == 200_000)
    }

    @Test
    func haikuReturns200K() {
        #expect(ContextWindowTable.window(for: "claude-haiku-4-5-20251001") == 200_000)
    }

    @Test
    func unknownModelReturns200KDefault() {
        #expect(ContextWindowTable.window(for: "some-future-model") == 200_000)
    }

    @Test
    func emptyOrNilReturns200KDefault() {
        #expect(ContextWindowTable.window(for: "") == 200_000)
        #expect(ContextWindowTable.window(for: nil) == 200_000)
    }
}
```

**Step 2: Run test — expect fail**

`swift test --filter ContextWindowTableTests` → FAIL (`ContextWindowTable` not defined).

**Step 3: Write minimal implementation**

```swift
// Sources/OpenIslandCore/ContextUsage.swift
import Foundation

public enum ContextWindowTable {
    public static let defaultWindow: Int = 200_000

    /// Returns the model's context window in tokens. Detects `[1m]` suffix
    /// for the 1M-context variant (e.g. `claude-opus-4-7[1m]`). Falls back
    /// to `defaultWindow` for unknown models or nil/empty input.
    public static func window(for model: String?) -> Int {
        guard let model, !model.isEmpty else { return defaultWindow }
        if model.hasSuffix("[1m]") { return 1_000_000 }
        // All known Claude models have 200K windows in Phase 1. The default
        // covers them and any future model we haven't pinned.
        return defaultWindow
    }
}
```

**Step 4: Run test — expect 6/6 PASS**

`swift test --filter ContextWindowTableTests`

**Step 5: Commit**

```bash
git add Sources/OpenIslandCore/ContextUsage.swift Tests/OpenIslandCoreTests/ContextWindowTableTests.swift
git commit -m "feat(core): add ContextWindowTable with 1m suffix detection"
```

---

## Task 2: `ContextUsage` + `ContextUsageReader.parse(transcriptData:)`

**Files:**
- Modify: `Sources/OpenIslandCore/ContextUsage.swift` (append)
- Create: `Tests/OpenIslandCoreTests/ContextUsageReaderTests.swift`

**Step 1: Write the failing tests**

```swift
// Tests/OpenIslandCoreTests/ContextUsageReaderTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

struct ContextUsageReaderTests {
    private func data(_ s: String) -> Data { s.data(using: .utf8)! }

    @Test
    func parsesLastAssistantUsageBlock() throws {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":1000,"cache_read_input_tokens":500,"cache_creation_input_tokens":2500,"output_tokens":50}}}"#
        ].joined(separator: "\n")
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(lines)))
        #expect(usage.used == 4000)
        #expect(usage.window == 200_000)
    }

    @Test
    func skipsNonAssistantTurnsScanningBackwards() throws {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":1}}}"#,
            #"{"type":"queue-operation","operation":"enqueue"}"#,
            #"{"type":"user","message":{"role":"user","content":"q"}}"#
        ].joined(separator: "\n")
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(lines)))
        #expect(usage.used == 100)
    }

    @Test
    func returnsNilWhenNoAssistantUsage() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"queue-operation","operation":"dequeue"}"#
        ].joined(separator: "\n")
        #expect(ContextUsageReader.parse(transcriptData: data(lines)) == nil)
    }

    @Test
    func handlesMissingCacheFields() throws {
        let line = #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":150,"output_tokens":5}}}"#
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(line)))
        #expect(usage.used == 150)
    }

    @Test
    func skipsMalformedLines() throws {
        let lines = [
            "this is not json",
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":42}}}"#,
            "another garbage line"
        ].joined(separator: "\n")
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(lines)))
        #expect(usage.used == 42)
    }

    @Test
    func detects1mVariantWindow() throws {
        let line = #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7[1m]","usage":{"input_tokens":300000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":1}}}"#
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(line)))
        #expect(usage.used == 300_000)
        #expect(usage.window == 1_000_000)
        #expect(abs(usage.percentLeft - 70.0) < 0.01)
    }

    @Test
    func picksLatestAssistantTurnNotEarlier() throws {
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":100,"output_tokens":1}}}"#,
            #"{"type":"user","message":{"role":"user","content":"more"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-7","usage":{"input_tokens":2000,"output_tokens":50}}}"#
        ].joined(separator: "\n")
        let usage = try #require(ContextUsageReader.parse(transcriptData: data(lines)))
        #expect(usage.used == 2000)
    }
}
```

**Step 2: Run test — expect fail**

`swift test --filter ContextUsageReaderTests` → FAIL (`ContextUsage` / `ContextUsageReader` not defined).

**Step 3: Append minimal implementation**

Append to `Sources/OpenIslandCore/ContextUsage.swift`:

```swift

public struct ContextUsage: Equatable, Sendable {
    public var used: Int
    public var window: Int

    public init(used: Int, window: Int) {
        self.used = used
        self.window = window
    }

    public var percentUsed: Double {
        guard window > 0 else { return 0 }
        return min(100, Double(used) / Double(window) * 100)
    }

    public var percentLeft: Double {
        max(0, 100 - percentUsed)
    }
}

public enum ContextUsageReader {
    /// Parses a Claude transcript (JSONL) and returns the most recent
    /// assistant turn's context-usage snapshot. Returns nil if no
    /// assistant turn with a `usage` block exists. Malformed lines are
    /// skipped silently.
    public static func parse(transcriptData: Data) -> ContextUsage? {
        guard let text = String(data: transcriptData, encoding: .utf8) else {
            return nil
        }
        // Scan forwards, keep the most recent valid assistant-with-usage line.
        // (Forwards scanning is fine for in-memory data; the file wrapper
        // tails the last 64KB so the input is bounded.)
        var latest: ContextUsage?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData),
                  let root = object as? [String: Any],
                  (root["type"] as? String) == "assistant",
                  let message = root["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else {
                continue
            }
            let input = (usage["input_tokens"] as? NSNumber)?.intValue ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? NSNumber)?.intValue ?? 0
            let used = input + cacheRead + cacheCreate
            let window = ContextWindowTable.window(for: message["model"] as? String)
            latest = ContextUsage(used: used, window: window)
        }
        return latest
    }
}
```

**Step 4: Run test — expect 7/7 PASS**

`swift test --filter ContextUsageReaderTests`

**Step 5: Commit**

```bash
git add Sources/OpenIslandCore/ContextUsage.swift Tests/OpenIslandCoreTests/ContextUsageReaderTests.swift
git commit -m "feat(core): add ContextUsage + ContextUsageReader.parse"
```

---

## Task 3: `ContextUsageReader.read(transcriptPath:)` — file wrapper

**Files:**
- Modify: `Sources/OpenIslandCore/ContextUsage.swift` (append)

No tests — manual smoke covers real file IO. Logic is a thin tail-read wrapper around the parser.

**Step 1: Append**

```swift

extension ContextUsageReader {
    /// Maximum bytes to read from the tail of the transcript when looking
    /// for the last assistant-with-usage line. 64KB covers ~hundreds of
    /// turns; we extend to 256KB if no usage block is found.
    static let primaryTailBytes = 64 * 1024
    static let extendedTailBytes = 256 * 1024

    /// Reads the tail of the transcript file and returns the most recent
    /// context usage snapshot. Returns nil if the file is missing,
    /// unreadable, or contains no assistant-with-usage line in the
    /// extended tail window.
    public static func read(transcriptPath: String) -> ContextUsage? {
        if let usage = readTail(path: transcriptPath, bytes: primaryTailBytes) {
            return usage
        }
        return readTail(path: transcriptPath, bytes: extendedTailBytes)
    }

    private static func readTail(path: String, bytes: Int) -> ContextUsage? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        return parse(transcriptData: data)
    }
}
```

**Step 2: Verify build**

`swift build` → success.

**Step 3: Commit**

```bash
git add Sources/OpenIslandCore/ContextUsage.swift
git commit -m "feat(core): add ContextUsageReader.read(transcriptPath:) tail-reader"
```

---

## Task 4: `ContextUsageRegistry` — in-memory cache (no watcher yet)

**Files:**
- Create: `Sources/OpenIslandCore/ContextUsageRegistry.swift`
- Create: `Tests/OpenIslandCoreTests/ContextUsageRegistryTests.swift`

The registry takes a reader closure for test injection — no FS in tests.

**Step 1: Write the failing tests**

```swift
// Tests/OpenIslandCoreTests/ContextUsageRegistryTests.swift
import Foundation
import Testing
@testable import OpenIslandCore

@MainActor
struct ContextUsageRegistryTests {
    @Test
    func cacheHitDoesNotReParse() async {
        var calls = 0
        let registry = ContextUsageRegistry(reader: { _ in
            calls += 1
            return ContextUsage(used: 100, window: 200_000)
        })
        registry.recordUsage(sessionID: "s1", transcriptPath: "/tmp/a.jsonl")
        _ = registry.usage(for: "s1")
        _ = registry.usage(for: "s1")
        #expect(calls == 1)
    }

    @Test
    func recordOverwritesPreviousValueForSession() {
        var values = [100, 500]
        let registry = ContextUsageRegistry(reader: { _ in
            ContextUsage(used: values.removeFirst(), window: 200_000)
        })
        registry.recordUsage(sessionID: "s1", transcriptPath: "/tmp/a.jsonl")
        #expect(registry.usage(for: "s1")?.used == 100)
        registry.invalidate(sessionID: "s1")
        registry.recordUsage(sessionID: "s1", transcriptPath: "/tmp/a.jsonl")
        #expect(registry.usage(for: "s1")?.used == 500)
    }

    @Test
    func pruneRemovesOnlyInactiveSessions() {
        let registry = ContextUsageRegistry(reader: { _ in
            ContextUsage(used: 1, window: 200_000)
        })
        registry.recordUsage(sessionID: "a", transcriptPath: "/tmp/a.jsonl")
        registry.recordUsage(sessionID: "b", transcriptPath: "/tmp/b.jsonl")
        registry.recordUsage(sessionID: "c", transcriptPath: "/tmp/c.jsonl")
        registry.prune(activeSessionIDs: ["a", "c"])
        #expect(registry.usage(for: "a") != nil)
        #expect(registry.usage(for: "b") == nil)
        #expect(registry.usage(for: "c") != nil)
    }

    @Test
    func unknownSessionReturnsNil() {
        let registry = ContextUsageRegistry(reader: { _ in nil })
        #expect(registry.usage(for: "missing") == nil)
    }
}
```

**Step 2: Run test — expect fail**

`swift test --filter ContextUsageRegistryTests` → FAIL.

**Step 3: Write minimal implementation**

```swift
// Sources/OpenIslandCore/ContextUsageRegistry.swift
import Foundation
import Observation

/// Caches per-session ContextUsage values for SwiftUI views. The reader
/// closure is injected so tests don't touch the file system. File-watching
/// is added in a follow-up task.
@MainActor
@Observable
public final class ContextUsageRegistry {
    private var cache: [String: ContextUsage] = [:]
    private var paths: [String: String] = [:]
    private let reader: (String) -> ContextUsage?

    public init(reader: @escaping (String) -> ContextUsage? = ContextUsageReader.read(transcriptPath:)) {
        self.reader = reader
    }

    /// Reads the transcript at `transcriptPath` and stores the result for
    /// `sessionID`. If the read returns nil, no entry is stored.
    public func recordUsage(sessionID: String, transcriptPath: String) {
        paths[sessionID] = transcriptPath
        if let usage = reader(transcriptPath) {
            cache[sessionID] = usage
        }
    }

    public func usage(for sessionID: String) -> ContextUsage? {
        cache[sessionID]
    }

    /// Drops the cached value (forcing the next `recordUsage` to re-read).
    public func invalidate(sessionID: String) {
        cache.removeValue(forKey: sessionID)
    }

    /// Removes any entries not present in the active set.
    public func prune(activeSessionIDs: Set<String>) {
        cache = cache.filter { activeSessionIDs.contains($0.key) }
        paths = paths.filter { activeSessionIDs.contains($0.key) }
    }
}
```

**Step 4: Run test — expect 4/4 PASS**

`swift test --filter ContextUsageRegistryTests`

**Step 5: Commit**

```bash
git add Sources/OpenIslandCore/ContextUsageRegistry.swift Tests/OpenIslandCoreTests/ContextUsageRegistryTests.swift
git commit -m "feat(core): add ContextUsageRegistry in-memory cache"
```

---

## Task 5: File-mod watcher in `ContextUsageRegistry`

**Files:**
- Modify: `Sources/OpenIslandCore/ContextUsageRegistry.swift` (append watcher logic)

No tests — file watcher behavior is covered by manual smoke. The contract added here is: when the file at a recorded `transcriptPath` is modified, the registry re-reads it and updates the cached entry. A 200ms debounce prevents storms.

**Step 1: Append watcher fields and lifecycle**

Modify the registry to install/cancel `DispatchSourceFileSystemObject` watchers as `recordUsage` and `prune` are called.

```swift
// Add as fields:
private var watchers: [String: DispatchSourceFileSystemObject] = [:]
private var debounceTasks: [String: Task<Void, Never>] = [:]

// In recordUsage(sessionID:transcriptPath:), after reader call:
installWatcher(sessionID: sessionID, transcriptPath: transcriptPath)

// In invalidate(sessionID:), in prune(activeSessionIDs:):
cancelWatcher(sessionID: sessionID)   // for invalidate
// for prune: iterate dropped keys and cancelWatcher each

// New private methods:
private func installWatcher(sessionID: String, transcriptPath: String) {
    cancelWatcher(sessionID: sessionID)
    let fd = open(transcriptPath, O_EVTONLY)
    guard fd >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write, .extend, .delete, .rename],
        queue: .global(qos: .utility)
    )
    source.setEventHandler { [weak self] in
        Task { @MainActor [weak self] in
            self?.scheduleRefresh(sessionID: sessionID, transcriptPath: transcriptPath)
        }
    }
    source.setCancelHandler { close(fd) }
    source.resume()
    watchers[sessionID] = source
}

private func cancelWatcher(sessionID: String) {
    watchers.removeValue(forKey: sessionID)?.cancel()
    debounceTasks.removeValue(forKey: sessionID)?.cancel()
}

private func scheduleRefresh(sessionID: String, transcriptPath: String) {
    debounceTasks.removeValue(forKey: sessionID)?.cancel()
    debounceTasks[sessionID] = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled, let self else { return }
        if let usage = self.reader(transcriptPath) {
            self.cache[sessionID] = usage
        }
    }
}
```

Update `prune(activeSessionIDs:)` to also cancel watchers for removed keys:

```swift
public func prune(activeSessionIDs: Set<String>) {
    let removed = cache.keys.filter { !activeSessionIDs.contains($0) }
    for id in removed { cancelWatcher(sessionID: id) }
    cache = cache.filter { activeSessionIDs.contains($0.key) }
    paths = paths.filter { activeSessionIDs.contains($0.key) }
}
```

**Step 2: Verify build**

`swift build` → success.

**Step 3: Verify existing tests still pass**

`swift test --filter ContextUsageRegistryTests` → 4/4 still pass (the injected reader path doesn't touch `installWatcher` because tests use fake paths; `open()` returning -1 is the gate).

Actually `open("/tmp/a.jsonl", O_EVTONLY)` may succeed if `/tmp/a.jsonl` exists from prior tests. To make tests robust, harden `installWatcher` to skip if the path doesn't exist:

```swift
private func installWatcher(sessionID: String, transcriptPath: String) {
    cancelWatcher(sessionID: sessionID)
    guard FileManager.default.fileExists(atPath: transcriptPath) else { return }
    let fd = open(transcriptPath, O_EVTONLY)
    guard fd >= 0 else { return }
    // ... rest
}
```

Re-run tests after that adjustment.

**Step 4: Commit**

```bash
git add Sources/OpenIslandCore/ContextUsageRegistry.swift
git commit -m "feat(core): add transcript file watcher to ContextUsageRegistry"
```

---

## Task 6: `ContextLeftBadge` view

**Files:**
- Create: `Sources/OpenIslandApp/Views/ContextLeftBadge.swift`

No unit tests for SwiftUI views in this codebase. Layout sanity tests live in Task 7.

**Step 1: Write the implementation**

```swift
// Sources/OpenIslandApp/Views/ContextLeftBadge.swift
import SwiftUI
import OpenIslandCore

struct ContextLeftBadge: View {
    let usage: ContextUsage

    private static let barWidth: CGFloat = 18
    private static let barHeight: CGFloat = 4

    var body: some View {
        if usage.percentLeft < 1 {
            // Below 1% — single red dot variant.
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.white.opacity(0.04), in: Capsule())
                .accessibilityLabel("\(Int(usage.percentLeft.rounded()))% context left")
        } else {
            HStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: Self.barWidth, height: Self.barHeight)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fillColor)
                        .frame(width: fillWidth, height: Self.barHeight)
                }
                Text("\(Int(usage.percentLeft.rounded()))%")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.04), in: Capsule())
            .accessibilityLabel("\(Int(usage.percentLeft.rounded()))% context left")
        }
    }

    var fillWidth: CGFloat {
        let used = max(0, min(100, usage.percentUsed))
        let raw = Self.barWidth * CGFloat(used / 100)
        return used > 0 ? max(2, raw) : 0
    }

    var fillColor: Color {
        let left = usage.percentLeft
        if left > 50 { return .green }
        if left > 20 { return .yellow }
        if left > 10 { return .orange }
        return .red
    }
}
```

**Step 2: Verify build**

`swift build` → success.

**Step 3: Commit**

```bash
git add Sources/OpenIslandApp/Views/ContextLeftBadge.swift
git commit -m "feat(app): add ContextLeftBadge view (bar + percent)"
```

---

## Task 7: `ContextLeftBadge` layout-sanity tests

**Files:**
- Create: `Tests/OpenIslandAppTests/ContextLeftBadgeTests.swift`

These tests exercise the pure-math properties of the view (fill width, color thresholds) by reading them directly via `@testable import`. The view's body is not snapshot-tested.

To make the math observable, expose the helpers via the existing `var fillColor` / `var fillWidth` properties — they're already declared without `private` modifier (matches what we wrote in Task 6).

**Step 1: Write the tests**

```swift
// Tests/OpenIslandAppTests/ContextLeftBadgeTests.swift
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct ContextLeftBadgeTests {
    @Test
    func fillWidthIsZeroWhenNothingUsed() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 0, window: 200_000))
        #expect(b.fillWidth == 0)
    }

    @Test
    func fillWidthHasMinimumSliverWhenAnyUsed() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 100, window: 200_000))
        #expect(b.fillWidth >= 2)
    }

    @Test
    func fillWidthIsBarWidthAtFull() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 200_000, window: 200_000))
        #expect(b.fillWidth == 18)
    }

    @Test
    func colorIsGreenAbove50PercentLeft() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 60_000, window: 200_000))
        #expect(b.fillColor == .green)
    }

    @Test
    func colorIsYellowBetween20And50() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 140_000, window: 200_000))
        #expect(b.fillColor == .yellow)
    }

    @Test
    func colorIsOrangeBetween10And20() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 175_000, window: 200_000))
        #expect(b.fillColor == .orange)
    }

    @Test
    func colorIsRedAtOrBelow10PercentLeft() {
        let b = ContextLeftBadge(usage: ContextUsage(used: 195_000, window: 200_000))
        #expect(b.fillColor == .red)
    }
}
```

**Step 2: Run tests — expect 7/7 PASS**

`swift test --filter ContextLeftBadgeTests`

If `Color` equality is finicky (Swift may not derive `Equatable` for `Color` reliably), assert via a private `enum BadgeFillColor { case green, yellow, orange, red }` exposed on the view instead. If that's needed, refactor `fillColor` to return that enum and add a `colorView` computed property that maps it to `Color` for the body.

**Step 3: Commit**

```bash
git add Tests/OpenIslandAppTests/ContextLeftBadgeTests.swift
# include the view file if you had to refactor fillColor to an enum
git commit -m "test(app): ContextLeftBadge fill width + color thresholds"
```

---

## Task 8: Wire `ContextUsageRegistry` into `AppModel` + reconcile lifecycle

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift`

**Step 1: Add the registry property**

Find a good spot near `projectColorRegistry` (added in Task 12 of the previous plan). Add:

```swift
let contextUsageRegistry = ContextUsageRegistry()
```

**Step 2: Hook into session reconciliation**

Find the AppModel function that processes session state changes (look for `state.sessions` mutations or a `reconcile`/`refresh`-style function). The most reliable point is the place that already receives session list updates from `BridgeServer`. Add at the end of that path:

```swift
let activeIDs = Set(state.sessions.map(\.id))
contextUsageRegistry.prune(activeSessionIDs: activeIDs)

for session in state.sessions {
    guard let path = session.claudeMetadata?.transcriptPath else { continue }
    if contextUsageRegistry.usage(for: session.id) == nil {
        contextUsageRegistry.recordUsage(sessionID: session.id, transcriptPath: path)
    }
}
```

If you can't find a single reconcile point cleanly, add the same logic in a small helper `func refreshContextUsageRegistry()` and call it from wherever `state.sessions` is assigned. The goal is: every time the session list changes, prune dropped sessions and record new Claude sessions.

**Step 3: Verify build + tests**

`swift build` → success.
`swift test` → expect green (no new failures).

**Step 4: Commit**

```bash
git add Sources/OpenIslandApp/AppModel.swift
git commit -m "feat(app): wire ContextUsageRegistry into AppModel session reconciliation"
```

---

## Task 9: Render `ContextLeftBadge` inside `IslandSessionRow`

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`

**Step 1: Pass the registry down**

`IslandSessionRow` is a `private struct` near line 1144. It currently has no model dependency for context usage. Two options:

(a) Add a new property `var contextUsage: ContextUsage?` and pass it from the parent's `IslandSessionRow(...)` call sites (lines 686, 715).
(b) Pass the whole registry and look up by `session.id`.

Pick (a) — leaves the row pure, easier to debug, no runtime lookup at render time.

**Edit at the row struct (around line 1144):** Add a new property:

```swift
var contextUsage: ContextUsage? = nil
```

**Edit each call site** (`IslandSessionRow(...)` invocations near lines 686 and 715):

```swift
IslandSessionRow(
    session: session,
    referenceDate: now,
    // ... existing args ...
    contextUsage: model.contextUsageRegistry.usage(for: session.id),
    // ... rest ...
)
```

**Step 2: Insert the badge in the right-side HStack**

In `rowBody(...)`, find the right-side `HStack(spacing: 6)` (around lines 1182-1194). Insert `ContextLeftBadge` **before** the `compactBadge(session.spotlightAgeBadge, presence: presence)` line, gated by:

```swift
if presence != .inactive, let usage = contextUsage {
    ContextLeftBadge(usage: usage)
}
```

The `presence != .inactive` guard makes the badge disappear on stale rows, matching the design.

**Step 3: Verify build + tests + visual**

`swift build` → success.
`swift test` → green.

Then run the dev app:
```bash
zsh scripts/launch-dev-app.sh --skip-setup
```

In the running app, expand the island and confirm:
- Active Claude sessions show a bar+percent badge.
- Codex / Cursor / Gemini sessions show no badge.
- Inactive (stale) rows don't render the badge.

**Step 4: Commit**

```bash
git add Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat(app): render ContextLeftBadge in expanded session rows"
```

---

## Task 10: `headerNeedsCodeburn` flag — extend `updateCodeburnPolling()`

**Files:**
- Modify: `Sources/OpenIslandApp/AppModel.swift`

The existing `updateCodeburnPolling()` (added in the closed-notch work) decides whether to start the codeburn subprocess timer based purely on slot config. The header pill is a third consumer; it needs to tell AppModel "I need codeburn" when the expanded view mounts and "I'm done" when it unmounts.

**Step 1: Add a flag**

Near the existing `notchWidgetConfig` field, add:

```swift
private(set) var headerNeedsCodeburn: Bool = false {
    didSet {
        guard headerNeedsCodeburn != oldValue else { return }
        updateCodeburnPolling()
    }
}

func setHeaderNeedsCodeburn(_ needs: Bool) {
    headerNeedsCodeburn = needs
}
```

**Step 2: Update the polling decision**

Change `updateCodeburnPolling()` to:

```swift
private func updateCodeburnPolling() {
    let needsCodeburn = notchWidgetConfig.rightSlot == .dollarSpentToday
        || notchWidgetConfig.centerSlotExternal == .dollarSpentToday
        || headerNeedsCodeburn
    // ...rest unchanged
}
```

**Step 3: Verify build + tests**

`swift build` → success.
`swift test` → green.

**Step 4: Commit**

```bash
git add Sources/OpenIslandApp/AppModel.swift
git commit -m "feat(app): extend updateCodeburnPolling with headerNeedsCodeburn flag"
```

---

## Task 11: `DollarTodayPill` view + integrate into `openedHeaderContent`

**Files:**
- Create: `Sources/OpenIslandApp/Views/DollarTodayPill.swift`
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`

**Step 1: Write the pill view**

```swift
// Sources/OpenIslandApp/Views/DollarTodayPill.swift
import SwiftUI
import OpenIslandCore

struct DollarTodayPill: View {
    let state: CodeburnState

    var body: some View {
        if case .ok(let snap) = state {
            Text(format(snap.todayCost, currency: snap.currency))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(tint(for: snap.todayCost))
                .accessibilityLabel("\(snap.currency) \(snap.todayCost) spent today")
        } else {
            EmptyView()
        }
    }

    private func format(_ cost: Double, currency: String) -> String {
        let symbol = (currency == "USD") ? "$" : ""
        if cost < 10 { return String(format: "\(symbol)%.2f", cost) }
        return String(format: "\(symbol)%.1f", cost)
    }

    private func tint(for cost: Double) -> Color {
        if cost < 5 { return .green }
        if cost < 20 { return .yellow }
        return .orange
    }
}
```

**Step 2: Wire it into the header**

Find `openedHeaderContent` (line ~472 in `IslandPanelView.swift`) and `usageSummaryView(...)` calls. Add `DollarTodayPill(state: model.codeburnClient?.state ?? .notProbed)` after the existing rate-limit summary, separated by a divider that matches the existing `|` between `5h` and `7d` blocks.

The exact insertion depends on which layout branch is active (`usageSummaryView(providers, layout: .full)` etc., lines ~758-761 and 872-873). The cleanest approach is to wrap the existing usage summary and the new pill in one `HStack(spacing: 8)` and let SwiftUI lay them out, or append the pill at the end of the existing `HStack` when it exists.

Read `openedHeaderContent` carefully and pick the smallest insertion. Pseudocode:

```swift
HStack(spacing: 8) {
    usageSummaryView(providers, layout: .full)
    if model.codeburnClient?.state.isOk == true {
        Text("|").foregroundStyle(.white.opacity(0.3))
        DollarTodayPill(state: model.codeburnClient!.state)
    }
}
```

To avoid force-unwrap, derive `let cbState = model.codeburnClient?.state` once and use a `if case .ok = cbState` pattern.

You'll need a small extension on `CodeburnState` to test for `.ok`:

```swift
public extension CodeburnState {
    var isOk: Bool {
        if case .ok = self { return true }
        return false
    }
}
```

Add that to `Sources/OpenIslandCore/CodeburnTypes.swift`.

**Step 3: Toggle `headerNeedsCodeburn`**

In `IslandPanelView`, attach to whatever view container is the expanded-view body:

```swift
.onAppear { model.setHeaderNeedsCodeburn(true) }
.onDisappear { model.setHeaderNeedsCodeburn(false) }
```

Place it on the **expanded** state's container only (not the closed-state). If the panel uses a single body that switches based on `notchStatus`, gate the toggle:

```swift
.onChange(of: model.notchStatus == .opened, initial: true) { _, isOpened in
    model.setHeaderNeedsCodeburn(isOpened)
}
```

Pick whichever placement matches existing patterns in the file (look for similar `notchStatus`-gated logic).

**Step 4: Verify build + tests**

`swift build` → success.
`swift test` → green.

**Step 5: Visual smoke**

```bash
zsh scripts/launch-dev-app.sh --skip-setup
```

- Without codeburn: header layout unchanged.
- With codeburn installed (`npm i -g codeburn`), wait 30s after expanding the island: pill appears next to rate-limit summary.

**Step 6: Commit**

```bash
git add Sources/OpenIslandApp/Views/DollarTodayPill.swift Sources/OpenIslandApp/Views/IslandPanelView.swift Sources/OpenIslandCore/CodeburnTypes.swift
git commit -m "feat(app): add DollarTodayPill in expanded header"
```

---

## Task 12: Final smoke + push

**Files:** none (verification only)

**Step 1: Release build**

```bash
swift build -c release
```

Expected: clean, no new warnings.

**Step 2: Full test suite**

```bash
swift test
```

Expected: all green, including all tests added in tasks 1–7.

**Step 3: Run the dev app and walk through the smoke list** (from the design doc):

- Fresh Claude session in cmux → expanded view shows `[░░░░░░] 99%`.
- Drive to ~70% → bar grows green.
- ~85% used → yellow.
- ~90%+ → orange/red.
- Codex session → no badge, layout doesn't twitch.
- `npm i -g codeburn`, wait 30s → header `$X.YZ` appears after rate-limit summary.
- Without codeburn → header unchanged.
- Quit cmux session → registry evicts (no zombie watcher; verify with `lsof -p <PID> | grep .jsonl` showing the closed file is no longer held open).

**Step 4: Push**

```bash
git push origin feat/notch-personalization
```

Branch already tracks `origin/feat/notch-personalization`.

---

## Out of scope / Phase 2

- Per-session `$` row badge (parse JSONL with bundled pricing table — separate plan).
- Codex / Cursor / Gemini context-left support.
- Tooltip / hover detail on either badge.
- Refreshable `ContextWindowTable` via Application Support JSON.
- A11y label localization (Phase 1 ships English).
