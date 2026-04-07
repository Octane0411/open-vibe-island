# Apple Watch 通知 — 实现计划

> 设计文档：[watch-notification-design.md](./watch-notification-design.md)
> 分支：`worktree-feat-watch-notification`

---

## 架构总览

```
┌─ Mac (OpenIslandApp 进程内) ──────────────────────────────────────┐
│                                                                   │
│  Agent → Hook → BridgeServer → AppModel                           │
│                                    │                              │
│                                    │ 监听 phase 变化               │
│                                    ↓                              │
│                           WatchNotificationRelay                  │
│                                    │                              │
│                                    ↓                              │
│                           WatchHTTPEndpoint                       │
│                           ┌────────────────────┐                  │
│                           │ Bonjour 广播        │                  │
│                           │ GET  /events (SSE)  │── 推送事件 ──┐   │
│                           │ POST /resolution    │← 回传决策 ─┐│   │
│                           │ POST /pair          │            ││   │
│                           │ GET  /status        │            ││   │
│                           └────────────────────┘            ││   │
└──────────────────────────────────────────────────────────────┼┼───┘
                                                               ││
                         ～～～ 同一 WiFi ～～～                   ││
                                                               ││
┌─ iPhone (OpenIslandMobile) ──────────────────────────────────┼┼───┐
│                                                              ││   │
│  NWBrowser (Bonjour 发现) → SSEClient (长连接) ←─────────────┘│   │
│       │                                                       │   │
│       ↓ 收到事件                                               │   │
│  UNNotificationRequest (本地通知, 带 Action)                    │   │
│       │                                                       │   │
│       │ 系统自动镜像                                            │   │
│       ↓                                                       │   │
│  Apple Watch (通知卡片 + Allow/Deny 按钮)                       │   │
│       │                                                       │   │
│       │ 用户点击                                                │   │
│       ↓                                                       │   │
│  UNNotificationCenter.delegate → HTTP POST /resolution ───────┘   │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Step 1: macOS 端 — WatchHTTPEndpoint

**目标**：macOS app 内新增轻量 HTTP server + Bonjour 广播。可用 curl 独立测试。

### 新增文件

| 文件 | 职责 |
|---|---|
| `Sources/OpenIslandCore/WatchHTTPEndpoint.swift` | NWListener TCP server，Bonjour 广播，HTTP 路由，配对/token 管理 |
| `Sources/OpenIslandCore/WatchNotificationRelay.swift` | 监听 AppModel 状态变化，构造 SSE 事件，处理 resolution 回传 |

### WatchHTTPEndpoint 详细设计

- 用 `NWListener`（Network.framework）创建 TCP server，自带 Bonjour 支持
- 服务类型：`_openisland._tcp`，TXT record 含设备名
- 手动解析 HTTP/1.1 请求（NWListener 给的是 raw TCP，需要自己解析 HTTP）
- SSE 响应：`Content-Type: text/event-stream`，保持连接不关闭

**端点：**

| 路径 | 方法 | 认证 | 功能 |
|---|---|---|---|
| `POST /pair` | JSON | 无 | 提交 4 位配对码，验证通过返回 session token |
| `GET /events` | SSE | Bearer token | 实时事件流 |
| `POST /resolution` | JSON | Bearer token | Watch 操作决策回传 |
| `GET /status` | JSON | Bearer token | 连接状态、活跃 session 数 |

**配对流程：**
- macOS app 启动时生成随机 4 位数字码，2 分钟有效
- 用户在 macOS 设置页或通知中看到配对码
- iPhone app 提交配对码 → 验证通过 → 返回 UUID session token
- token 持久化在 Keychain，后续请求免配对

### WatchNotificationRelay 详细设计

- 持有 `WatchHTTPEndpoint` 引用
- 监听 `AppModel.state` 变化（通过 `applyTrackedEvent()` 回调）
- 过滤需要推送的事件：
  - `sessionCompleted` → 推送完成通知
  - `permissionRequested` → 推送权限请求（含 requestID）
  - `questionAsked` → 推送问题（含选项）
- 收到 `/resolution` POST → 根据 requestID 找到对应 session → 调用 BridgeServer 的 resolution 逻辑

### 修改文件

| 文件 | 改动 |
|---|---|
| `Sources/OpenIslandApp/AppModel.swift` | 新增 `watchRelay` 属性；`applyTrackedEvent()` (~L745) 中事件应用后通知 relay |
| `Sources/OpenIslandCore/BridgeServer.swift` | 暴露 `resolvePendingClaudeInteraction()` (~L1638) 和 `resolvePendingClaudeQuestion()` (~L1704) 或通过 BridgeCommand 转发 |

### 验证

```bash
swift build

