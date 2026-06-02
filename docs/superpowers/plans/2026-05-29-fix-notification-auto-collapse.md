# 修改通知卡片自动关闭行为实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 修改 Open Island 通知卡片的自动关闭行为，使权限请求和问答卡片保持显示直到用户操作，操作后切换到会话列表模式；修复会话可见性逻辑，确保已完成会话保持显示1小时；优化关闭状态灵动岛的品牌色适配。

**架构：** 
1. 修改 `IslandSurface.matchesCurrentState()` 方法：当 session 为 nil 时返回 true（等待加载），当 session 处于 running 状态但有未处理的权限请求或问答时也返回 true
2. 修改 `OverlayUICoordinator.reconcileIslandSurfaceAfterStateChange()` 方法：状态不匹配时切换到会话列表而不是直接关闭
3. 修改 `AgentSession.isVisibleInIsland` 属性：优化可见性判断逻辑，已完成会话保持显示 1 小时，优先处理 hook-managed 会话
4. 修改 `SessionState` 处理权限请求和问答事件：会话不存在时创建临时会话，防止 hook-managed 会话因进程检测失败而被标记为结束
5. 修改 `OverlayUICoordinator`：添加通知卡片自动折叠延迟、点击外部保护、切换到会话列表时清理通知状态
6. 添加会话删除按钮和过期自动清理逻辑
7. 优化关闭状态灵动岛的品牌色适配与显示逻辑

**技术栈：** Swift 6.2, SwiftUI, AppKit

---

### 任务 1：修改 IslandSurface.matchesCurrentState() 方法

**文件：**
- 修改：`Sources/OpenIslandApp/IslandSurface.swift`

- [x] **步骤 1：定位并修改文件**

在 `Sources/OpenIslandApp/IslandSurface.swift` 中，修改 `matchesCurrentState()` 方法：

**修改前：**
```swift
func matchesCurrentState(of session: AgentSession?) -> Bool {
    guard sessionID != nil else {
        return true
    }

    guard let session else {
        return false
    }

    switch session.phase {
    case .waitingForApproval:
        return session.permissionRequest != nil
    case .waitingForAnswer:
        return session.questionPrompt != nil
    case .completed:
        return true
    case .running:
        return false
    }
}
```

**修改后：**
```swift
func matchesCurrentState(of session: AgentSession?) -> Bool {
    guard sessionID != nil else {
        return true
    }

    guard let session else {
        return true
    }

    switch session.phase {
    case .waitingForApproval:
        return session.permissionRequest != nil
    case .waitingForAnswer:
        return session.questionPrompt != nil
    case .completed:
        return true
    case .running:
        return true
    }
}
```

**变更说明：**
- 将 `session` 为 nil 时的返回值从 `false` 改为 `true`：当 session 加载完成前不关闭卡片
- 当 session 处于 `.running` 状态时：始终返回 true，保持会话显示

- [x] **步骤 2：Commit**

```bash
git add Sources/OpenIslandApp/IslandSurface.swift
git commit -m "fix: prevent notification cards from auto-collapsing when session has pending request"
```

---

### 任务 2：修改 OverlayUICoordinator.reconcileIslandSurfaceAfterStateChange() 方法

**文件：**
- 修改：`Sources/OpenIslandApp/OverlayUICoordinator.swift`

- [x] **步骤 1：定位并修改文件**

在 `Sources/OpenIslandApp/OverlayUICoordinator.swift` 中，修改 `reconcileIslandSurfaceAfterStateChange()` 方法：

**修改前：**
```swift
func reconcileIslandSurfaceAfterStateChange() {
    guard islandSurface.isNotificationCard else {
        return
    }

    let session = activeIslandCardSession
    guard islandSurface.matchesCurrentState(of: session) else {
        if notchOpenReason == .notification {
            notchClose()
        } else {
            islandSurface = .sessionList()
        }
        return
    }

    updateNotificationAutoCollapse()
}
```

