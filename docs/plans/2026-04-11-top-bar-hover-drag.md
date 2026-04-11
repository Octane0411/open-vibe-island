# 外接屏 Hover 展开拖动 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让外接显示器 `topBar` 模式在 hover 自动展开后支持从顶部 header 启动拖动，并在拖动开始时同步恢复成药丸态，松手后保存新位置且保持闭合。

**Architecture:** 继续由 `OverlayPanelController` 和 `NotchHostingView` 负责 AppKit 鼠标接管与拖拽几何，SwiftUI 只暴露复用的 top-bar opened header 尺寸信息。拖动开始后不保留 opened 面板本体，而是同步切回 closed 并复用现有药丸拖动与持久化链路。

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing, Swift Package Manager

---

### Task 1: 固化 opened-header 拖动判定

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`
- Test: `Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift`

**Step 1: 写失败测试**

在 `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift` 中新增纯判定测试，覆盖：

- `topBar + opened + hover` 允许从 opened header 启动拖动
- `topBar + opened + click` 不允许
- `notch + opened + hover` 不允许

示例：

```swift
@Test
func hoverOpenedTopBarAllowsHeaderDrag() {
    let allowed = OverlayPanelController.canDragOpenedTopBarHeader(
        status: .opened,
        mode: .topBar,
        openReason: .hover
    )

    #expect(allowed)
}
```

**Step 2: 跑测试确认失败**

Run: `swift test --filter '(OverlayPanelControllerTests|OverlayUICoordinatorTests)'`

Expected: 因判定 helper 尚不存在而编译失败或测试失败。

**Step 3: 写最小实现**

在 `Sources/OpenIslandApp/OverlayPanelController.swift` 中新增 opened-header 拖动判定 helper，只表达条件，不处理拖动细节。

**Step 4: 再跑测试确认通过**

Run: `swift test --filter '(OverlayPanelControllerTests|OverlayUICoordinatorTests)'`

Expected: 新增判定测试通过。

**Step 5: 提交**

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift \
  Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift \
  Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift
git commit -m "test: cover top-bar opened header drag gating"
```

### Task 2: 固化 header 拖拽热区几何

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`

**Step 1: 写失败测试**

在 `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift` 中新增热区几何测试，覆盖：

- 顶部 header 左侧区域命中为可拖
- 右上角按钮区不命中为可拖
- header 下方内容区不命中为可拖

示例：

```swift
@Test
func openedTopBarHeaderDragRectExcludesControlButtons() {
    let rect = OverlayPanelController.openedTopBarHeaderDragRect(
        panelBounds: NSRect(x: 0, y: 0, width: 736, height: 420),
        headerHeight: 30,
        trailingControlWidth: 64,
        horizontalPadding: 18
    )

    #expect(rect.maxX < 736)
}
```

**Step 2: 跑测试确认失败**

Run: `swift test --filter OverlayPanelControllerTests`

Expected: 因热区 helper 尚不存在而失败。

**Step 3: 写最小实现**

在 `OverlayPanelController` 中新增纯几何 helper 生成 opened top-bar header 拖拽热区；在 `IslandPanelView` 中抽出可复用的 top-bar opened header 尺寸常量，供控制器与视图共享。

**Step 4: 跑测试确认通过**

Run: `swift test --filter OverlayPanelControllerTests`

Expected: 几何测试通过。

**Step 5: 提交**

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift \
  Sources/OpenIslandApp/Views/IslandPanelView.swift \
  Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift
git commit -m "test: define top-bar opened header drag hit area"
```

### Task 3: 让 opened hover header 成为拖动入口

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`

**Step 1: 写失败测试**

在 `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift` 中新增状态测试，覆盖：

- 命中 opened header 时 `NotchHostingView` 所需的 AppKit 接管条件为真
- 非热区或不符合条件时继续让 SwiftUI 子视图处理事件

**Step 2: 跑测试确认失败**

Run: `swift test --filter OverlayPanelControllerTests`

Expected: 因 opened-header 接管条件未实现而失败。

**Step 3: 写最小实现**

在 `OverlayPanelController` / `NotchHostingView` 中扩展：

- `mouseDown` 可在 hover-opened header 进入待拖状态
- `hitTest` 仅在 opened-header 热区返回 hosting view 自己
- 右上角按钮区仍透传给 SwiftUI

**Step 4: 跑测试确认通过**

Run: `swift test --filter OverlayPanelControllerTests`

Expected: 接管条件与旧有 closed pill 行为同时通过。

**Step 5: 提交**

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift \
  Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift
git commit -m "feat: start drag from hover-opened top-bar header"
```