# 启动 app 后：
# 1. 配对
curl -X POST -d '{"code":"1234"}' http://<mac-ip>:<port>/pair
# 返回 {"token":"uuid-xxx"}

# 2. 监听 SSE
curl -N -H "Authorization: Bearer uuid-xxx" http://<mac-ip>:<port>/events

# 3. 触发 agent 事件 → 观察 curl 输出
# 4. 回传决策
curl -X POST -H "Authorization: Bearer uuid-xxx" \
  -d '{"requestID":"req-456","action":"allow"}' \
  http://<mac-ip>:<port>/resolution
```

---

## Step 2: iOS App — 骨架 + Bonjour 发现 + 配对

**目标**：新建 iOS app，实现 Bonjour 发现和配对。

### 项目结构

```
ios/
├── OpenIslandMobile.xcodeproj
└── OpenIslandMobile/
    ├── App.swift                    # SwiftUI 入口
    ├── ContentView.swift            # 主页：连接状态 + 通知历史
    ├── Network/
    │   ├── BonjourDiscovery.swift   # NWBrowser 搜索 _openisland._tcp
    │   ├── SSEClient.swift          # HTTP SSE 长连接
    │   └── ConnectionManager.swift  # 发现→配对→SSE 生命周期
    ├── Views/
    │   ├── PairingView.swift        # Mac 列表 + 输入配对码
    │   └── SettingsView.swift       # 通知类型开关
    ├── Models/
    │   └── WatchEvent.swift         # 事件数据模型（与 macOS 端共享定义）
    └── Info.plist                   # NSLocalNetworkUsageDescription + NSBonjourServices
```

### Info.plist 关键配置

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Open Island needs to discover your Mac on the local network to receive agent notifications.</string>
<key>NSBonjourServices</key>
<array>
    <string>_openisland._tcp</string>
</array>
```

### 验证

- iPhone 上运行 → 发现 Mac → 输入配对码 → 连接成功
- SSE 事件在控制台打印

---

## Step 3: iOS App — 本地通知 + Watch 镜像

**目标**：SSE 事件转为本地通知，Watch 自动镜像显示。

### 新增文件

| 文件 | 职责 |
|---|---|
| `NotificationManager.swift` | 注册 category/action，事件→通知转换 |

### 通知 Category 定义

```swift
// PERMISSION_REQUEST: Allow + Deny 按钮
// QUESTION: 动态选项（最多 4 个 action）
// SESSION_COMPLETED: 无按钮，纯信息
```

### 验证

- 触发 agent 权限请求 → iPhone 通知 → Watch 镜像 → 看到 Allow/Deny 按钮

---

## Step 4: 双向交互

**目标**：Watch 按钮点击 → 回传 Mac 执行。

### 关键实现

- `UNUserNotificationCenter.delegate` 的 `didReceive response` 回调
- 根据 `response.actionIdentifier` 判断操作（ALLOW/DENY/选项文本）
- `ConnectionManager.postResolution(requestID:action:)` → HTTP POST

### 验证

- 端到端：agent 请求权限 → Watch 震动 → 点 Allow → agent 继续执行

---

## Step 5: 打磨

- iOS app UI：连接状态页、通知历史列表、已配对设备管理
- macOS 设置页：Watch 通知开关、配对码显示、已配对设备
- SSE 后台重连（app 进入后台时连接可能被系统断开）
- 边界情况：token 过期、Mac 重启后重新配对、多 session 并发

---

## 关键代码路径参考

| 功能 | 文件 | 位置 |
|---|---|---|
| 事件分发入口 | `AppModel.swift` | `applyTrackedEvent()` ~L745 |
| 权限审批 | `AppModel.swift` | `approveFocusedPermission()` ~L564 |
| 问题回答 | `AppModel.swift` | `answerFocusedQuestion()` ~L577 |
| 权限 resolution 执行 | `BridgeServer.swift` | `resolvePendingClaudeInteraction()` ~L1638 |
| 问题 resolution 执行 | `BridgeServer.swift` | `resolvePendingClaudeQuestion()` ~L1704 |
| Session phase 定义 | `AgentSession.swift` | `SessionPhase` ~L51 |
| 权限请求模型 | `AgentSession.swift` | `PermissionRequest` ~L105 |
| 问题模型 | `AgentSession.swift` | `QuestionPrompt` ~L168 |
| 现有 bridge 协议 | `BridgeTransport.swift` | `BridgeEnvelope` / `BridgeCodec` |

---

## 每个 Step 可以独立开分支和 PR

- Step 1: `feat/watch-http-endpoint`
- Step 2: `feat/watch-ios-app`
- Step 3: `feat/watch-notifications`
- Step 4: `feat/watch-bidirectional`
- Step 5: `feat/watch-polish`

建议从 Step 1 开始，纯 macOS 端，用 curl 验证。
