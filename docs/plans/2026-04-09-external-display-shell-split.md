# 外接显示器闭合态壳层拆分 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在保持展开态内容一致的前提下，拆分内置刘海屏与外接显示器的闭合态壳层和定位策略，降低模式分支耦合，并为外接屏后续视觉调优建立独立落点。

**Architecture:** `IslandPanelView` 只负责根据 `OverlayPlacementMode` 组装闭合态壳层与共享展开态内容；`OverlayPanelController` 继续负责窗口生命周期，但把 topBar 专属的锚点、closed hit rect、拖拽与 clamp 几何收敛到模式化 helper。展开态内容树只保留一份实现。

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, Swift Package Manager

---

### Task 1: 固化模式化几何与壳层约束

**Files:**
- Create: `Sources/OpenIslandApp/OverlayClosedShellMetrics.swift`
- Create: `Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift`
- Modify: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`

**Step 1: 写失败测试，固化壳层模式约束**

在 `Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift` 中新增纯单元测试，覆盖：

- `notch` 模式返回刘海壳层 metrics
- `topBar` 模式返回外接屏紧凑 pill metrics
- opened header allowance 对非刘海屏至少为 `30`

示例：

```swift
@Test
func topBarClosedShellUsesCompactMetrics() {
    let metrics = OverlayClosedShellMetrics.forMode(
        .topBar,
        closedHeight: 22,
        liveCountDigits: 1,
        showsAttention: false
    )

    #expect(metrics.closedHeight == 22)
    #expect(metrics.isFloatingPill)
}
```

**Step 2: 运行测试并确认失败**

Run: `swift test --filter OverlayClosedShellMetricsTests`

Expected: 编译失败或测试失败，因为 `OverlayClosedShellMetrics` 尚不存在。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/OverlayClosedShellMetrics.swift` 中新增纯 helper，至少包含：

- mode
- closedHeight
- openedHeaderHeight
- iconSize
- horizontalPadding
- badge spacing
- attention indicator size

保持 helper 无 SwiftUI 依赖，便于测试。

**Step 4: 运行测试并确认通过**

Run: `swift test --filter OverlayClosedShellMetricsTests`

Expected: `OverlayClosedShellMetricsTests` 全部通过。

**Step 5: 补控制器侧回归测试**

在 `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift` 中追加非刘海屏 opened header allowance / closed hit rect 相关断言，避免后续重构时把 topBar 闭合态几何改回 notch 假设。

**Step 6: 提交**

```bash
git add Sources/OpenIslandApp/OverlayClosedShellMetrics.swift \
  Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift \
  Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift
git commit -m "test: cover overlay shell mode metrics"
```

### Task 2: 从 `IslandPanelView` 中拆出闭合态壳层

**Files:**
- Create: `Sources/OpenIslandApp/Views/OverlayClosedShells.swift`
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`
- Test: `Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift`

**Step 1: 写失败测试，约束模式选择结果**

在 `OverlayClosedShellMetricsTests` 中新增测试，约束：

- `.notch` 模式不会使用 floating pill metrics
- `.topBar` 模式不会使用 notch filler lane metrics

示例：

```swift
@Test
func notchAndTopBarClosedShellsUseDifferentLayoutFamilies() {
    let notch = OverlayClosedShellMetrics.forMode(.notch, closedHeight: 34, liveCountDigits: 1, showsAttention: false)
    let topBar = OverlayClosedShellMetrics.forMode(.topBar, closedHeight: 22, liveCountDigits: 1, showsAttention: false)

    #expect(notch.layoutFamily == .notch)
    #expect(topBar.layoutFamily == .floatingPill)
}
```

**Step 2: 运行测试并确认失败**

Run: `swift test --filter OverlayClosedShellMetricsTests`

Expected: 因新增字段或约束未实现而失败。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/Views/OverlayClosedShells.swift` 中新增：

- `NotchClosedShell`
- `TopBarClosedShell`

在 `Sources/OpenIslandApp/Views/IslandPanelView.swift` 中：

- 保留共享的 opened content
- 让闭合态 `headerRow` 分派到新壳层
- 清理 `headerRow` 中的 `if !isNotchMode` 大分支

要求：

- 不复制 `openedContent`
- 不复制 opened header actions
- 不改变 `model.notchStatus` 的状态流

**Step 4: 运行针对性测试**

Run: `swift test --filter OverlayClosedShellMetricsTests`

Expected: 新增 metrics / mode 约束继续通过。

**Step 5: 运行 overlay 回归测试**

Run: `swift test --filter OverlayPanelControllerTests`

Expected: 既有几何测试保持通过。

