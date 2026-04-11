# 外接屏 Hover 展开拖动设计

## 背景

当前外接显示器 `topBar` 模式的拖动行为只支持闭合药丸：

- 闭合态按下药丸后可以直接拖动
- `hover` 进入药丸后会自动展开
- 展开态本身不支持拖动

这导致一个明显的交互割裂：

- 用户已经通过 `hover` 看到展开面板
- 但想移动位置时，必须先离开当前操作语境，重新回到闭合药丸再拖

用户希望把这条路径改成：

1. 鼠标移入药丸，面板自动展开
2. 展开后的面板允许拖动
3. 一旦开始拖动，视觉立即恢复成药丸
4. 拖动结束后保持药丸态并保存新位置

## 已确认约束

- 只改外接显示器 `topBar` 模式，不改刘海 `notch` 模式
- 只有顶部 `header / 药丸区` 可以启动拖动
- 展开面板的内容区必须继续保留原本的按钮、滚动、卡片交互
- 仅 `hover` 自动展开后的面板支持该拖动路径；`click` 主动展开保持现状
- 一旦识别到拖动，必须立即切回药丸态，不走普通 close 动画
- 拖动结束后保持药丸态，不自动重新展开
- 右上角控制按钮区不能被拖拽热区覆盖

## 目标

1. 让外接屏 hover 展开后的操作更连贯，用户不需要先手动收回再拖
2. 保持展开态内容区交互稳定，不引入误拖
3. 复用现有 top-bar 锚点持久化和闭合药丸拖拽能力
4. 不影响 notch 模式、click 展开路径和已有 close 动画修复

## 非目标

- 不给 `notch` 模式增加拖动
- 不让整个展开面板都可拖动
- 不改变 click 展开时的 header 操作方式
- 不重做 hover-open / auto-collapse 的整体状态机

## 交互决策

### 1. 只在 hover 展开时允许 header 拖动

这是本轮最重要的边界。

如果把拖动能力直接开放给所有展开态：

- header 上的控制按钮点击会更容易被误判成拖动
- 内容区滚动和卡片操作会与拖动冲突
- click 展开的工作流会变得更不稳定

因此本轮把拖动限定在：

- `topBar`
- 当前状态为 `opened`
- 展开原因是 `hover`
- 鼠标按下位置位于顶部 header 拖拽热区

### 2. 拖动热区只覆盖 header，可排除按钮区

顶部 header 是唯一允许开始拖动的区域。

具体策略：

- 左侧标题/摘要区域可拖
- 中间空白区域可拖
- 右上角静音、设置按钮所在区域不可拖

这样可以避免“想点按钮却把面板拖走”的误操作。

### 3. 拖动开始时立即切回药丸态

如果继续保留展开态面板跟随拖动：

- 视觉重量过大
- 展开态 frame 更容易被边界 clamp 影响
- 会重新引入“开始拖动时先跳一下”的问题

因此一旦位移超过拖动阈值：

- 立即把 overlay 状态切回 closed
- 直接进入现有药丸拖拽路径
- 后续只移动闭合药丸窗口

这条路径本质上是“hover-opened header 只是拖动入口，真正拖动的实体仍然是 closed pill”。

### 4. 松手后保持药丸态

拖动结束后的状态固定为：

- 保存新的 top-bar 锚点
- 保持 `closed`
- 不自动重新展开

这样用户可以连续拖多个位置，也不会在松手时再被 hover 状态抖动带回展开态。

## 实现思路

### 1. 控制器增加 opened-header 拖动判定

`OverlayPanelController` 新增一组纯判定 / 几何 helper：

- 当前是否允许从 opened header 进入拖动
- opened top-bar header 的拖拽热区
- 是否应排除右侧按钮区

这些 helper 继续由 AppKit 层消费，避免把拖动判定塞进 SwiftUI 子视图树。

### 2. `NotchHostingView` 统一接管两类拖动入口

当前 `NotchHostingView` 只接管闭合药丸拖动。

本轮扩展为两条入口：

- 闭合药丸拖动
- hover-opened header 拖动

展开 header 拖动的生命周期：

1. `mouseDown`
2. 命中 opened header 拖拽热区
3. 超过拖动阈值
4. 通知控制器立即切回药丸态
5. 重置拖动原点并开始移动 closed pill

### 3. 状态切换使用“立即收回”而不是普通 close 动画

普通 `notchClose()` 会走现有 close 过渡，这不适合拖动开始瞬间。

这里需要一个面向拖动的专用入口：

- 同步切到 `closed`
- 不播放普通 close 动画
- 不等待 close transition defer
- 让 panel frame 立即回到药丸拖动语义

### 4. 持久化继续复用已有 top-bar 锚点逻辑

拖动结束时仍复用现有：

- `OverlayPillPositionStore.save(...)`
- top-bar 边界 clamp
- closed hit rect 更新

这样本轮不需要重写位置持久化。

## 风险与应对

### 风险 1：header 拖拽与按钮点击冲突

应对：

- 把拖拽热区限制在 header
- 明确排除按钮区
- 保留拖动阈值，轻微抖动不触发拖动

### 风险 2：开始拖动时视觉跳变

应对：

- 不走普通 close 动画
- 用同步切回 closed 的方式进入拖动
- 复用现有 closed pill 拖拽路径，减少新几何分支

### 风险 3：hover 展开和拖动状态相互抢占

应对：

- 拖动开始前取消 hover timer
- 拖动中禁止重新触发 hover-open
- 松手后保持 closed，不立即恢复 hover-open

## 测试策略

### 纯逻辑测试

- opened top-bar header 何时允许拖动
- click 展开时不允许走 opened-header 拖动
- notch 模式不允许走 opened-header 拖动
- header 拖拽热区不会覆盖按钮区

### 回归测试

- 拖动开始时 overlay 会同步切回 closed
- 拖动结束后保持 closed
- 现有 closed pill 拖动不回归
- hover 自动展开不回归
- close 动画锚点修复不回归

## 结论

本轮最稳妥的方案不是“让展开面板本体拖动”，而是：

- 用 hover 展开的 header 作为拖动入口
- 一旦识别拖动，立即切回药丸
- 后续继续沿用现有 closed pill 拖动与持久化链路

这样既满足新的交互目标，也能把副作用限制在 top-bar hover 路径内。

## 实现备注

- 实际实现时，Task 3 到 Task 5 共享同一条 AppKit 拖动态机：header 热区接管、越阈值后同步切回 closed、随后复用 closed pill 拖动与持久化。
- 这三步不能再人为拆成互不相干的链路，否则会重新引入 shared-state 回归。
- 越过拖动阈值的同一帧必须把从初始按下点累计出来的位移立即应用到 collapsed pill；如果只是先切回 `closed`、下一帧再继续拖，用户体感会像“面板根本拖不动”。
- 运行时排查这条链路时，可打开 `defaults write app.openisland.dev overlay.debug.drag -bool YES`；日志会写入 `OSLog` 的 `OverlayDrag` category，覆盖 `hitTest -> mouseDown -> mouseDragged -> collapse -> moveDraggedPanel -> mouseUp`。
