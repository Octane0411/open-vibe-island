# watchOS 原生 App 方案设计

> 前置文档：[watch-notification-design.md](./watch-notification-design.md)
> 现状：macOS 端 HTTP endpoint + iOS app 已跑通，通知镜像方案验证发现不满足需求

---

## 为什么需要原生 watchOS App

当前方案依赖 iOS 本地通知的 Watch 镜像，有一个系统级限制：
**iPhone 解锁时通知不会镜像到 Watch。** 只有 iPhone 锁屏状态下，通知才会转到手表。

这不符合使用场景——开发者经常在看 iPhone 的同时等待 agent 响应，此时手表收不到震动。

原生 watchOS app 的优势：
- **任何时候都能震动**（通过 WatchConnectivity 发消息触发 haptic）
- **自定义 UI**（比镜像通知更丰富的交互界面）
- **主动推送**（不依赖 iOS 通知系统的镜像策略）

---

## 架构变更

### 现有链路（不变）

```
Agent → Hook → BridgeServer → AppModel → WatchNotificationRelay → WatchHTTPEndpoint
                                                                        │
                                                                   SSE (局域网)
                                                                        │
                                                                   iPhone App
```

### 新增链路

```
iPhone App (ConnectionManager)
    │
    │  收到 SSE 事件
    │
    ├─→ 1. WCSession.sendMessage()        ← 实时通道，Watch 可达时
    │       或 transferUserInfo()          ← 排队通道，Watch 不可达时也能送达
    │
    ↓
watchOS App (OpenIslandWatch)
    │
    ├─→ 2. WKInterfaceDevice.play(.notification)   ← 震动
    ├─→ 3. 显示事件卡片 UI（Allow/Deny 按钮）
    │
    │  用户点击
    │
    ├─→ 4. WCSession.sendMessage(reply)    ← 回传决策到 iPhone
    │
    ↓
iPhone App
    │
    ├─→ 5. HTTP POST /resolution           ← 回传 Mac
    │
    ↓
macOS App → Agent 继续执行
```

---

## watchOS App 设计

### 项目结构

```
ios/
├── OpenIslandMobile.xcodeproj
├── OpenIslandMobile/
│   ├── ...（现有代码）
│   └── WatchConnectivityManager.swift       ← 新增：iPhone 端 WCSession
│
├── OpenIslandWatch/                          ← 新增 watchOS target
│   ├── OpenIslandWatchApp.swift              ← SwiftUI 入口
│   ├── ContentView.swift                     ← 主界面：待处理列表
│   ├── EventCardView.swift                   ← 事件卡片（权限/问题/完成）
│   ├── SessionConnectivityDelegate.swift     ← WCSession delegate
│   └── HapticManager.swift                   ← 震动管理
│
└── Shared/                                   ← iOS + watchOS 共享
    └── WatchMessage.swift                    ← WCSession 消息类型定义
```

### 核心类

#### 1. WatchMessage（共享）

iPhone 和 Watch 之间的消息类型：

```swift
/// iPhone → Watch
enum WatchMessage: Codable {
    case permissionRequest(PermissionPayload)
    case question(QuestionPayload)
    case sessionCompleted(CompletionPayload)
    case resolved(requestID: String)       // Mac 侧已处理，Watch 清理 UI

    struct PermissionPayload: Codable {
        let requestID: String
        let sessionID: String
        let agentTool: String
        let title: String
        let summary: String
        let workingDirectory: String?
    }

    struct QuestionPayload: Codable {
        let requestID: String
        let sessionID: String
        let agentTool: String
        let title: String
        let options: [String]
    }

    struct CompletionPayload: Codable {
        let sessionID: String
        let agentTool: String
        let summary: String
    }
}

/// Watch → iPhone
enum WatchResponse: Codable {
    case resolution(requestID: String, action: String)  // "allow" / "deny" / 选项文本
}
```

#### 2. WatchConnectivityManager（iPhone 端）

```swift
class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// 发送事件到 Watch
    func sendEvent(_ message: WatchMessage) {
        let data = try? JSONEncoder().encode(message)
        let dict = ["payload": data]

        if WCSession.default.isReachable {
            // Watch 可达：实时发送，带 reply handler 接收回传
            WCSession.default.sendMessage(dict, replyHandler: { reply in
                // Watch 回传的决策
                self.handleWatchReply(reply)
            })
        } else {
            // Watch 不可达：排队发送，Watch 激活时收到
            WCSession.default.transferUserInfo(dict)
        }
    }

    // Watch 回传决策 → HTTP POST /resolution
    func handleWatchReply(_ reply: [String: Any]) { ... }
}
```

