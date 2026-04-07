# Apple Watch Notification Design

## 动机

Agent 等待权限批准或回答问题时，开发者可能没有注意到 — 无论是在 Mac 前专注写代码，还是离开去倒杯咖啡。
手腕上的震动是比屏幕上的灵动岛更强的感官通道：不会被其他窗口遮挡，不会在专注时被忽略。
Watch 通知让开发者第一时间感知到 agent 需要关注，并可以快速操作。

## 设计原则

1. **手腕 = 快速决策面板**，不是完整控制面板。只推需要人类干预的事件，不显示终端输出。
2. **5 秒内完成交互**。看到通知 → 理解上下文 → 做出动作。
3. **静默优先**。运行中的 session 不打扰，只在需要注意时震动。
4. **Fail open**。推送链路断了不影响 Mac 端正常工作。
5. **零额外进程**。复用现有 macOS app 的 BridgeServer，不引入新的中间服务。

---

## 交互设计

### 推送哪些事件？

| 事件 | 推送？ | 理由 |
|---|---|---|
| `permissionRequested` | **是** | Agent 被阻塞，等人批准 |
| `questionAsked` | **是** | Agent 被阻塞，等人回答 |
| `sessionCompleted` | **是** | 任务完成，值得知道 |
| `sessionStarted` | 否 | 用户自己启动的，不需要通知 |
| `activityUpdated` | 否 | 太频繁，无需关注 |

### 通知样式

#### 1. 权限请求通知

```
┌─────────────────────────┐
│  🔧 Claude Code         │
│  ───────────────────     │
│  wants to run:           │
│  "rm -rf build/"         │
│                          │
│  📁 ~/Projects/my-app    │
│                          │
│  ┌─────────┐ ┌────────┐ │
│  │  Allow  │ │  Deny  │ │
│  └─────────┘ └────────┘ │
└─────────────────────────┘
```

**字段映射：**
- 标题：`PermissionRequest.title`（工具名）
- 正文：`PermissionRequest.summary`（操作摘要）
- 副标题：session 的工作目录（来自 `JumpTarget.workingDirectory`）
- 动作按钮：`primaryActionTitle` / `secondaryActionTitle`

**Watch 交互流程：**
1. 手腕震动（haptic: `.notification`）
2. 抬腕看到通知卡片
3. 点 Allow → WCSession 回传 → macOS app 执行 `PermissionResolution.allowOnce`
4. 点 Deny → WCSession 回传 → macOS app 执行 `PermissionResolution.deny`
5. 不操作 → 无影响，Mac 端仍在等待，用户可以回到电脑操作

#### 2. 问题回答通知

```
┌─────────────────────────┐
│  💬 Codex               │
│  ───────────────────     │
│  asks:                   │
│  "Which database         │
│   should I use?"         │
│                          │
│  ┌───────────────────┐   │
│  │  PostgreSQL       │   │
│  │  SQLite           │   │
│  │  MySQL            │   │
│  └───────────────────┘   │
│                          │
│  ┌──────────────────┐    │
│  │ Open on Mac ↗    │    │
│  └──────────────────┘    │
└─────────────────────────┘
```

**字段映射：**
- 标题：`QuestionPrompt.title`
- 选项列表：`QuestionPrompt.options`（最多显示 4 个，超出显示"Open on Mac"）

**Watch 交互流程：**
1. 手腕震动
2. 看到问题和选项
3. 点选某个选项 → WCSession 回传 → macOS app 提交 `QuestionPromptResponse`
4. 选项太多或太复杂 → 点"Open on Mac" → 仅标记为已读，回 Mac 处理

#### 3. Session 完成通知（最重要）

```
┌─────────────────────────┐
│  ✅ Claude Code          │
│  ───────────────────     │
│  Task completed          │
│  "Add user auth flow"    │
│                          │
│  ┌──────────────────┐    │
│  │   Dismiss        │    │
│  └──────────────────┘    │
└─────────────────────────┘
```

**字段映射：**
- 标题：agent 工具名
- 正文：`SessionCompleted.summary`

