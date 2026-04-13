# Overlay Presentation Policy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## 实施状态（2026-04-13）

- Task 1 已落地：`b52329f feat: add overlay presentation policy model`
- Task 2 已落地：`52302ae feat: add overlay presentation policy setting`
- Task 3 已落地：`3b067a7 fix: preserve manual display selection during fallback`
- Task 4-6 已合并落地：`431d044 feat: drive overlay layout by resolved presentation mode`
- Task 7 当前用于最终验证与文档收口

**Goal:** 引入与显示器选择正交的三档形态策略，让 overlay 可以在任意目标屏幕上按“全使用岛 / 有刘海才用岛 / 全胶囊”工作，并修复手工显示器选择会被错误清空的问题。

**Architecture:** 保留现有 `overlayDisplaySelectionID` 作为“目标显示器”配置，新增 `overlayPresentationPolicy` 作为“形态策略”配置，再根据目标屏幕能力推导运行时最终形态。拖动、位置持久化、壳层几何和诊断展示统一改为基于最终形态驱动，而不是继续把“外接屏 fallback”与“胶囊形态”耦合在一起。同时修复显示器暂时缺失时只做临时 fallback、但不丢失手工选择的持久化值。

**Tech Stack:** Swift 6.2、SwiftUI、AppKit、Swift Testing、UserDefaults

---

### Task 1: 建立形态策略与最终形态的数据模型

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayDisplayConfiguration.swift`
- Modify: `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- Test: `Tests/OpenIslandAppTests/OverlayScreenSelectionResolverTests.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`

**Step 1: 写失败测试，锁定策略推导结果**

在 `Tests/OpenIslandAppTests/OverlayScreenSelectionResolverTests.swift` 或新的专用测试文件中补以下测试：

```swift
@Test
func automaticPolicyUsesIslandOnNotchedScreen() {
    let mode = OverlayPresentationPolicy.automaticIslandWhenNotched
        .resolvePresentationMode(screenCapability: .notched)

    #expect(mode == .island)
}

@Test
func automaticPolicyUsesPillOnPlainScreen() {
    let mode = OverlayPresentationPolicy.automaticIslandWhenNotched
        .resolvePresentationMode(screenCapability: .plain)

    #expect(mode == .pill)
}

@Test
func alwaysIslandForcesIslandOnPlainScreen() {
    let mode = OverlayPresentationPolicy.alwaysIsland
        .resolvePresentationMode(screenCapability: .plain)

    #expect(mode == .island)
}

@Test
func alwaysPillForcesPillOnNotchedScreen() {
    let mode = OverlayPresentationPolicy.alwaysPill
        .resolvePresentationMode(screenCapability: .notched)

    #expect(mode == .pill)
}
```

**Step 2: 运行测试，确认先红**

Run:

```bash
swift test --filter 'OverlayScreenSelectionResolverTests'
```

Expected: 编译失败或测试失败，提示 `OverlayPresentationPolicy` / `OverlayPresentationMode` / `OverlayScreenCapability` 尚不存在。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/OverlayDisplayConfiguration.swift` 中：

- 新增 `OverlayScreenCapability`
  - `.notched`
  - `.plain`
- 新增 `OverlayPresentationPolicy`
  - `.alwaysIsland`
  - `.automaticIslandWhenNotched`
  - `.alwaysPill`
- 新增 `OverlayPresentationMode`
  - `.island`
  - `.pill`
- 提供纯 helper：

```swift
extension OverlayPresentationPolicy {
    func resolvePresentationMode(
        screenCapability: OverlayScreenCapability
    ) -> OverlayPresentationMode
}
```

- 把当前 `isNotched(_:)` 的结果同时暴露成 `screenCapability(for:)`

**Step 4: 运行测试，确认转绿**

Run:

```bash
swift test --filter 'OverlayScreenSelectionResolverTests'
```

Expected: 相关策略推导测试通过。

**Step 5: Commit**

```bash
git add Sources/OpenIslandApp/OverlayDisplayConfiguration.swift Tests/OpenIslandAppTests/OverlayScreenSelectionResolverTests.swift
git commit -m "feat: add overlay presentation policy model"
```

### Task 2: 持久化新的形态策略，并让设置页展示它

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- Modify: `Sources/OpenIslandApp/AppModel.swift`
- Modify: `Sources/OpenIslandApp/Views/SettingsView.swift`
- Modify: `Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift`

**Step 1: 写失败测试，锁定默认值和持久化**

在 `Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift` 中增加测试：

```swift
@Test
func presentationPolicyDefaultsToAutomaticIslandWhenNotched() {
    #expect(OverlayPresentationPolicy.defaultValue == .automaticIslandWhenNotched)
}

