# 修改通知卡片自动关闭行为实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 修改 Open Island 通知卡片的自动关闭行为，使权限请求和问答卡片保持显示直到用户操作，操作后切换到会话列表模式。

**架构：** 
1. 修改 `IslandSurface.matchesCurrentState()` 方法：当 session 为 nil 时返回 true（等待加载），当 session 处于 running 状态但有未处理的权限请求或问答时也返回 true
2. 修改 `OverlayUICoordinator.reconcileIslandSurfaceAfterStateChange()` 方法：状态不匹配时切换到会话列表而不是直接关闭

**技术栈：** Swift 6.2, SwiftUI, AppKit

---

### 任务 1：修改 IslandSurface.matchesCurrentState() 方法

**文件：**
- 修改：`Sources/OpenIslandApp/IslandSurface.swift:36-55`

- [ ] **步骤 1：定位并修改文件**

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
        return session.permissionRequest != nil || session.questionPrompt != nil
    }
}
```

**变更说明：**
- 将 `session` 为 nil 时的返回值从 `false` 改为 `true`：当 session 加载完成前不关闭卡片
- 当 session 处于 `.running` 状态时：如果之前有过权限请求或问答，返回 true 保持卡片打开

- [ ] **步骤 2：验证语法正确性**

运行：`swift build --target OpenIslandApp 2>&1 | head -20`
预期：无编译错误（网络问题导致的依赖获取失败除外）

- [ ] **步骤 3：Commit**

```bash
git add Sources/OpenIslandApp/IslandSurface.swift
git commit -m "fix: keep notification card visible when session is loading or running with pending request"
```

---

### 任务 2：修改 OverlayUICoordinator.reconcileIslandSurfaceAfterStateChange() 方法

**文件：**
- 修改：`Sources/OpenIslandApp/OverlayUICoordinator.swift:347-363`

- [ ] **步骤 1：定位并修改文件**

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

- [ ] **步骤 2：验证语法正确性**

运行：`swift build --target OpenIslandApp 2>&1 | head -20`
预期：无编译错误（网络问题导致的依赖获取失败除外）

- [ ] **步骤 3：Commit**

```bash
git add Sources/OpenIslandApp/OverlayUICoordinator.swift
git commit -m "fix: switch to session list instead of closing when notification card state mismatch"
```

---

### 任务 3：编译验证

**文件：**
- 验证：整个项目

- [ ] **步骤 1：编译项目**

运行：`swift build 2>&1 | tail -10`
预期：成功编译，无语法错误（网络问题导致的依赖获取失败除外）

- [ ] **步骤 2：运行测试（如有）**

运行：`swift test 2>&1 | tail -10`
预期：所有测试通过

- [ ] **步骤 3：Commit**（如有需要修复的内容）

```bash
git add .
git commit -m "chore: verify build and tests pass"
```