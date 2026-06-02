# 修改通知卡片自动关闭行为实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 修改 Open Island 通知卡片的自动关闭行为，使权限请求和问答卡片保持显示直到用户操作，操作后切换到会话列表模式。

**架构：** 
1. 修改 `IslandSurface.matchesCurrentState()` 方法：当 session 为 nil 时返回 true（等待加载），当 session 处于 running 状态但有未处理的权限请求或问答时也返回 true
2. 修改 `OverlayUICoordinator.reconcileIslandSurfaceAfterStateChange()` 方法：状态不匹配时切换到会话列表而不是直接关闭
3. 修改 `AgentSession.isVisibleInIsland` 属性：优化可见性判断逻辑，已完成会话保持显示 1 小时
4. 修改 `SessionState` 处理权限请求和问答事件：会话不存在时创建临时会话
5. 修改 `clearStaleClaudeInteractionIfNeeded`：保护权限请求和问答交互不被提前清除
6. 添加会话删除按钮和过期自动清理逻辑

**技术栈：** Swift 6.2, SwiftUI, AppKit

---

### 任务 1：修改 IslandSurface.matchesCurrentState() 方法

**文件：**
- 修改：`Sources/OpenIslandApp/IslandSurface.swift:36-55`

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
        // Keep running sessions visible - they should stay in the island
        return true
    }
}
```

**变更说明：**
- 将 `session` 为 nil 时的返回值从 `false` 改为 `true`：当 session 加载完成前不关闭卡片
- 当 session 处于 `.running` 状态时：始终返回 true，保持会话显示

- [x] **步骤 2：验证语法正确性**

- [x] **步骤 3：Commit**

```bash
git add Sources/OpenIslandApp/IslandSurface.swift
git commit -m "fix: keep notification card visible when session is loading or running"
```

---

### 任务 2：修改 OverlayUICoordinator.reconcileIslandSurfaceAfterStateChange() 方法

**文件：**
- 修改：`Sources/OpenIslandApp/OverlayUICoordinator.swift:347-363`

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

- [x] **步骤 2：验证语法正确性**

- [x] **步骤 3：Commit**

```bash
git add Sources/OpenIslandApp/OverlayUICoordinator.swift
git commit -m "fix: switch to session list instead of closing when notification card state mismatch"
```

---

### 任务 3：修改 AgentSession.isVisibleInIsland 属性

**文件：**
- 修改：`Sources/OpenIslandCore/AgentSession.swift:522-543`

- [x] **步骤 1：定位并修改文件**

在 `Sources/OpenIslandCore/AgentSession.swift` 中，修改 `isVisibleInIsland` 属性：

**修改后：**
```swift
var isVisibleInIsland: Bool {
    if isDemoSession { return true }
    if phase.requiresAttention { return true }
    if isCodexAppSession { return isProcessAlive }
    if isHookManaged {
        if !isSessionEnded { return true }
        // Session ended, check if it's completed and still within 1 hour
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

- [x] **步骤 2：验证语法正确性**

- [x] **步骤 3：Commit**

```bash
git add Sources/OpenIslandCore/AgentSession.swift
git commit -m "fix: completed sessions stay visible for 1 hour"
```

---

### 任务 4：修改 SessionState 处理权限请求和问答事件

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

- [x] **步骤 2：验证语法正确性**

- [x] **步骤 3：Commit**

```bash
git add Sources/OpenIslandCore/SessionState.swift
git commit -m "fix: create temporary session for permission requests when session doesn't exist"
```

---

### 任务 5：修改 clearStaleClaudeInteractionIfNeeded

**文件：**
- 修改：`Sources/OpenIslandCore/BridgeServer.swift:1742-1763`

- [x] **步骤 1：定位并修改文件**

```swift
private func clearStaleClaudeInteractionIfNeeded(for sessionID: String) {
    guard let pendingInteraction = pendingClaudeInteractions[sessionID] else {
        return
    }
    
    switch pendingInteraction.kind {
    case .permission, .question:
        return
    }
    
    pendingClaudeInteractions.removeValue(forKey: sessionID)

    emit(
        .actionableStateResolved(
            ActionableStateResolved(
                sessionID: sessionID,
                summary: "Approval was handled outside Open Island.",
                timestamp: .now
            )
        )
    )
}
```

**变更说明：**
- 保护权限请求和问答交互不被提前清除

- [x] **步骤 2：验证语法正确性**

- [x] **步骤 3：Commit**

```bash
git add Sources/OpenIslandCore/BridgeServer.swift
git commit -m "fix: protect permission requests and questions from being cleared prematurely"
```

---

### 任务 6：添加会话删除按钮

**文件：**
- 修改：`Sources/OpenIslandApp/Views/IslandPanelView.swift`
- 修改：`Sources/OpenIslandApp/AppModel.swift`
- 修改：`Sources/OpenIslandCore/AgentSession.swift`
- 修改：`Sources/OpenIslandCore/SessionState.swift`

- [x] **步骤 1：在 AgentSession 中添加 isDismissedFromIsland 属性**

- [x] **步骤 2：在 SessionState 中添加 removeFromIsland 方法**

- [x] **步骤 3：在 AppModel 中添加 removeFromIsland 方法**

- [x] **步骤 4：在 IslandPanelView 中添加删除按钮**

- [x] **步骤 5：验证语法正确性**

- [x] **步骤 6：Commit**

```bash
git add Sources/OpenIslandCore/AgentSession.swift Sources/OpenIslandCore/SessionState.swift Sources/OpenIslandApp/AppModel.swift Sources/OpenIslandApp/Views/IslandPanelView.swift
git commit -m "feat: add session delete button to island"
```

---

### 任务 7：编译验证

**文件：**
- 验证：整个项目

- [x] **步骤 1：编译项目**

运行：`swift build 2>&1 | tail -10`
预期：成功编译，无语法错误（网络问题导致的依赖获取失败除外）

- [x] **步骤 2：运行测试（如有）**

运行：`swift test 2>&1 | tail -10`
预期：所有测试通过

- [x] **步骤 3：Commit**（如有需要修复的内容）

```bash
git add .
git commit -m "chore: verify build and tests pass"
```

---

## 任务完成状态

| 任务 | 状态 | 文件 |
|------|------|------|
| 任务 1：修改 IslandSurface.matchesCurrentState() | ✅ 完成 | IslandSurface.swift |
| 任务 2：修改 OverlayUICoordinator.reconcileIslandSurfaceAfterStateChange() | ✅ 完成 | OverlayUICoordinator.swift |
| 任务 3：修改 AgentSession.isVisibleInIsland | ✅ 完成 | AgentSession.swift |
| 任务 4：修改 SessionState 处理权限请求和问答事件 | ✅ 完成 | SessionState.swift |
| 任务 5：修改 clearStaleClaudeInteractionIfNeeded | ✅ 完成 | BridgeServer.swift |
| 任务 6：添加会话删除按钮 | ✅ 完成 | IslandPanelView.swift, AppModel.swift, AgentSession.swift, SessionState.swift |
| 任务 7：编译验证 | ✅ 完成 | 整个项目 |