@Test
func persistedPresentationPolicyRoundTripsRawValue() {
    let raw = OverlayPresentationPolicy.alwaysPill.rawValue
    let restored = OverlayPresentationPolicy(rawValue: raw)

    #expect(restored == .alwaysPill)
}
```

如果当前测试结构更适合 coordinator 的纯 helper，也可以改成“从缺省配置恢复时得到默认值”的测试。

**Step 2: 运行测试，确认先红**

Run:

```bash
swift test --filter 'OverlayUICoordinatorTests'
```

Expected: 失败，提示没有新的 policy 持久化与默认行为。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/OverlayUICoordinator.swift` 中：

- 新增 `overlayPresentationPolicy`
- 新增 `UserDefaults` key，例如 `overlay.presentation.policy`
- 在初始化/恢复时读取，默认值为 `.automaticIslandWhenNotched`
- 在 `didSet` 中持久化

在 `Sources/OpenIslandApp/AppModel.swift` 中：

- 透出 `overlayPresentationPolicy` 给设置页使用

在 `Sources/OpenIslandApp/Views/SettingsView.swift` 中：

- 在“显示”页新增一个 `Picker`
- 三个选项：
  - 全使用岛
  - 有刘海才用岛
  - 全胶囊

在中英文本地化文件中新增对应文案 key。

**Step 4: 运行测试，确认转绿**

Run:

```bash
swift test --filter 'OverlayUICoordinatorTests'
```

Expected: policy 默认值与持久化测试通过。

**Step 5: Commit**

```bash
git add Sources/OpenIslandApp/OverlayUICoordinator.swift Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/Views/SettingsView.swift Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift
git commit -m "feat: add overlay presentation policy setting"
```

### Task 3: 修复手工显示器选择失效时被重置为 automatic 的问题

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayScreenSelectionResolver.swift`
- Modify: `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- Modify: `Sources/OpenIslandApp/OverlayDisplayConfiguration.swift`
- Test: `Tests/OpenIslandAppTests/OverlayScreenSelectionResolverTests.swift`
- Test: `Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift`

**Step 1: 写失败测试，锁定“暂时 fallback 但不清空手工选择”**

在 `Tests/OpenIslandAppTests/OverlayScreenSelectionResolverTests.swift` 中新增：

```swift
@Test
func missingManualSelectionFallsBackWithoutLosingSelectionSummary() {
    let resolved = OverlayScreenSelectionResolver.resolve(
        preferredScreenID: "display-external",
        screens: [
            OverlayScreenSelectionCandidate(
                id: "display-built-in",
                isNotched: true,
                isMain: true
            )
        ]
    )

    #expect(resolved?.screenID == "display-built-in")
    #expect(resolved?.selectionSummary == "manual missing, auto fallback")
}
```

在 `Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift` 中新增纯 helper 测试，锁定“当前选择失效时不把 `overlayDisplaySelectionID` 改写成 automatic”。

**Step 2: 运行测试，确认先红**

Run:

```bash
swift test --filter '(OverlayScreenSelectionResolverTests|OverlayUICoordinatorTests)'
```

Expected: 失败，表明 coordinator 当前仍会清空手工选择。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/OverlayUICoordinator.swift` 中：

- 修改 `refreshOverlayDisplayConfiguration()`
- 当前选中的显示器不在 `overlayDisplayOptions` 时：
  - 不修改 `overlayDisplaySelectionID`
  - 直接继续 `refreshOverlayPlacement()`

在 `Sources/OpenIslandApp/OverlayDisplayConfiguration.swift` / `OverlayScreenSelectionResolver.swift` 中：

- 确保 diagnostics 能区分：
  - 手工命中
  - 手工缺失后的临时 fallback
  - automatic

**Step 4: 运行测试，确认转绿**

Run:

```bash
swift test --filter '(OverlayScreenSelectionResolverTests|OverlayUICoordinatorTests)'
```

Expected: 手工选择缺失时的 fallback 测试通过，且没有把选择改写成 automatic。

**Step 5: Commit**

```bash
git add Sources/OpenIslandApp/OverlayScreenSelectionResolver.swift Sources/OpenIslandApp/OverlayUICoordinator.swift Sources/OpenIslandApp/OverlayDisplayConfiguration.swift Tests/OpenIslandAppTests/OverlayScreenSelectionResolverTests.swift Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift
git commit -m "fix: preserve manual display selection during fallback"
```

### Task 4: 把最终形态接入 diagnostics 与运行时推导

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayDisplayConfiguration.swift`
- Modify: `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- Modify: `Sources/OpenIslandApp/AppModel.swift`
- Test: `Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift`
- Test: `Tests/OpenIslandAppTests/OverlayScreenSelectionResolverTests.swift`

**Step 1: 写失败测试，锁定 diagnostics 同时展示策略与最终形态**

新增测试，断言 diagnostics 至少能够给出：

- `screenCapability`
- `presentationPolicy`
- `presentationMode`

例如：

```swift
@Test
func diagnosticsCarryResolvedPresentationMode() {
    let diagnostics = OverlayPlacementDiagnostics(
        ...
        screenCapability: .plain,
        presentationPolicy: .alwaysIsland,
        presentationMode: .island
    )

    #expect(diagnostics.presentationMode == .island)
}
```

**Step 2: 运行测试，确认先红**

Run:

```bash
swift test --filter '(OverlayScreenSelectionResolverTests|OverlayUICoordinatorTests)'
```

Expected: 编译失败或测试失败，提示 diagnostics 结构还没有这些字段。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/OverlayDisplayConfiguration.swift` 中：