**这是 Watch 通知最核心的价值** — agent 完成任务后开发者可能完全没注意到，灵动岛容易被忽略，但手腕震动不会。纯信息性，不需要操作。

---

## 通信架构

### 方案：Bonjour + HTTP 本地通信（无云服务、无额外进程）

通信分为两段，使用不同的技术：

- **macOS ↔ iPhone**：Bonjour 局域网发现 + HTTP（需要同一 WiFi）
- **iPhone ↔ Watch**：WCSession（Apple Watch Connectivity 框架，支持蓝牙和 WiFi）

核心思路：在现有 macOS app 内新增一个轻量 HTTP 端点，iPhone app 通过 Bonjour 自动发现并连接。不需要额外进程。

```
Claude Code / Codex
    │
    │  Hook (stdin/stdout)
    ↓
OpenIslandHooks (CLI)
    │
    │  Unix socket
    ↓
BridgeServer (macOS app 内, 已有)
    │
    │  AppModel 状态变更
    ↓
WatchHTTPEndpoint (新增, macOS 端)
    │  - Bonjour 广播 _openisland._tcp
    │  - /events (SSE 实时推送)
    │  - /resolution (接收操作回传)
    │
    │  HTTP (局域网, 同一 WiFi)
    ↓
iPhone App (OpenIslandMobile)
    │  - Bonjour 发现 Mac
    │  - SSE 接收事件 → 本地通知
    │  - WCSession 中继到 Watch
    │
    │  WCSession (蓝牙/WiFi)
    ↓
Watch (通知镜像 + UNNotificationAction)
    │
    │  用户点击 Allow / Deny / 选项
    ↓
iPhone App
    │
    │  HTTP POST /resolution (回传决策)
    ↓
WatchHTTPEndpoint (macOS 端)
    │
    │  调用 AppModel 执行 resolution
    ↓
BridgeServer → Hook 进程 → Agent 继续执行
```

### 为什么选 Bonjour + HTTP

| 维度 | Bonjour + HTTP | CloudKit |
|---|---|---|
| 延迟 | 亚秒级（局域网直连） | 1-3 秒（云端中转） |
| 网络依赖 | 同一 WiFi，无需互联网 | 需要互联网 |
| 隐私 | 数据完全留在本地 | 经过 Apple 服务器 |
| 额外进程 | 无（复用 macOS app） | 无 |
| 额外配置 | 无 | 需要 CloudKit container、schema、subscription |
| 复杂度 | 低 | 高 |

**限制：Mac 和 iPhone 必须在同一 WiFi 下。** 实际使用中这几乎不是问题 — 开发时 Mac 和手机通常在同一网络。离开 WiFi 后通知链路中断，但不影响 Mac 端正常工作（fail open）。

### HTTP 端点设计

macOS app 内新增一个轻量 HTTP server（复用 NWListener），提供以下端点：

| 端点 | 方法 | 说明 |
|---|---|---|
| `/events` | GET (SSE) | 实时事件流，iPhone 长连接接收推送 |
| `/resolution` | POST | iPhone 回传用户在 Watch 上的操作决策 |
| `/status` | GET | 当前连接状态、活跃 session 数 |

### 事件推送格式（SSE）

```
event: permissionRequested
data: {"sessionID":"abc-123","agentTool":"claudeCode","title":"Bash: rm -rf build/","summary":"Remove build directory","workingDirectory":"~/Projects/my-app","primaryAction":"Allow","secondaryAction":"Deny","requestID":"req-456"}

event: sessionCompleted
data: {"sessionID":"abc-123","agentTool":"codex","summary":"Add user auth flow"}
```

### 操作回传格式（HTTP POST）

```json
POST /resolution
{
    "requestID": "req-456",
    "action": "allow"          // "allow" | "deny" | 选项文本
}
```

### 配对机制

首次连接需要确认身份，防止连到别人的 Mac。

**配对流程：**

