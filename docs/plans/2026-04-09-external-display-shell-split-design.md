# 外接显示器闭合态壳层拆分设计

## 背景

当前 overlay 已经存在两种显示模式：

- 内置刘海屏：`OverlayPlacementMode.notch`
- 外接显示器：`OverlayPlacementMode.topBar`

代码层面并不是完全复用一套表现，而是在同一套骨架里逐步加入模式分支：

- `OverlayPanelController` 已经按模式区分锚点、拖拽、命中区域和窗口定位。
- `IslandPanelView` 已经按模式区分闭合态 shape、header 布局和 opened header 行为。

这说明“外接屏只是刘海屏的轻微变体”这个前提已经不成立。继续把两者硬塞进同一个闭合态实现里，只会让 `if isNotchMode` 越来越多，视觉调优和交互调优互相牵制。

## 已确认约束

- 展开态内容必须保持一致。
- 外接显示器和内置刘海屏允许使用不同的闭合态视觉。
- `automatic` 选屏在存在内置刘海屏时，仍必须优先贴到刘海屏，不能因为外接屏恰好是 `NSScreen.main` 而漂移到 top bar。
- 外接显示器的拖拽、命中区和 top-bar 定位行为必须保留。
- topBar 闭合态在恢复直接命中前，必须先把 `NSPanel` frame 缩回闭合尺寸，不能继续保留上一次展开态的大窗口命中区。
- topBar 锚点持久化必须按实时闭合宽度做边界夹取，不能写死一个固定半宽。
- topBar 闭合态按住/拖拽期间，后台 session 刷新不能立刻触发 panel reposition，必须延后到指针释放后再补做。
- 控制器用于定位的 shadow inset 与 SwiftUI 视图用于绘制的 shadow inset 必须共享同一套 opened/closed 规则，否则边界附近会出现开合后 pill 无法回到原锚点的问题。
- 外接显示器闭合态保留 hover 自动展开，但鼠标按下后必须优先进入按住/拖动链路，不能再被 hover 展开抢占。
- 不做“双套完整 UI”，避免把 session list、notification card、header actions 维护两份。

## 目标

1. 保持展开态信息架构、内容组件和交互行为一致。
2. 让外接显示器闭合态可以独立调优，不再受刘海屏闭合态结构拖累。
3. 让定位、命中测试和拖拽逻辑按显示模式收敛，避免控制器继续横向膨胀。
4. 为后续外接屏视觉迭代创造稳定落点，而不是继续往主视图里追加条件分支。

## 非目标

- 本轮不重写展开态内容。
- 本轮不引入两套 notification card / session row。
- 本轮不立即锁定外接屏闭合态的最终像素参数，只先拆出可调结构。
- 本轮不改变模式判定来源，仍以 `OverlayPlacementMode` 为单一事实来源。

## 当前问题

### 1. 视图层已经处于“半拆不拆”状态

`IslandPanelView` 目前共享同一个 `notchContent` 骨架，但内部已经在以下位置分叉：

- 闭合态 shape：刘海屏用 `NotchShape`，外接屏用 `Capsule`
- 闭合态 header：刘海屏是 notch 布局，外接屏是紧凑 chip 布局
- opened header：仅刘海屏走 notch-aware 布局

这意味着同一个函数同时承担了：

- 模式选择
- 几何计算
- 视觉外壳
- 展开态内容承载

职责过多，后续再改外接屏视觉时很容易误伤刘海屏。

### 2. 控制器层的模式差异已经很重

`OverlayPanelController` 对外接屏已经单独支持：

- pill anchor 持久化
- 拖拽移动与保存
- top-bar 模式命中范围
- 非刘海屏高度与 closed rect 计算

这些逻辑不是简单样式差异，而是不同的交互模型。它们继续内联在同一个控制器里，会让测试边界越来越模糊。

## 决策

采用“共享展开态内容，拆分闭合态壳层与定位策略”的结构。

### 保持共享的部分

- `openedContent`
- session list / notification / actionable card
- header buttons 的动作语义
- overlay 生命周期与 `AppModel` 状态机

### 拆分的部分