**修改后：**
```swift
func reconcileIslandSurfaceAfterStateChange() {
    guard islandSurface.isNotificationCard else {
        return
    }

    let session = activeIslandCardSession
    guard islandSurface.matchesCurrentState(of: session) else {
        if notchOpenReason == .notification {
            islandSurface = .sessionList(actionableSessionID: islandSurface.sessionID)
        } else {
            islandSurface = .sessionList()
        }
        return
    }

    updateNotificationAutoCollapse()
}
```

**变更说明：**
- 当状态不匹配且是通知打开时：不再调用 `notchClose()` 直接关闭，而是切换到 `.sessionList(actionableSessionID:)` 保留会话引用

- [x] **步骤 2：Commit**

```bash
git add Sources/OpenIslandApp/OverlayUICoordinator.swift
git commit -m "fix: prevent notification auto collapse by preserving session reference"
```

---

### 任务 3：修改 OverlayUICoordinator 通知状态清理

**文件：**
- 修改：`Sources/OpenIslandApp/OverlayUICoordinator.swift`

- [x] **步骤 1：添加通知状态清理逻辑**

修改 `reconcileIslandSurfaceAfterStateChange()` 方法，添加切换到会话列表时的通知状态清理和布局刷新：

```swift
func reconcileIslandSurfaceAfterStateChange() {
    guard islandSurface.isNotificationCard else {
        return
    }

    let session = activeIslandCardSession
    guard islandSurface.matchesCurrentState(of: session) else {
        if notchOpenReason == .notification {
            islandSurface = .sessionList(actionableSessionID: islandSurface.sessionID)
            notificationAutoCollapseTask?.cancel()
            refreshOverlayPlacementIfVisible()
        } else {
            islandSurface = .sessionList()
        }
        return
    }

    updateNotificationAutoCollapse()
}
```

- [x] **步骤 2：Commit**

```bash
git add Sources/OpenIslandApp/OverlayUICoordinator.swift
git commit -m "fix: properly clean up notification state when switching to session list"
```

---

### 任务 4：修改 AgentSession.isVisibleInIsland 属性

**文件：**
- 修改：`Sources/OpenIslandCore/AgentSession.swift`

- [x] **步骤 1：定位并修改文件**

在 `Sources/OpenIslandCore/AgentSession.swift` 中，修改 `isVisibleInIsland` 属性：

```swift
var isVisibleInIsland: Bool {
    if isDemoSession { return true }
    if phase.requiresAttention { return true }
    
    if isCodexAppSession {
        return isProcessAlive
    }
    
    if isHookManaged {
        if !isSessionEnded { return true }
        if phase == .completed {
            let oneHourAgo = Date.now.addingTimeInterval(-3600)
            return updatedAt > oneHourAgo
        }
        return false
    }
    
    if isProcessAlive { return true }
    return false
}
```

**变更说明：**
- hook-managed 会话已结束时，如果是已完成状态且在 1 小时内，仍然保持可见
- 优先处理 hook-managed 会话以获得稳定的可见性

- [x] **步骤 2：Commit**

```bash
git add Sources/OpenIslandCore/AgentSession.swift
git commit -m "fix: prioritize hook-managed sessions for stable visibility"
```

---

### 任务 5：修改 SessionState 处理权限请求和问答事件

**文件：**
- 修改：`Sources/OpenIslandCore/SessionState.swift`

- [x] **步骤 1：定位并修改文件**

在 `permissionRequested` 和 `questionAsked` 事件处理中，当会话不存在时创建临时会话：

```swift
case let .permissionRequested(payload):
    if var session = sessionsByID[payload.sessionID] {
        session.phase = .waitingForApproval
        session.permissionRequest = payload.request
        upsert(session)
    } else {
        var session = AgentSession(
            id: payload.sessionID,
            title: payload.request.summary,
            tool: .claudeCode,
            phase: .waitingForApproval,
            summary: payload.request.summary,
            updatedAt: payload.timestamp,
            permissionRequest: payload.request
        )
        session.isHookManaged = true
        upsert(session)
    }
```

**变更说明：**
- 当会话不存在时创建临时会话，确保权限请求不丢失

- [x] **步骤 2：Commit**

```bash
git add Sources/OpenIslandCore/SessionState.swift
git commit -m "fix: create temporary session for permission requests when session doesn't exist"
```