```
Mac                              iPhone
 │                                 │
 │  1. Bonjour 广播                │
 │  _openisland._tcp               │
 │  TXT: { name: "王的MacBook Pro" } │
 │ ──────────────────────────────→ │
 │                                 │  2. 发现 Mac，显示设备名
 │                                 │     用户点击连接
 │                                 │
 │  3. Mac 显示 4 位配对码          │
 │  (macOS app 设置页 / 通知)       │
 │                                 │
 │                                 │  4. iPhone 输入配对码
 │  ←──────────────────────────── │
 │                                 │
 │  5. 验证通过                     │
 │     生成 session token           │
 │     返回给 iPhone                │
 │ ──────────────────────────────→ │
 │                                 │  6. 保存 token
 │                                 │     后续请求带 token，免配对
```

**设计要点：**
- 4 位数字码（比 claude-watch 的 6 位更简洁，安全性对局域网场景足够）
- 配对码有效期 2 分钟，过期重新生成
- 配对成功后 iPhone 保存 session token，后续自动连接
- Mac 端可以在设置页查看已配对设备、撤销配对
- 同一 WiFi 下发现多台 Mac 时，iPhone 列出设备名让用户选择

### 用户 Setup 流程

1. App Store 下载 iPhone app（一次性）
2. 打开 iPhone app → 授权通知权限（一次性）
3. Mac 和 iPhone 在同一 WiFi → iPhone 自动发现 Mac
4. Mac 上显示 4 位配对码 → iPhone 输入 → 配对完成（一次性）
5. 之后自动连接，无需再操作

---

## 工程拆分

### 需要新建的 Target

| Target | 类型 | 职责 |
|---|---|---|
| `OpenIslandMobile` | iOS App | Bonjour 发现 Mac、SSE 接收事件、本地通知、WCSession 中继到 Watch |
| `OpenIslandShared` | 共享 Framework | 消息类型定义、编解码，macOS 和 iOS 共用 |

**不需要独立 watchOS App target**（v1）。Watch 通知通过 iOS app 的 `UNNotificationCategory` + `UNNotificationAction` 实现，利用系统自动镜像。

### macOS 端改动

在 `OpenIslandApp` 中新增 `WatchHTTPEndpoint`：

```swift
/// 在 macOS app 内启动一个轻量 HTTP server，通过 Bonjour 广播服务。
/// iPhone app 连接后通过 SSE 接收事件，通过 POST 回传操作决策。
class WatchHTTPEndpoint {
    let appModel: AppModel

    // Bonjour 广播 _openisland._tcp
    func startAdvertising() { ... }

    // SSE: 当 session phase 变为 waitingForApproval / waitingForAnswer / completed 时推送事件
    func handleEventsStream(_ connection: NWConnection) { ... }

    // POST /resolution: 收到 iPhone 回传的操作决策，驱动 AppModel 执行
    func handleResolution(_ request: HTTPRequest) { ... }
}
```

### iOS App（OpenIslandMobile）

**极简，但有足够内容过审：**

1. **主页面**：连接状态 + 最近通知列表（权限请求/问题/完成）
2. **设置页面**：通知类型开关、静默模式
3. **后台能力**：
   - Bonjour 发现 macOS app → SSE 长连接接收事件
   - 收到事件 → 创建 `UNNotificationRequest`（带 category 和 action）→ 自动镜像到 Watch
   - Watch 上用户点击操作 → `UNUserNotificationCenter.delegate` 回调 → HTTP POST 回传 Mac
   - WCSession 与 Watch 通信（Watch 操作回传）

**通知 Category 定义：**

```swift
// 权限请求
let allowAction = UNNotificationAction(identifier: "ALLOW", title: "Allow", options: [])
let denyAction = UNNotificationAction(identifier: "DENY", title: "Deny", options: [.destructive])
let permissionCategory = UNNotificationCategory(
    identifier: "PERMISSION_REQUEST",
    actions: [allowAction, denyAction],
    intentIdentifiers: []
)

// 问题回答 — 动态生成 category（每个问题的选项不同）
// 使用 category identifier 编码选项信息，如 "QUESTION_opt1_opt2_opt3"
```

---