- 给 `OverlayPlacementDiagnostics` 增加：
  - `screenCapability`
  - `presentationPolicy`
  - `presentationMode`
- 提供用户可读描述字段

在 resolver / diagnostics 构建路径中：

- 先解析目标屏幕
- 再解析屏幕能力
- 最后根据 `overlayPresentationPolicy` 推导 `presentationMode`

在 `OverlayUICoordinator` / `AppModel` 中：

- 保证 diagnostics 的刷新链路都能拿到最新 policy

**Step 4: 运行测试，确认转绿**

Run:

```bash
swift test --filter '(OverlayScreenSelectionResolverTests|OverlayUICoordinatorTests)'
```

Expected: diagnostics 与推导结果相关测试通过。

**Step 5: Commit**

```bash
git add Sources/OpenIslandApp/OverlayDisplayConfiguration.swift Sources/OpenIslandApp/OverlayUICoordinator.swift Sources/OpenIslandApp/AppModel.swift Tests/OpenIslandAppTests/OverlayScreenSelectionResolverTests.swift Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift
git commit -m "refactor: derive overlay presentation mode from policy"
```

### Task 5: 把拖动与 pill 持久化 gating 改为基于最终形态

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Modify: `Sources/OpenIslandApp/OverlayPillPositionStore.swift`
- Modify: `Sources/OpenIslandApp/OverlayClosedShellMetrics.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPillPositionStoreTests.swift`

**Step 1: 写失败测试，锁定“全胶囊时内屏也可拖”“全使用岛时外屏也不可拖”**

在 `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift` 中新增纯 helper 测试，例如：

```swift
@Test
func islandPresentationDisablesTopBarDragRegardlessOfScreen() {
    #expect(
        !OverlayPanelController.acceptsDirectMouseInteraction(
            status: .closed,
            mode: .island
        )
    )
}

@Test
func pillPresentationEnablesClosedPillDragRegardlessOfScreenCapability() {
    #expect(
        OverlayPanelController.acceptsDirectMouseInteraction(
            status: .closed,
            mode: .pill
        )
    )
}
```

如果需要，先把 helper 的参数从旧的 `OverlayPlacementMode` 迁到新的最终形态枚举。

**Step 2: 运行测试，确认先红**

Run:

```bash
swift test --filter '(OverlayPanelControllerTests|OverlayPillPositionStoreTests)'
```

Expected: 失败，说明当前 gating 仍绑定旧的 `topBar/notch` 语义。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/OverlayPanelController.swift` 中：

- 将 drag / hit-test / 直接交互 / hover-open 相关判断改为基于最终形态
- `presentationMode == .pill`：
  - 允许闭合 pill 拖动
  - 允许 hover-open header 拖动
  - 允许读写 pill 锚点
- `presentationMode == .island`：
  - 禁用上述行为

在 `Sources/OpenIslandApp/OverlayPillPositionStore.swift` 中：

- 不需要改变存储格式
- 但调用点只在 `presentationMode == .pill` 时使用

必要时在 `OverlayClosedShellMetrics.swift` 中将“compact pill”不再表达成“外接屏专属”，而是表达成最终形态为 `pill` 的共享 metrics。

**Step 4: 运行测试，确认转绿**

Run:

```bash
swift test --filter '(OverlayPanelControllerTests|OverlayPillPositionStoreTests)'
```

Expected: 交互 gating 与位置持久化测试通过。

**Step 5: Commit**

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift Sources/OpenIslandApp/OverlayPillPositionStore.swift Sources/OpenIslandApp/OverlayClosedShellMetrics.swift Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift Tests/OpenIslandAppTests/OverlayPillPositionStoreTests.swift
git commit -m "refactor: gate drag behavior by presentation mode"
```