### Task 4: 拖动开始时同步切回药丸

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayUICoordinator.swift`
- Modify: `Sources/OpenIslandApp/AppModel.swift`
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Test: `Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift`
- Test: `Tests/OpenIslandAppTests/AppModelSessionListTests.swift`

**Step 1: 写失败测试**

新增测试覆盖：

- 从 hover-opened topBar header 开始拖动时，overlay 状态会同步切回 `closed`
- 不经过普通 close transition defer
- 拖动结束后仍保持 `closed`

示例：

```swift
@Test
func topBarHoverDragStartClosesOverlayImmediately() {
    let plan = OverlayUICoordinator.dragStartPlan(
        status: .opened,
        mode: .topBar,
        openReason: .hover
    )

    #expect(plan == .closeImmediatelyForDrag)
}
```

**Step 2: 跑测试确认失败**

Run: `swift test --filter '(OverlayUICoordinatorTests|AppModelSessionListTests)'`

Expected: 因拖动专用 close 入口不存在而失败。

**Step 3: 写最小实现**

在 `OverlayUICoordinator` 中新增一个面向拖动的同步收回入口；在 `AppModel` 暴露对应调用；在 `OverlayPanelController` 的拖动启动链路里调用它。

要求：

- 不走普通 close 动画
- 不恢复到 opened
- 不改变 click 展开路径

**Step 4: 跑测试确认通过**

Run: `swift test --filter '(OverlayUICoordinatorTests|AppModelSessionListTests)'`

Expected: 新增状态测试通过。

**Step 5: 提交**

```bash
git add Sources/OpenIslandApp/OverlayUICoordinator.swift \
  Sources/OpenIslandApp/AppModel.swift \
  Sources/OpenIslandApp/OverlayPanelController.swift \
  Tests/OpenIslandAppTests/OverlayUICoordinatorTests.swift \
  Tests/OpenIslandAppTests/AppModelSessionListTests.swift
git commit -m "fix: collapse hover-opened top-bar before drag"
```

### Task 5: 复用现有药丸拖拽与持久化链路

**Files:**
- Modify: `Sources/OpenIslandApp/OverlayPanelController.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift`
- Test: `Tests/OpenIslandAppTests/OverlayPlacementStrategyTests.swift`

**Step 1: 写失败测试**

新增测试覆盖：

- 从 opened header 进入拖动后，后续 panel 移动使用 closed pill 语义
- 松手后保存的仍是 top-bar 药丸锚点
- 边界 clamp 与已有持久化规则不回归

**Step 2: 跑测试确认失败**

Run: `swift test --filter '(OverlayPanelControllerTests|OverlayPlacementStrategyTests)'`

Expected: 至少一个新增回归测试失败。

**Step 3: 写最小实现**

让 opened-header 拖动在超过阈值后：

- 重新建立 drag 起点
- 把随鼠标移动的对象切换为 closed pill
- `mouseUp` 后继续复用 `persistDraggedPillPosition()`

**Step 4: 跑测试确认通过**

Run: `swift test --filter '(OverlayPanelControllerTests|OverlayPlacementStrategyTests)'`

Expected: 拖动与边界回归测试通过。

**Step 5: 提交**

```bash
git add Sources/OpenIslandApp/OverlayPanelController.swift \
  Tests/OpenIslandAppTests/OverlayPanelControllerTests.swift \
  Tests/OpenIslandAppTests/OverlayPlacementStrategyTests.swift
git commit -m "fix: persist top-bar position after hover drag"
```

### Task 6: 文档、全量验证与收尾

**Files:**
- Modify: `docs/plans/2026-04-11-top-bar-hover-drag-design.md`
- Modify: `docs/plans/2026-04-11-top-bar-hover-drag.md`
- Modify: `docs/plans/2026-04-09-external-display-shell-split-design.md`

**Step 1: 同步文档**

把实现后的真实约束同步回设计文档，尤其是：

- 只在 hover-opened topBar header 启用拖动
- 拖动开始后同步收回药丸
- 按钮区排除在拖拽热区之外

**Step 2: 跑针对性测试**

Run: `swift test --filter '(OverlayPanelControllerTests|OverlayUICoordinatorTests|AppModelSessionListTests|OverlayPlacementStrategyTests)'`

Expected: 所有与 top-bar 拖动相关的测试通过。

**Step 3: 跑全量验证**

Run: `swift test`

Expected: 全量测试通过；Ghostty live integration 用例若未设置环境变量则按设计跳过。

**Step 4: 跑文档检查**

Run: `scripts/check-docs.sh`

Expected: 输出 `docs check passed`。

**Step 5: 提交**

```bash
git add docs/plans/2026-04-11-top-bar-hover-drag-design.md \
  docs/plans/2026-04-11-top-bar-hover-drag.md \
  docs/plans/2026-04-09-external-display-shell-split-design.md
git commit -m "docs: record top-bar hover drag plan"
```
