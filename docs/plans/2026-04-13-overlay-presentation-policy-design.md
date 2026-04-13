# 覆盖层形态策略与显示器选择解耦设计

## 实施状态（2026-04-13）

- 已完成形态策略模型：`b52329f feat: add overlay presentation policy model`
- 已完成形态策略设置项与持久化：`52302ae feat: add overlay presentation policy setting`
- 已完成手工显示器选择缺失时的 fallback 保留：`3b067a7 fix: preserve manual display selection during fallback`
- 已完成最终展示形态对 diagnostics、布局、壳层与交互路径的真实驱动：`431d044 feat: drive overlay layout by resolved presentation mode`

当前分支上的“全使用岛 / 有刘海才用岛 / 全胶囊”配置、显示器选择保留策略，以及按最终形态驱动的 overlay 行为已经落地。该设计文档后续主要保留为决策背景与约束说明。

## 背景

当前覆盖层的显示逻辑把两件不同的事情混在了一起：

1. 选哪一块显示器承载 overlay
2. 在这块显示器上用“岛”还是“胶囊”形态

现有实现里，第二件事并不是用户配置，而是由屏幕是否有刘海直接推导出来：

- 有刘海屏：`OverlayPlacementMode.notch`
- 无刘海屏：`OverlayPlacementMode.topBar`

这带来了两个问题：

- 用户不能显式要求“所有屏幕都用岛”或“所有屏幕都用胶囊”
- “胶囊”被隐含定义成“外接屏 fallback 形态”，导致交互、拖动、持久化等行为天然绑定到外接屏，而不是绑定到形态本身

另外，当前显示器选择还有一个已知缺陷：

- 当手工选择的显示器短暂不在可用列表中时，当前实现会把用户选择重置为 `automatic`
- 之后 overlay 会重新回到自动策略，而自动策略又优先刘海屏
- 这会让“手工固定外接屏”的偏好丢失

## 目标

1. 新增一个与“显示器选择”并列存在的全局“形态策略”配置
2. 支持三档策略：
   - 全使用岛
   - 有刘海才用岛
   - 全胶囊
3. 把“是否可拖动、是否保存位置、是否忽略 pill 锚点”等行为从“外接屏/内屏”解耦，改为由最终形态驱动
4. 修复手工显示器选择会被错误清空的问题
5. 保持现有默认行为兼容：默认仍是“有刘海才用岛”

## 非目标

- 不在本轮引入“每块屏幕单独配置形态策略”
- 不改变当前 overlay 的核心内容结构、通知卡片流程或会话列表逻辑
- 不重做现有屏幕 ID 生成方式
- 不移除现有 top-bar pill 拖动与位置持久化能力，只改变它的适用条件

## 已确认交互约束

### 1. 显示器选择与形态策略并列存在

用户会继续先选择 overlay 落在哪块显示器上，再独立选择这块显示器最终使用什么形态。

这意味着：

- “显示器选择”只解决 overlay 放在哪块屏
- “形态策略”只解决 overlay 在该屏上是岛还是胶囊

两者不能继续共享同一个 `OverlayPlacementMode` 语义。

### 2. 全使用岛是强制岛行为

当用户选择“全使用岛”时：

- 即使目标屏幕没有刘海，也要按岛形态渲染
- 行为上也应完全按当前“岛”处理
- 固定顶部居中
- 不允许拖动
- 不使用 pill 锚点持久化

这不是“胶囊几何 + 岛外观”，而是完整的岛模式。

### 3. 全胶囊是强制胶囊行为

当用户选择“全胶囊”时：

- 即使目标屏幕有刘海，也要按胶囊形态渲染
- 行为上应完全按当前 top-bar pill 处理
- 顶部居中 / 支持拖动
- 允许保存位置
- 不再把“胶囊”定义成外接屏专属形态

换句话说，本轮要把当前“外接屏形态”提升成独立的“胶囊形态”。

## 推荐方案

推荐把“目标屏幕能力”和“最终展示形态”拆成两层语义，而不是继续扩展当前的 `OverlayPlacementMode`。

### 配置层

新增全局配置：

- `overlayDisplaySelectionID`
  - 只决定目标显示器
- `overlayPresentationPolicy`
  - `alwaysIsland`
  - `automaticIslandWhenNotched`
  - `alwaysPill`

其中：

- `automaticIslandWhenNotched` 作为默认值，兼容当前产品行为

### 运行时推导层

运行时分三步推导：

1. 根据 `overlayDisplaySelectionID` 解析目标显示器
2. 根据屏幕几何判断该显示器是否具备“刘海能力”
3. 根据 `overlayPresentationPolicy + 屏幕能力` 推导最终展示形态

最终形态建议用独立枚举表示，例如：

- `OverlayPresentationMode.island`
- `OverlayPresentationMode.pill`

这样可以把大量当前写成“`mode == .topBar` 才能拖动”的逻辑，统一改成“`presentationMode == .pill` 才能拖动”。

## 备选方案与取舍

### 方案 A：继续扩展 `OverlayPlacementMode`

例如把 `notch/topBar` 扩成更多混合状态。

不推荐，原因是：

- 会继续把“屏幕能力”“用户策略”“最终形态”混在一起
- 拖动、持久化、设置页、诊断文案都会越来越难维护
- 后续再出“显示器切换”和“形态策略”交叉问题时，排查成本会更高

### 方案 B：每块屏幕单独配置形态策略

不作为本轮方案，原因是：

- 超出当前需求
- 设置页复杂度明显上升
- 持久化与迁移成本也会更高