### Task 6: 把视图壳层与设置诊断改为基于最终形态

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`
- Modify: `Sources/OpenIslandApp/Views/SettingsView.swift`
- Modify: `Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings`
- Test: `Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift`

**Step 1: 写失败测试，锁定岛/胶囊 metrics 不再隐含等于内外屏**

在 `Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift` 中新增测试：

```swift
@Test
func pillPresentationUsesCompactPillMetricsEvenOnNotchedScreen() {
    let metrics = OverlayClosedShellMetrics.forPresentationMode(
        .pill,
        closedHeight: 22
    )

    #expect(metrics.layoutFamily == .floatingPill)
}
```

再补一条：

```swift
@Test
func islandPresentationUsesIslandMetricsEvenOnPlainScreen() {
    let metrics = OverlayClosedShellMetrics.forPresentationMode(
        .island,
        closedHeight: 22
    )

    #expect(metrics.layoutFamily == .notch)
}
```

**Step 2: 运行测试，确认先红**

Run:

```bash
swift test --filter 'OverlayClosedShellMetricsTests'
```

Expected: 失败，说明 metrics 仍按旧的 `OverlayPlacementMode` 工作。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/Views/IslandPanelView.swift` 中：

- 不再把“是否 notch 模式”直接当成最终形态
- 改为优先读取 diagnostics 中的 `presentationMode`
- `presentationMode == .island` 走当前 island 壳层
- `presentationMode == .pill` 走当前 pill 壳层

在 `Sources/OpenIslandApp/Views/SettingsView.swift` 中：

- diagnostics 区新增：
  - 屏幕能力
  - 形态策略
  - 当前实际形态

在本地化资源中新增对应文案。

**Step 4: 运行测试，确认转绿**

Run:

```bash
swift test --filter 'OverlayClosedShellMetricsTests'
```

Expected: metrics 与壳层推导测试通过。

**Step 5: Commit**

```bash
git add Sources/OpenIslandApp/Views/IslandPanelView.swift Sources/OpenIslandApp/Views/SettingsView.swift Sources/OpenIslandApp/Resources/en.lproj/Localizable.strings Sources/OpenIslandApp/Resources/zh-Hans.lproj/Localizable.strings Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift
git commit -m "feat: render overlay by resolved presentation mode"
```

### Task 7: 全量验证并清理诊断文档

**Files:**
- Modify: `docs/index.md`
- Modify: `docs/plans/2026-04-13-overlay-presentation-policy-design.md`
- Modify: `docs/plans/2026-04-13-overlay-presentation-policy.md`

**Step 1: 运行定向测试**

Run:

```bash
swift test --filter '(OverlayScreenSelectionResolverTests|OverlayUICoordinatorTests|OverlayPanelControllerTests|OverlayPillPositionStoreTests|OverlayClosedShellMetricsTests|AppModelSessionListTests)'
```

Expected: 目标测试全部通过。

**Step 2: 运行全量测试**

Run:

```bash
swift test
```

Expected: 全量通过；如有 live 集成测试 skip，应在总结中明确说明。

**Step 3: 更新文档状态**

- 在设计文档中补最终实现备注
- 保持 `docs/index.md` 链接完整
- 如实现过程中计划有偏移，在本计划文档中同步修正

**Step 4: 检查工作区**

Run:

```bash
git diff --check
git status -sb
```

Expected: 无空白错误；仅保留本轮预期改动。

**Step 5: Commit**

```bash
git add docs/index.md docs/plans/2026-04-13-overlay-presentation-policy-design.md docs/plans/2026-04-13-overlay-presentation-policy.md
git commit -m "docs: finalize overlay presentation policy plan"
```

## 回滚策略

- **回滚范围**：本计划引入的四个落地提交——`b52329f`（model）、`52302ae`（settings）、`3b067a7`（preserve manual fallback）、`431d044`（drive layout by mode）——可通过 `git revert` 按倒序单独撤销。
- **持久化清理**：用户已配置的 `overlay.presentation.policy` UserDefaults 键在回滚后会被忽略（模型不再存在即视为默认 `automaticIslandWhenNotched`），无需主动清理；不会影响拖拽锚点（`overlay.pill.position.<screenID>`）等独立持久化状态。
- **数据兼容**：`overlayDisplaySelectionID` 的手工选择语义在整个 PR 中未改变，只在 fallback 分支上加了保留逻辑，回滚后退化为旧的 auto-fallback 行为，不会丢失用户的持久化选择。
- **验证**：`swift test` 全量通过 + 手工切换 `Always Island / Always Pill / Automatic` 观察外接屏形态随之变化。