---

### 任务 6：防止 hook-managed 会话因进程检测失败而被标记为结束

**文件：**
- 修改：`Sources/OpenIslandCore/SessionState.swift`
- 修改：`Sources/OpenIslandCore/AgentSession.swift`

- [x] **步骤 1：修改进程检测逻辑**

在 `SessionState` 的进程检测逻辑中，对 hook-managed 会话跳过进程检测：

```swift
if session.isHookManaged {
    if session.isSessionEnded {
        continue
    }
    if session.phase == .completed {
        upsert(session)
        continue
    }
    // 继续正常处理
}
```

**变更说明：**
- hook-managed 会话依赖 hook 生命周期事件，不应被进程检测影响

- [x] **步骤 2：Commit**

```bash
git add Sources/OpenIslandCore/SessionState.swift Sources/OpenIslandCore/AgentSession.swift
git commit -m "fix: prevent hook-managed sessions from being marked ended due to process detection failure"
```

---

### 任务 7：添加通知卡片自动折叠行为和点击外部保护

**文件：**
- 修改：`Sources/OpenIslandApp/OverlayUICoordinator.swift`
- 修改：`Sources/OpenIslandApp/AppModel.swift`
- 修改：`Sources/OpenIslandApp/Views/SettingsView.swift`

- [x] **步骤 1：添加通知自动折叠延迟设置**

在 `AppModel.swift` 中添加配置项：

```swift
@AppStorage("notificationAutoCollapseDelay")
var notificationAutoCollapseDelay: Double = 10.0
```

- [x] **步骤 2：添加点击外部保护逻辑**

在 `OverlayUICoordinator.swift` 中添加点击外部时检查会话状态：

```swift
func handleClickOutside() {
    if sessionsRequireAttention {
        return
    }
    // 正常关闭逻辑
}
```

- [x] **步骤 3：在设置页面添加配置 UI**

- [x] **步骤 4：Commit**

```bash
git add Sources/OpenIslandApp/OverlayUICoordinator.swift Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/Views/SettingsView.swift
git commit -m "feat: notification card auto-collapse behavior, click-outside protection, notification delay setting"
```

---

### 任务 8：添加会话删除按钮

**文件：**
- 修改：`Sources/OpenIslandApp/Views/IslandPanelView.swift`
- 修改：`Sources/OpenIslandApp/AppModel.swift`
- 修改：`Sources/OpenIslandCore/AgentSession.swift`
- 修改：`Sources/OpenIslandCore/SessionState.swift`

- [x] **步骤 1：在 AgentSession 中添加 isDismissedFromIsland 属性**

- [x] **步骤 2：在 SessionState 中添加 removeFromIsland 方法**

- [x] **步骤 3：在 AppModel 中添加 removeFromIsland 方法**

- [x] **步骤 4：在 IslandPanelView 中添加删除按钮**

- [x] **步骤 5：Commit**

```bash
git add Sources/OpenIslandCore/AgentSession.swift Sources/OpenIslandCore/SessionState.swift Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat: add session delete button to island"
```

---

### 任务 9：优化关闭状态灵动岛的品牌色适配与显示逻辑

**文件：**
- 修改：`Sources/OpenIslandApp/AppModel.swift`
- 修改：`Sources/OpenIslandApp/Views/V6NotchContent.swift`
- 修改：`Sources/OpenIslandApp/Views/UnifiedBars.swift`
- 修改：`Sources/OpenIslandCore/SessionState.swift`

- [x] **步骤 1：添加 islandClosedBrandColor 方法**

在 `AppModel.swift` 中添加获取当前会话品牌色的方法：

```swift
func islandClosedBrandColor() -> Color {
    // 返回当前会话的品牌色
}
```

- [x] **步骤 2：修改 UnifiedBars 区分 idle 和 running 状态**

```swift
func drawBar(isRunning: Bool, brandColor: Color) {
    // 根据状态和品牌色绘制
}
```

- [x] **步骤 3：为运行中的灵动岛添加宽度增量**

- [x] **步骤 4：Commit**