#### 3. watchOS App 主界面

```swift
@main
struct OpenIslandWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.sessionManager)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        NavigationStack {
            if sessionManager.pendingEvents.isEmpty {
                // 空状态：已连接 / 未连接
                ConnectionStatusView()
            } else {
                // 待处理事件列表
                List(sessionManager.pendingEvents) { event in
                    EventCardView(event: event)
                }
            }
        }
    }
}
```

#### 4. EventCardView（事件卡片）

```swift
struct EventCardView: View {
    let event: WatchMessage
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        switch event {
        case .permissionRequest(let payload):
            VStack(alignment: .leading, spacing: 8) {
                Label(payload.agentTool, systemImage: "gearshape")
                    .font(.caption)
                Text(payload.title)
                    .font(.headline)
                Text(payload.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Allow") {
                        sessionManager.resolve(requestID: payload.requestID, action: "allow")
                    }
                    .tint(.green)

                    Button("Deny") {
                        sessionManager.resolve(requestID: payload.requestID, action: "deny")
                    }
                    .tint(.red)
                }
            }

        case .question(let payload):
            VStack(alignment: .leading, spacing: 8) {
                Label(payload.agentTool, systemImage: "questionmark.bubble")
                    .font(.caption)
                Text(payload.title)
                    .font(.headline)

                ForEach(payload.options, id: \.self) { option in
                    Button(option) {
                        sessionManager.resolve(requestID: payload.requestID, action: option)
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .sessionCompleted(let payload):
            VStack(alignment: .leading, spacing: 4) {
                Label(payload.agentTool, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(payload.summary)
                    .font(.caption2)
                    .lineLimit(3)
            }

        default:
            EmptyView()
        }
    }
}
```

#### 5. HapticManager

```swift
import WatchKit

struct HapticManager {
    static func playForEvent(_ message: WatchMessage) {
        switch message {
        case .permissionRequest:
            // 权限请求：强震动
            WKInterfaceDevice.current().play(.notification)
        case .question:
            // 问题：中等震动
            WKInterfaceDevice.current().play(.directionUp)
        case .sessionCompleted:
            // 完成：轻震动
            WKInterfaceDevice.current().play(.success)
        default:
            break
        }
    }
}
```

#### 6. WatchSessionManager（Watch 端）

```swift
class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published var pendingEvents: [WatchMessage] = []
    @Published var isConnected = false

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // 收到 iPhone 实时消息
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message["payload"] as? Data,
              let event = try? JSONDecoder().decode(WatchMessage.self, from: data) else { return }

        DispatchQueue.main.async {
            // 震动
            HapticManager.playForEvent(event)

            switch event {
            case .resolved(let requestID):
                // Mac 侧已处理，移除对应事件
                self.pendingEvents.removeAll { $0.requestID == requestID }
            default:
                self.pendingEvents.append(event)
            }
        }

        // 保存 replyHandler 供用户操作后回传
        self.pendingReplyHandlers[event.requestID] = replyHandler
    }

    // 收到排队消息（Watch 之前不可达时 iPhone 发的）
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        // 同上逻辑，但没有 replyHandler，需要用 sendMessage 回传
    }

    func resolve(requestID: String, action: String) {
        // 先通过 replyHandler 回传（如果有）
        if let handler = pendingReplyHandlers.removeValue(forKey: requestID) {
            let response = try? JSONEncoder().encode(WatchResponse.resolution(requestID: requestID, action: action))
            handler(["response": response as Any])
        } else {
            // fallback: 主动 sendMessage
            let response = try? JSONEncoder().encode(WatchResponse.resolution(requestID: requestID, action: action))
            WCSession.default.sendMessage(["response": response as Any], replyHandler: nil)
        }

        // 移除已处理事件
        pendingEvents.removeAll { $0.requestID == requestID }

        // 轻震确认
        WKInterfaceDevice.current().play(.click)
    }

    private var pendingReplyHandlers: [String: ([String: Any]) -> Void] = [:]
}
```

---

## iPhone 端改动

### ConnectionManager 新增

在收到 SSE 事件后，除了发本地通知，同时通过 WCSession 发送到 Watch：