- 闭合态外壳视图
- 模式相关的闭合态 layout tokens
- topBar 与 notch 的定位/命中/拖拽策略

## 目标结构

### 1. `IslandPanelView` 退化为组装器

`IslandPanelView` 只负责：

- 读取当前 `OverlayPlacementMode`
- 选择闭合态壳层
- 承载共享的展开态内容
- 统一 opened / closed / popping 状态切换

它不再自己承载两套闭合态排版细节。

### 2. 引入两个闭合态壳层

- `NotchClosedShell`
- `TopBarClosedShell`

它们只负责闭合态的：

- shape
- icon / badge / attention indicator 排布
- 闭合态 hover / scale 视觉
- 模式专属 spacing / padding / corner radius tokens

这样外接屏后续可以单独调成真正的 floating pill，而不是继续伪装成“缩小版 notch”。

### 3. 展开态内容保持单一实现

引入共享 opened content 容器，承载：

- opened header 内容
- session list
- notification / approval / question / completion 卡片

允许存在少量 mode-aware token，例如：

- header 顶部安全间距
- opened header 预留高度

但不允许拆成两套内容树。

### 4. 控制器侧按模式拆出 placement helper

`OverlayPanelController` 继续是 overlay 生命周期入口，但模式差异逻辑应收敛到独立 helper：

- notch：居中贴刘海、固定命中模型
- topBar：锚点、拖拽、clamp、closed hit rect、可持久化位置、按住时的 hover 抑制

不一定要第一步就上 protocol；可以先抽成 mode-aware helper / strategy type，确保职责边界清楚，再视复杂度决定是否继续抽象。

## 数据与渲染流

1. `OverlayPanelController` 解析目标屏幕并产出 `OverlayPlacementDiagnostics`
2. `IslandPanelView` 以 `diagnostics.mode` 作为闭合态模式来源
3. 闭合态时：
   - `NotchClosedShell` 或 `TopBarClosedShell` 负责外壳与 header 布局
4. 展开态时：
   - 始终进入共享 opened content
   - 仅通过 mode-aware token 处理少量顶部几何差异
5. 外接显示器闭合态按下时：
   - 立即取消当前 hover timer
   - 进入 press/drag 优先状态
   - `mouseUp` 再按“点击打开 / 拖动持久化”分流

## 测试策略

### 单元测试

优先为纯 helper 建测试，避免把关键约束埋进 SwiftUI 私有状态：

- notch / topBar 模式下的 closed shell metrics
- opened header allowance 规则
- topBar closed hit rect / anchor clamp / dragging 保存逻辑
- topBar 闭合态按下时不会再触发 hover 自动展开

### 回归测试

保留并扩展 `OverlayPanelControllerTests`，覆盖：

- `closedSurfaceRect`
- 非刘海屏高度规则
- click / hover 相关行为不回归
- automatic 选屏对内置刘海屏的优先级不回归
- closed topBar 命中恢复前的 frame 同步不回归
- topBar 锚点保存/恢复的边缘 clamp 不回归

### 手工验证

至少验证以下场景：

- 内置刘海屏闭合态视觉与打开行为不回归
- 外接显示器闭合态仍可拖拽、点击打开、hover 打开
- 外接显示器闭合态在按下后不会边展开边拖动
- 两种模式展开后内容一致
- 外接显示器展开后不会裁切 header 或内容区

## 风险与应对

### 风险 1：拆分后 opened/closed 动画衔接变差

应对：

- 共享状态机与动画入口
- 将 mode-specific shape 留在 closed shell 内部，但 transition timing 仍由顶层统一控制

### 风险 2：外接屏拖拽命中区回归

应对：

- 保持 `NotchHostingView` 的 topBar 接管逻辑
- 先把几何 helper 提纯并补测试，再迁移调用点

### 风险 3：展开态被意外拆成两套

应对：

- 在实现计划里明确“opened content 只能有一个组件入口”
- 评审时重点检查是否出现 duplicated opened tree

## 结论

最合适的方向不是“完全双份实现”，而是：

- 共享展开态内容
- 拆分闭合态壳层
- 拆分模式相关的定位与命中策略

这样既能保持产品语义一致，也能让外接显示器真正作为独立表现面来演进。