**Step 6: 提交**

```bash
git add Sources/OpenIslandApp/Views/OverlayClosedShells.swift \
  Sources/OpenIslandApp/Views/IslandPanelView.swift \
  Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift
git commit -m "refactor: split closed overlay shells by placement mode"
```

### Task 3: 提纯 topBar 定位、命中与拖拽策略

**Files:**
- Create: `Sources/OpenIslandApp/OverlayPlacementStrategy.swift`
- Create: `Tests/OpenIslandAppTests/OverlayPlacementStrategyTests.swift`
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`

**Step 1: 写失败测试，固化 topBar 专属几何行为**

在 `Tests/OpenIslandAppTests/OverlayPlacementStrategyTests.swift` 中新增纯 helper 测试，覆盖：

- topBar anchor 默认位于 `visibleFrame.maxY - 18`
- 已保存 anchor 会被优先使用
- closed rect 会围绕 anchor / closed width 计算
- opened panel 会被 clamp 在 `visibleFrame` 内
- topBar 闭合态的点击/拖拽命中必须跟随当前 overlay 实际所在屏，不能默认退回主屏

示例：

```swift
@Test
func topBarFrameClampsToVisibleFrame() {
    let frame = OverlayPlacementStrategy.topBar.frame(
        anchor: NSPoint(x: 1900, y: 1060),
        size: NSSize(width: 740, height: 520),
        screenVisibleFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117)
    )

    #expect(frame.maxX <= 1728)
}
```

**Step 2: 运行测试并确认失败**

Run: `swift test --filter OverlayPlacementStrategyTests`

Expected: 因 helper 未实现而失败。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/OverlayPlacementStrategy.swift` 中新增 mode-aware helper，至少收敛：

- notch / topBar anchor 规则
- topBar frame clamp
- closed hit rect 计算

并保持以下交互约束：

- `topBar` 闭合态保留直接鼠标交互，支持点击与拖拽
- `notch` 闭合态继续走被动命中，不引入可拖拽行为

然后把 `OverlayPanelController` 中对应逻辑改为调用 helper，而不是继续内联。

**Step 4: 运行新测试并确认通过**

Run: `swift test --filter OverlayPlacementStrategyTests`

Expected: 新几何测试全部通过。

**Step 5: 运行 overlay 控制器回归测试**

Run: `swift test --filter OverlayPanelControllerTests`

Expected: 既有 hit-testing / panel activation / closed height 测试全部通过。

**Step 6: 提交**

```bash
git add Sources/OpenIslandApp/OverlayPlacementStrategy.swift \
  Sources/OpenIslandApp/OverlayPanelController.swift \
  Tests/OpenIslandAppTests/OverlayPlacementStrategyTests.swift \
  Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift
git commit -m "refactor: extract overlay placement strategies"
```

### Task 4: 验证展开态共享内容未被拆散

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`
- Modify: `Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift`
- Modify: `docs/architecture.md`

**Step 1: 写失败测试，约束 opened header allowance 行为**

在 `OverlayClosedShellMetricsTests` 中新增测试，要求：

- notch / topBar 两种模式都通过同一个 opened allowance 入口计算
- topBar 的 opened header allowance 至少为 `30`
- notch 模式继续以 `closedHeight` 为基线

**Step 2: 运行测试并确认失败**

Run: `swift test --filter OverlayClosedShellMetricsTests`

Expected: 因共享入口未完全统一而失败。

**Step 3: 写最小实现**

在 `IslandPanelView` 中：

- 提炼共享 opened content 容器
- 让 notch / topBar 都从同一个 opened content 入口渲染
- 仅保留必要的 mode-aware spacing / token，不复制内容树

同时在 `docs/architecture.md` 追加一段说明：

- 闭合态壳层按 placement mode 拆分
- 展开态内容保持单一路径

**Step 4: 运行相关测试**

Run: `swift test --filter OverlayClosedShellMetricsTests`

Expected: 共享 opened content 的约束测试通过。

**Step 5: 运行完整测试**

Run: `swift test`

Expected: 全量测试通过；如有跳过测试，记录原因。

**Step 6: 手工验证**

Run: `zsh scripts/launch-dev-app.sh`

验证：

- 内置刘海屏闭合态未退化
- 外接显示器闭合态仍可拖拽、点击打开、hover 打开
- 两种模式展开态内容一致

**Step 7: 提交**

```bash
git add Sources/OpenIslandApp/Views/IslandPanelView.swift \
  Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift \
  docs/architecture.md