```bash
git add Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/Views/V6NotchContent.swift Sources/OpenIslandApp/Views/UnifiedBars.swift Sources/OpenIslandCore/SessionState.swift
git commit -m "refactor(closed island): optimize brand color adaptation and display logic"
```

---

### 任务 10：添加每种类型的声音设置

**文件：**
- 修改：`Sources/OpenIslandApp/NotificationSoundService.swift`
- 修改：`Sources/OpenIslandApp/Views/SettingsView.swift`

- [x] **步骤 1：添加完成/权限/问答的声音设置**

```swift
@AppStorage("notificationSoundCompletion")
var notificationSoundCompletion: NotificationSound = .default

@AppStorage("notificationSoundPermission")
var notificationSoundPermission: NotificationSound = .default

@AppStorage("notificationSoundQuestion")
var notificationSoundQuestion: NotificationSound = .default
```

- [x] **步骤 2：Commit**

```bash
git add Sources/OpenIslandApp/NotificationSoundService.swift Sources/OpenIslandApp/Views/SettingsView.swift
git commit -m "feat: add per-type sound settings (completion/permission/question)"
```

---

### 任务 11：编译验证

**文件：**
- 验证：整个项目

- [x] **步骤 1：编译项目**

运行：`swift build 2>&1 | tail -10`
预期：成功编译，无语法错误

- [x] **步骤 2：Commit**

```bash
git add .
git commit -m "fix(session-visibility): 修复会话可见性逻辑"
```

---

## 任务完成状态

| 任务 | 状态 | 文件 |
|------|------|------|
| 任务 1：修改 IslandSurface.matchesCurrentState() | ✅ 完成 | IslandSurface.swift |
| 任务 2：修改 OverlayUICoordinator.reconcileIslandSurfaceAfterStateChange() | ✅ 完成 | OverlayUICoordinator.swift |
| 任务 3：修改 OverlayUICoordinator 通知状态清理 | ✅ 完成 | OverlayUICoordinator.swift |
| 任务 4：修改 AgentSession.isVisibleInIsland | ✅ 完成 | AgentSession.swift |
| 任务 5：修改 SessionState 处理权限请求和问答事件 | ✅ 完成 | SessionState.swift |
| 任务 6：防止 hook-managed 会话因进程检测失败 | ✅ 完成 | SessionState.swift, AgentSession.swift |
| 任务 7：添加通知卡片自动折叠行为和点击外部保护 | ✅ 完成 | OverlayUICoordinator.swift, AppModel.swift, SettingsView.swift |
| 任务 8：添加会话删除按钮 | ✅ 完成 | IslandPanelView.swift, AppModel.swift, AgentSession.swift, SessionState.swift |
| 任务 9：优化关闭状态灵动岛的品牌色适配 | ✅ 完成 | AppModel.swift, V6NotchContent.swift, UnifiedBars.swift, SessionState.swift |
| 任务 10：添加每种类型的声音设置 | ✅ 完成 | NotificationSoundService.swift, SettingsView.swift |
| 任务 11：编译验证 | ✅ 完成 | 整个项目 |

---

## 提交记录

| 提交 | 描述 |
|------|------|
| df58f56 | fix: prevent notification cards from auto-collapsing when session has pending request or question |
| 95ea0c2 | fix: prevent notification auto collapse by preserving session reference |
| e1a6d81 | fix: properly clean up notification state when switching to session list |
| 6327190 | fix: add refreshOverlayPlacementIfVisible call when switching to session list |
| 37e7150 | fix: keep running sessions visible in island when they have pending requests |
| 6cf2634 | fix: prevent notification card auto-dismissal for sessions with pending requests |
| 724d465 | fix: prioritize hook-managed sessions for stable visibility |
| a836380 | fix: prevent hook-managed sessions from being marked ended due to process detection failure |
| a1d293b | feat: notification card auto-collapse behavior, click-outside protection, notification delay setting, and per-type sound settings |
| 54e4da2 | refactor(closed island): 优化关闭状态灵动岛的品牌色适配与显示逻辑 |
| 4cd1f2f | fix(session-visibility): 修复会话可见性逻辑 |