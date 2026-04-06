# Codex 审批通知功能 — 交接文档

## 背景

Open Island 之前没有接入 Codex 的 `PreToolUse` / `PostToolUse` hook，导致：
1. Codex 运行时工具状态（命令预览、工具名称）无法在 island 显示
2. Codex 权限审批无法通过 island 操作

## 涉及的 PR

### PR #84 — `refactor: remove CodexRolloutWatcher from live operation`
- **分支**: `worktree-refactor+codex-single-path` → `main`
- **内容**:
  - 移除 `CodexRolloutWatcher` 运行时轮询（之前 Codex 有 hook + JSONL 轮询两条数据路径，导致竞态）
  - 删除 `TrackedEventIngress` enum 和所有双路径防御代码
  - 在 `CodexHookInstaller.eventSpecs` 中注册 `PreToolUse` 和 `PostToolUse` hook
  - 保留 `CodexRolloutDiscovery` 仅用于启动时一次性恢复历史 session
- **状态**: 待合并

### PR #106 — `refactor: Codex PreToolUse notify-only`
- **分支**: `worktree-codex-notify-only` → `worktree-refactor+codex-single-path`
- **依赖**: 必须先合并 #84
- **注意**: 这个 PR 的 base 是 #84 的分支，合并 #84 后需要将 #106 的 base 改为 `main`
- **内容**:
  - Codex PreToolUse 默认为**仅通知模式**（不阻塞 Codex 自身 TUI 审批）
  - 新增用户设置开关：**"在 Island 中拦截 Codex 审批"**（Settings > General > 行为）
    - 关闭（默认）：island 显示命令通知，Codex 终端正常弹出自己的审批
    - 开启：island 接管审批，Codex 等待 island 的 Allow/Deny
  - `BridgeServer` 根据 `UserDefaults("codex.approval.intercept")` 决定行为
  - `SessionActivityUpdated` 新增 `showsNotification` 和 `requiresAttention` 字段
  - PreToolUse 通知显示橙色 attention tone
  - hook CLI 和 hooks.json 对 PreToolUse 使用 24h 超时（支持拦截模式）
- **状态**: 待合并

## 合并顺序

1. 合并 PR #84 到 `main`
2. 将 PR #106 的 base branch 改为 `main`，rebase 后合并

## 验证清单

### 基础功能（PR #84）

- [ ] `swift build` 通过
- [ ] `swift test` 全部通过
- [ ] Codex 启动时 island 正常检测到 session（SessionStart hook）
- [ ] Codex 运行时状态更新正常（工具名称、命令预览来自 PreToolUse/PostToolUse）
- [ ] Codex 完成通知正常（音效 + 面板展开 + 内容 + 10s 后自动关闭）
- [ ] Claude Code 通知不受影响
- [ ] App 启动时历史 Codex session 正常恢复

### 通知模式（PR #106，开关关闭 — 默认）

- [ ] Codex 触发 PreToolUse 时，island 弹出通知卡片
- [ ] 通知卡片显示橙色 attention tone（不是蓝色）
- [ ] 通知卡片显示命令内容（如 "Codex wants to run: git log"）
- [ ] 通知自动收起（和完成通知类似）
- [ ] Hook 立即返回，Codex 不被阻塞
- [ ] Codex 自身 TUI 审批 prompt 正常弹出

### 拦截模式（PR #106，开关开启）

- [ ] Settings > General > 行为 中有 "在 Island 中拦截 Codex 审批" 开关
- [ ] 开启后，Codex PreToolUse 时 island 弹出审批卡片（橙色，带 Allow/Deny 按钮）
- [ ] Codex 终端被阻塞等待 island 决策
- [ ] 点击 "Allow Once" → Codex 继续执行
- [ ] 点击 "Deny" → Codex 收到拒绝指令
- [ ] 审批卡片收起后，再展开控制中心，等待审批的 session 仍显示审批按钮
- [ ] 开关切换即时生效，不需要重装 hook

### Claude Code 回归测试

- [ ] Claude Code 权限审批流程正常（不受 Codex 改动影响）
- [ ] Claude Code 问答功能正常
- [ ] Claude Code 完成通知正常

## 已知问题

1. **launch-dev-app.sh 签名问题**: 脚本将 resource bundle 放在 `.app` 根目录，导致 codesign 失败。临时解决方案：手动将 `OpenIsland_OpenIslandApp.bundle` 从 `.app/` 移到 `.app/Contents/Resources/` 后重新签名。这是已有问题，不在本次改动范围内。

2. **审批卡片收起后按钮消失**: `IslandPanelView` 中列表模式下，`waitingForApproval` / `waitingForAnswer` 的 session 现在始终标记为 `isActionable`（已在 PR #106 的 worktree 中修复但未单独提交，需要验证是否已包含在最终代码中）。

## 关键文件

| 文件 | 改动说明 |
|------|---------|
| `Sources/OpenIslandCore/CodexHookInstaller.swift` | 注册 PreToolUse/PostToolUse，24h 超时 |
| `Sources/OpenIslandCore/BridgeServer.swift` | PreToolUse 处理分支（通知/拦截） |
| `Sources/OpenIslandHooks/main.swift` | Codex PreToolUse 使用长超时 |
| `Sources/OpenIslandCore/AgentEvent.swift` | `showsNotification` + `requiresAttention` 字段 |
| `Sources/OpenIslandCore/AgentSession.swift` | `activityRequiresAttention` 字段 |
| `Sources/OpenIslandApp/IslandSurface.swift` | 通知触发 + running 状态匹配 |
| `Sources/OpenIslandApp/AgentSession+Presentation.swift` | attention tone 逻辑 |
| `Sources/OpenIslandApp/AppModel.swift` | `codexApprovalIntercept` 设置 |
| `Sources/OpenIslandApp/Views/SettingsView.swift` | 拦截开关 UI |
| `Sources/OpenIslandApp/Views/IslandPanelView.swift` | 审批按钮始终显示 |

## 构建与测试

```bash
# 在 worktree-codex-notify-only 分支
swift build
swift test

# 启动 dev app 测试
zsh scripts/launch-dev-app.sh
```
