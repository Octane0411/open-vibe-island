# 为 Agent Deck 做贡献

<strong>中文</strong> | <a href="CONTRIBUTING.md">English</a>

感谢你对 Agent Deck 项目的关注与贡献！

---

## Human Parts

*这部分内容是给人类阅读的。*

我们欢迎一切好的想法，只要你有意愿，你可以把任何想法变成这个项目的代码，并被其他人使用。

查看 [路线图](docs/roadmap.md#路线图) 了解项目方向，选一个你感兴趣的方向参与。

本项目所有代码均由 AI 产出，因此你也不应该贡献人类产出的代码。

### 如何开始

我们在让 AI 更好迭代这个项目上做了一些功夫。想要开始贡献，你需要在你的 code agent 中输入下面这段话：

```
帮我阅读这个项目的 CONTRIBUTING.md 并说明我应该如何迭代这个项目，
然后向我列出你已知的信息，例如发布构建/仓库架构/代码规范/在仓库中的PR规范等等。
```

### 用你的代理上报 Bug

如果你遇到了问题，把下面的 prompt 复制到你的代理（Claude Code、Codex 等）中，它会自动收集环境信息并帮你创建一个结构清晰的 issue。

<details>
<summary>点击展开 prompt</summary>

```
我在使用 Agent Deck (https://github.com/Octane0411/agent-deck) 时遇到了问题。

请帮我提交一个 GitHub issue，步骤如下：

1. 收集我的环境信息：
   - 运行 `sw_vers` 获取 macOS 版本
   - 运行 `swift --version` 获取 Swift 版本
   - 检查 Agent Deck 是否在运行：`ps aux | grep -i "agentdeck\|AgentDeckApp" | grep -v grep`
   - 获取应用版本：`defaults read ~/Applications/Open\ Island\ Dev.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown"`
   - 检查我正在使用的终端

2. 询问我：
   - 我期望发生什么
   - 实际发生了什么
   - 复现步骤

3. 使用 `gh issue create` 在 GitHub 上创建 issue，格式如下：
   - 标题：简洁的摘要
   - 正文包含以下部分：**环境信息**、**问题描述**、**复现步骤**、**期望行为 vs 实际行为**
   - 如适用，添加 "bug" 标签

仓库：Octane0411/agent-deck
```

</details>

### 用你的代理提交功能建议

有新想法？让你的代理帮你起草提案。

<details>
<summary>点击展开 prompt</summary>

```
我想为 Agent Deck (https://github.com/Octane0411/agent-deck) 提一个功能建议。

请帮我提交一个 GitHub issue，步骤如下：

1. 询问我：
   - 我想要什么功能
   - 为什么有用（解决什么问题）
   - 对实现方式有什么想法

2. 使用 `gh issue create` 在 GitHub 上创建 issue，格式如下：
   - 标题：简洁的摘要，前缀为 "feat: "
   - 正文包含以下部分：**功能描述**、**动机**、**预期行为**
   - 如适用，添加 "enhancement" 标签

仓库：Octane0411/agent-deck
```

</details>

---

## Agent Parts

*这部分内容是给 agent 阅读的。*

### 项目简介

Agent Deck 是一个原生 macOS 应用，作为 AI 编程代理的桌面伴侣。它驻留在刘海/顶栏区域，监控本地代理会话、展示权限请求、回答问题，并提供"跳转回"对应终端上下文的能力。完全本地运行，无需服务端。

**支持的代理**: Codex, Claude Code

**支持的终端**: Terminal.app, Ghostty

### 环境要求

- macOS 14+
- Swift 6.2+
- Xcode（用于 app target）

### 构建与测试

```bash
# 构建项目
swift build

# 运行测试
swift test

# 运行应用
swift run AgentDeckApp

# 构建 Hook 可执行文件（Release）
swift build -c release --product AgentDeckHooks
```

也可以在 Xcode 中打开 `Package.swift`，直接构建和运行应用。

### 进一步了解

- [`CLAUDE.md`](CLAUDE.md) — 架构、代码规范、分支规则、提交规范、发版流程。
- [`docs/architecture.md`](docs/architecture.md) — 系统设计与工程决策。
- [`docs/product.md`](docs/product.md) — 产品范围与 MVP 边界。
- [`docs/hooks.md`](docs/hooks.md) — 支持的 Hook 事件、Payload 字段、指令协议。