## 运行时行为设计

### 1. 岛形态

当最终形态为 `island` 时：

- 使用当前 notch/island 视觉与交互语义
- 顶部居中
- 不允许 pill 拖动
- 不消费 `OverlayPillPositionStore`
- 不写入 pill 锚点

这适用于：

- 有刘海屏 + 自动策略
- 任意屏幕 + 全使用岛

### 2. 胶囊形态

当最终形态为 `pill` 时：

- 使用当前 top-bar pill 视觉与交互语义
- 可拖动
- 可保存位置
- 读取并写入 `OverlayPillPositionStore`
- hover-open 后的 header 拖动链路继续保留

这适用于：

- 无刘海屏 + 自动策略
- 任意屏幕 + 全胶囊

### 3. 诊断与设置展示

当前“Display”页的诊断信息不足以表达新的配置模型。

建议扩展为四类信息：

- 当前屏幕
- 屏幕能力：有刘海 / 普通屏
- 形态策略：三档配置之一
- 当前实际形态：岛 / 胶囊

这样可以快速区分：

- 是用户主动选择了某个策略
- 还是自动策略根据屏幕能力做出的结果
- 还是手工显示器当前暂时不可用，系统只是在做临时 fallback

## 显示器选择持久化修复

当前缺陷在于：

- 如果手工选择的显示器一度不在 `overlayDisplayOptions` 中
- 当前实现会把 `overlayDisplaySelectionID` 直接重置为 `automatic`
- 这会触发持久化删除，导致用户偏好永久丢失

本轮建议修复为：

- 手工选择失效时，只做临时 fallback 渲染
- 不清空保存的 `overlayDisplaySelectionID`
- diagnostics 明确标记“手工选择暂不可用，当前按 fallback 显示”
- 当目标屏幕重新出现时，应自动回到原手工选择

这项修复与新形态策略是同一层配置治理问题，应该在同一轮完成。

## 数据模型建议

### 1. 屏幕能力

建议新增纯几何层 helper，例如：

- `OverlayScreenCapability.notched`
- `OverlayScreenCapability.plain`

只负责回答“这块屏幕有没有刘海能力”，不负责回答最终渲染形态。

### 2. 用户配置

建议新增：

- `OverlayPresentationPolicy`
  - `alwaysIsland`
  - `automaticIslandWhenNotched`
  - `alwaysPill`

并为其提供：

- `UserDefaults` 持久化 key
- 中英文展示文案
- 设置页 `Picker`

### 3. 最终形态

建议新增：

- `OverlayPresentationMode`
  - `island`
  - `pill`

它将成为：

- `OverlayPanelController`
- `IslandPanelView`
- `OverlayClosedShellMetrics`
- drag / hit-test / pill position store gating

之间共享的单一事实来源。

## 迁移策略

### 1. 旧用户默认迁移

已有用户统一迁移到：

- `overlayPresentationPolicy = automaticIslandWhenNotched`

这样不会改变默认体验。

### 2. 旧 pill 锚点数据兼容

现有位置持久化数据继续保留。

但使用规则改为：

- 当前实际形态是 `pill` 时读写
- 当前实际形态是 `island` 时忽略

### 3. 手工显示器选择兼容

现有 `overlay.display.preference` 继续保留；
但从本轮开始，不再因为屏幕暂时缺失而主动删除它。

## 测试策略

### 1. 纯逻辑测试

- 有刘海屏 + `alwaysIsland` -> `island`
- 有刘海屏 + `automaticIslandWhenNotched` -> `island`
- 有刘海屏 + `alwaysPill` -> `pill`
- 无刘海屏 + `alwaysIsland` -> `island`
- 无刘海屏 + `automaticIslandWhenNotched` -> `pill`
- 无刘海屏 + `alwaysPill` -> `pill`

### 2. 交互 gating 测试

- `island` 形态不可拖动
- `pill` 形态可拖动
- `pill` 形态的 hover-open header 拖动不再依赖“外接屏”前提

### 3. 持久化测试

- `pill` 形态会保存和读取 pill 位置
- `island` 形态忽略 pill 锚点
- 手工显示器选择失效时不会清空保存值
- 目标屏幕恢复后会重新命中原手工选择

## 风险与应对

### 风险 1：当前 `OverlayPlacementMode` 用途过多

应对：

- 本轮不要只做命名替换
- 先明确“屏幕能力”“用户策略”“最终形态”三层职责
- 再逐步把调用点迁移到最终形态判断

### 风险 2：拖动/持久化回归

应对：

- 所有 drag gating 统一绑定到 `OverlayPresentationMode.pill`
- 通过回归测试锁住 hover-opened header 拖动与位置保存

### 风险 3：设置迁移后诊断混乱

应对：

- diagnostics 同时展示“策略”和“当前实际形态”
- 不再把 “topBar/notch” 直接当成设置语义暴露给用户

## 结论

本轮应把“显示器选择”和“岛/胶囊策略”拆成两套正交配置。

推荐方案是：

- 保留 `overlayDisplaySelectionID` 负责目标屏幕
- 新增 `overlayPresentationPolicy` 负责用户策略
- 新增 `OverlayPresentationMode` 作为运行时最终形态
- 将拖动、锚点持久化、视图壳层、诊断展示全部改为基于最终形态驱动
- 同时修复手工显示器选择会被错误清空的问题

这样可以把当前“胶囊 = 外接屏 fallback”这层历史耦合拆掉，为后续形态控制、显示器切换与交互稳定性建立更清晰的边界。