git commit -m "refactor: share opened overlay content across display modes"
```

### Task 5: 外接屏视觉细调与闭合宽度收敛

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayClosedShellMetrics.swift`
- Modify: `Sources/OpenIslandApp/Views/OverlayClosedShells.swift`
- Test: `Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift`

**Step 1: 写失败测试，锁定外接屏 pill tokens**

为 topBar 模式新增具体 token 断言，例如：

- icon size
- spacing
- horizontal padding
- closed height

要求这些 token 只影响 `TopBarClosedShell`。

**Step 2: 运行测试并确认失败**

Run: `swift test --filter OverlayClosedShellMetricsTests`

Expected: 新 token 断言失败。

**Step 3: 写最小实现**

仅调整 topBar 壳层相关的视觉参数与闭合宽度来源，不改 notch 壳层。

要求：

- topBar 闭合宽度按内容紧凑计算，不能继续复用 notch 的 lane expansion 公式
- `IslandPanelView` 与 `OverlayPanelController` 走同一个 mode-aware helper
- notch 模式继续保留原有 lane-based 宽度模型

**Step 4: 运行测试并确认通过**

Run: `swift test --filter OverlayClosedShellMetricsTests`

Expected: token 测试通过。

**Step 5: 手工验证**

Run: `zsh scripts/launch-dev-app.sh`

Expected: 外接屏闭合态视觉更协调，展开态内容无回归。

**Step 6: 提交**

```bash
git add Sources/OpenIslandApp/OverlayClosedShellMetrics.swift \
  Sources/OpenIslandApp/Views/OverlayClosedShells.swift \
  Tests/OpenIslandAppTests/OverlayClosedShellMetricsTests.swift
git commit -m "fix: refine top-bar closed shell tokens"
```

### Task 6: topBar 按下优先拖动并抑制 hover 展开

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Modify: `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- Modify: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`
- Modify: `docs/plans/2026-04-09-external-display-shell-split-design.md`

**Step 1: 写失败测试，锁定按住优先交互**

在 `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift` 中新增纯 helper 测试，覆盖：

- `topBar` 闭合态按下时不再允许 hover 定时展开
- `notch` 闭合态不受这条规则影响
- 释放按住状态后，`topBar` 的 hover 展开资格恢复

**Step 2: 运行测试并确认失败**

Run: `swift test --filter OverlayPanelControllerTests`

Expected: 因 hover 抑制 helper 尚不存在而失败。

**Step 3: 写最小实现**

在 `OverlayPanelController` 中：

- 为 topBar 闭合态引入按住/拖动中的 hover 抑制状态
- `mouseDown` 一进入 topBar 闭合态 press candidate 就立即取消 hover timer
- `handleMouseMoved` / `scheduleHoverOpen` 在 press state 下禁止触发 hover 展开
- `mouseUp` 后恢复 hover 资格，并保持现有“点击打开 / 拖动保存”分流

在 `OverlayUICoordinator` 中只保留必要的交互状态对接，不改展开态内容与 notch 行为。

**Step 4: 运行测试并确认通过**

Run: `swift test --filter OverlayPanelControllerTests`

Expected: 新增交互测试通过。

**Step 5: 运行完整测试**

Run: `swift test`

Expected: 全量测试通过；如有跳过测试，记录原因。

**Step 6: 手工验证**

Run: `zsh scripts/launch-dev-app.sh`

验证：

- hover 到外接屏小胶囊时仍会自动展开
- 但在 hover 延迟内按下并拖动时，不会再触发展开动画
- 按住不动并松手时仍按点击打开处理

**Step 7: 提交**

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift \
  Sources/OpenIslandApp/OverlayUICoordinator.swift \
  Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift \
  docs/plans/2026-04-09-external-display-shell-split-design.md \
  docs/plans/2026-04-09-external-display-shell-split.md
git commit -m "fix: suppress hover open during top-bar drag press"
```

## 回滚策略

- **壳层拆分部分**：`NotchClosedShell` / `TopBarClosedShell` 以及 `OverlayClosedShellMetrics.forMode` 是纯加法；若需要回滚，可以让 `IslandPanelView` 的 closed 分支重新走合并后的老路径，再删除这两个视图文件。
- **hover+drag 部分**：对应的 `OverlayPanelController` / `OverlayUICoordinator` 改动与 `2026-04-11-top-bar-hover-drag` 计划共享回滚面，参见那份计划的“回滚策略”。
- **持久化**：本计划未新增 UserDefaults 键，也未变动 `overlay.pill.position.*` 的 schema，回滚无数据迁移负担。
- **测试锚点**：`OverlayClosedShellMetricsTests` 的 notch/topBar 分家用例是结构回归的最小校验集，可作为回滚彻底性的快速 smoke。
