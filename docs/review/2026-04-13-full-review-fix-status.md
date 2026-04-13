# 2026-04-13 Full Review 修复进度

## 背景

本记录用于承接 `./.full-review/` 对 `worktree-feat+external-display-support` 相对 `origin/main` 的综合审查结果。

原则：

- 只处理这次 PR 引入的问题，不扩散到仓库历史遗留问题。
- 保留 `.full-review` 作为原始审查结论，不在原文里混入后续修复状态。
- 每轮修复结束后更新这份文档，作为“已修 / 未修”对账面。

## 已落地修复

### 分支上此前已经提交的修复

1. `OverlayUICoordinator` 的 `NotificationCenter` observer 已清理，避免长期悬挂的屏幕参数与前台应用订阅。
2. 屏幕持久化标识已统一收敛到 `OverlayScreenIdentity`，避免多处 `screenID(for:)` 漂移导致 pill 位置读写不同 key。
3. `OverlayPillPositionStore` 已对非有限值做防御处理，避免 `NaN` / `Inf` 锚点把窗口推到非法坐标。

### 本轮继续落地的修复

1. `OverlayPanelController.hide()` 现在会显式停止 `NotchEventMonitors`，不再让隐藏后的 overlay 继续保留全局鼠标监视器空转。
2. `NotchEventMonitors` 的鼠标移动节流状态改为带锁共享状态，不再依赖 `nonisolated(unsafe) sharedLastMove` 的无锁跨闭包读写。
3. `NotchEventMonitors.moveDispatchDecision` 被提取为可测试的纯决策函数，便于后续继续做热路径回归保护。
4. 当前工作区同时保留了两项热路径微优化：
   - `overlay.debug.drag` 开关改为一次性读取，避免每次拖拽日志都查询 `UserDefaults`
   - `overlayDragLog` 改为 `@autoclosure`，在关闭日志时不再提前构造字符串
   - `shouldCaptureTopBarDragLayerHit` 先按 opened/closed 分支，再决定是否进入对应的昂贵子路径

## 仍未完成的问题

截至本轮，以下 full-review 项仍未完成，后续应继续按优先级处理：

1. `OverlayPanelController` 的热路径还没有彻底移除屏幕解析与放置诊断回退，`hitTest` / 鼠标监视路径仍有进一步缓存空间。
2. 缺少针对 overlay 热路径的性能基线测试，full-review 提到的性能回归目前还没有进入自动化预算约束。
3. CI push trigger 与当前 `worktree-*` 分支命名冲突、release notes 双语流水线问题仍未处理。
4. `.full-review` 中剩余的 P1/P2 架构问题（如 God object 拆分、更多缓存与依赖注入）尚未进入本轮修复范围。

## 本轮验证

- `swift test --filter OverlayPanelControllerTests`
- `swift test`

两条命令在本地均通过。