```swift
// 现有逻辑：发本地通知（保留，作为 fallback）
notificationManager?.scheduleNotification(for: event)

// 新增：通过 WCSession 发到 Watch
WatchConnectivityManager.shared.sendEvent(watchMessage)
```

### 本地通知保留

本地通知作为 fallback 保留：
- Watch app 没装时，通知镜像仍然能用（iPhone 锁屏时）
- Watch 不可达时，通知至少会在 iPhone 上显示

---

## 实现步骤

### Step 6: WatchConnectivity 桥接

**目标**：iPhone 和 Watch 之间建立 WCSession 通信。

- 新增 `Shared/WatchMessage.swift`（共享消息类型）
- 新增 `WatchConnectivityManager.swift`（iPhone 端）
- ConnectionManager 收到 SSE 事件后调用 WCSession 发送
- 在 Xcode 中为 iOS target 启用 WatchConnectivity capability

**验证**：iPhone 端日志确认 WCSession 激活、消息发送成功。

### Step 7: watchOS App 骨架

**目标**：新建 watchOS target，收到消息能震动。

- Xcode 中 File → New → Target → watchOS App
- 实现 `WatchSessionManager`（WCSession delegate）
- 收到消息 → `WKInterfaceDevice.play(.notification)` → 震动
- 简单 UI 显示 "等待事件..."

**验证**：触发 agent 事件 → Watch 震动。

### Step 8: watchOS 事件卡片 UI

**目标**：Watch 上显示可操作的事件卡片。

- 实现 `EventCardView`（权限请求 Allow/Deny、问题选项、完成摘要）
- 实现 `ContentView`（待处理事件列表）
- 待处理事件为空时显示连接状态

**验证**：Watch 上看到事件卡片，按钮可点击。

### Step 9: Watch → Mac 决策回传

**目标**：Watch 上的操作能传回 Mac 执行。

- Watch 点击按钮 → WCSession reply → iPhone → HTTP POST /resolution → Mac
- Mac 端执行 resolution → agent 继续
- 同时发 SSE `actionableStateResolved` → iPhone → WCSession → Watch 清除对应事件

**验证**：端到端 — agent 请求权限 → Watch 震动 → 点 Allow → agent 继续。

### Step 10: 打磨

- 不同事件类型不同的震动模式
- Watch 事件自动过期清理
- iPhone 前台时 Watch 仍能震动（核心卖点验证）
- Watch complication 显示待处理数量（可选）
- 错误处理：WCSession 断开重连、消息丢失重试

---

## WatchConnectivity 注意事项

1. **WCSession 生命周期**：必须在 app 启动时尽早调用 `activate()`，且只能有一个 delegate
2. **isReachable**：只有 Watch app 在前台或最近使用过时才为 true；用 `transferUserInfo` 作为 fallback
3. **后台预算**：watchOS 给后台任务很少的 CPU 时间（4-15 秒），震动和 UI 更新要快
4. **消息大小**：单条消息建议 < 64KB，我们的 payload 远小于此
5. **调试**：Xcode 可以同时 attach iOS 和 watchOS 进程，方便断点调试

---

## 与现有方案的关系

| 组件 | 是否保留 | 说明 |
|---|---|---|
| macOS WatchHTTPEndpoint | 保留 | SSE + resolution 不变 |
| macOS WatchNotificationRelay | 保留 | 事件推送逻辑不变 |
| iOS Bonjour 发现 + 配对 | 保留 | Mac ↔ iPhone 连接不变 |
| iOS SSE Client | 保留 | 接收事件的通道不变 |
| iOS 本地通知 | 保留（降级为 fallback） | Watch app 未安装时仍有用 |
| iOS → Watch 通知镜像 | 被 WCSession 替代 | 不再依赖通知镜像 |
| **新增** watchOS App | 新增 | 原生 UI + haptic |
| **新增** WCSession 通信 | 新增 | iPhone ↔ Watch 双向 |

---

## 分支策略

继续在 `feat/watch-notification` 集成分支上开发：

```
feat/watch-notification (集成分支)
    ├── Step 6 PR: feat/watch-connectivity     ← WCSession 桥接
    ├── Step 7 PR: feat/watchos-app            ← watchOS 骨架 + 震动
    ├── Step 8 PR: feat/watchos-ui             ← 事件卡片 UI
    ├── Step 9 PR: feat/watchos-resolution     ← 决策回传
    └── Step 10 PR: feat/watchos-polish        ← 打磨
```