## 用户配置

在 macOS app 的设置中新增：

- **Watch 通知开关**（默认关闭）
- **通知类型勾选**：权限请求 / 问题 / 完成通知
- **静默模式**：完成通知不震动
- **连接状态**：显示 iPhone 是否已配对、Watch 是否可达

---

## 实现步骤

### Step 1: macOS 端 — WatchHTTPEndpoint
- 在 macOS app 内用 `NWListener` 起一个 HTTP server
- 注册 Bonjour 服务 `_openisland._tcp`
- 实现 `/events` SSE 端点：监听 `AppModel` 的 session phase 变化，推送 JSON 事件
- 实现 `/resolution` POST 端点：接收决策，调用 `AppModel` 执行
- **可以纯 Mac 端开发和测试**（用 curl 模拟 iPhone 连接验证 SSE 推送）

### Step 2: iOS App — 骨架 + Bonjour 发现 + 配对
- 新建 Xcode project（OpenIslandMobile）
- 用 `NWBrowser` 搜索 `_openisland._tcp`，发现 Mac 后显示设备名
- 实现配对流程：用户选择 Mac → 输入 4 位配对码 → 获取 session token
- 连接 SSE，控制台打印收到的事件
- **验证 Mac ↔ iPhone 通信链路 + 配对机制**

### Step 3: iOS App — 本地通知 + Watch 镜像
- 注册 `UNNotificationCategory`（权限请求、问题、完成）
- SSE 收到事件 → 创建 `UNNotificationRequest` → 发出本地通知
- **戴上 Watch 验证通知镜像是否正常**

### Step 4: 双向交互
- `UNUserNotificationCenter.delegate` 处理 Watch 上的按钮点击
- 点击 → HTTP POST `/resolution` 回传 Mac
- Mac 端执行 `PermissionResolution` → agent 继续
- **端到端验证：agent 请求权限 → Watch 震动 → 点 Allow → agent 继续**

### Step 5: 打磨
- iOS app UI（连接状态页、通知历史列表、已配对设备管理）
- macOS 设置页（Watch 通知开关、配对码显示、已配对设备列表）
- 后台 SSE 重连逻辑
- 错误处理和边界情况

### 后续扩展（可选）
- 如果通知镜像不够用，开发独立 watchOS App target
- Session 列表概览、Complication 显示待处理数量

---

## 开放问题

1. **iOS app 审核** — 需要足够的 UI 内容。方案：最近通知历史列表 + 设置页 + 连接状态页。
2. **后台 SSE 连接** — iPhone app 在后台时 SSE 长连接可能被系统断开。需要处理重连逻辑，以及评估是否需要 Background Modes（如 `background fetch` 或 `remote notifications`）。
3. **多 Mac 发现** — 同一 WiFi 下多台 Mac 运行 Open Island 时，Bonjour 会发现多个服务。iPhone 列出设备名让用户选择并配对，token 机制确保后续自动连接正确的 Mac。
4. **Xcode 项目结构** — 当前项目用 Swift Package Manager，iOS target 需要 Xcode project 或 workspace。需评估是在 Package.swift 中添加还是单独建 Xcode project。
5. **局域网权限** — iOS 14+ 首次访问局域网时会弹出权限请求，需要在 Info.plist 中声明 `NSLocalNetworkUsageDescription` 和 Bonjour 服务类型。

---

## 参考

- [claude-watch](https://github.com/shobhit99/claude-watch) — 类似项目，使用 Node.js Bridge + Bonjour + WCSession 方案。我们的方案更简洁：复用已有 macOS app，不需要额外 Node.js 进程。
- [NWListener (Network.framework)](https://developer.apple.com/documentation/network/nwlistener) — macOS 端轻量 HTTP server
- [NWBrowser (Bonjour)](https://developer.apple.com/documentation/network/nwbrowser) — iOS 端局域网服务发现
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession) — iPhone ↔ Watch 通信
- [UNNotificationAction](https://developer.apple.com/documentation/usernotifications/unnotificationaction) — Watch 通知操作按钮
