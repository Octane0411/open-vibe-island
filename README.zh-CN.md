<p align="center">
  <img src="Assets/Brand/app-icon-cat.png" alt="Open Island" width="128" height="128">
</p>

<h1 align="center">Open Island</h1>

<p align="center">
  面向 AI coding agents 的开源 macOS companion app。
  <br>
  <strong>中文</strong> | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/Octane0411/open-vibe-island/releases">下载</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#贡献">参与贡献</a>
</p>

---

## Human Parts

这部分内容是给人类阅读的。

### 这是什么

这是一个开源的 [Vibe Island](https://vibeisland.app/) 替代品，面向 macOS 上的重度 code agent 用户。目前支持 **Claude Code** 和 **Codex**，终端集成覆盖 **Terminal.app**、**Ghostty**、**cmux**、**Kaku**、**WezTerm** 和 **iTerm2**，并对 Warp 提供降级检测支持。

<p align="center">
  <img src="docs/images/screenshot-overview.png" alt="Open Island 截图" width="720">
</p>

### 动机

我不想在自己的电脑上运行一个闭源、付费的软件来监视我所有的生产过程，所以我 build 了这个开源版本。

> you don't need to pay for a product you can vibe since you are a vibe coder

### 使用方式

- 从 [GitHub Releases](https://github.com/Octane0411/open-vibe-island/releases) 下载早期版本并安装，或从源码构建。
- Fork 这个仓库，然后 vibe 你自己的版本。
- 如果你遇到 bug 或使用问题，请先发 issue，我们会优先处理。
- 如果你希望支持其他 terminal app 或 code agent，请先发 issue，我们会尽可能扩展。
- 如果你有产品想法或功能需求，也请先发 issue；欢迎附 demo 发 PR。

### 注意事项

本应用可能会为你的 Claude Code 或 Codex 安装 hooks，因此你可能会在这些会话中看到 hook 相关输出。

### 功能状态

#### 支持的 Code Agents

| Agent | 状态 | 说明 |
|---|---|---|
| **Claude Code** | 已支持 | Hook 集成、JSONL 会话发现、status line bridge、用量追踪 |
| **Codex** | 已支持 | 完整 hook 集成（SessionStart、UserPromptSubmit、Stop）、用量追踪 |
| **opencode** | 规划中 | — |
| **gemini cli** | 规划中 | — |

#### 支持的终端

| 终端 | 状态 | 说明 |
|---|---|---|
| **Terminal.app** | 完整支持 | Jump-back，TTY 定位 |
| **Ghostty** | 完整支持 | Jump-back，ID 匹配 |
| **cmux** | 完整支持 | Jump-back，Unix socket API |
| **Kaku** | 完整支持 | Jump-back，CLI pane 定位 |
| **WezTerm** | 完整支持 | Jump-back，CLI pane 定位 |
| **iTerm2** | 完整支持 | Jump-back，session ID / TTY 匹配 |
| **Warp** | 规划中 | 仅降级检测 |

#### 其他功能

| 功能 | 状态 | 说明 |
|---|---|---|
| 刘海 / 顶部栏覆盖层 | 已支持 | 刘海 Mac 在刘海区域，其他 Mac 顶部居中栏 |
| 控制中心 | 已支持 | Hook 状态、用量仪表盘 |
| 设置 | 已支持 | 通用、显示、声音、快捷键、实验室、关于 |
| 完成通知 | 已支持 | 已支持claude code, codex |
| 权限通知 | 已支持 | 已支持claude code, codex |
| askUserQuestion通知 | 已支持 | 已支持claude code |
| 通知音效 | 已支持 | 可配置系统音效、静音切换 |
| 国际化 | 已支持 | English、简体中文 |
| 自动更新 | 已支持 | 基于 Sparkle 的自动更新，支持 appcast |

## 社区

目前项目还在早期阶段，在体验中可能会出现任何问题，加入微信群/discord以获得更快的反馈和更高的解决优先级

同时欢迎任意 issue 和 pull request，我们也在寻找其他maintainer，open island只是个开始，微信群：

<img src="docs/images/wechat-group.jpg" alt="Open Island 微信群二维码" width="360">

### 通过 Code Agent 提交 Bug

遇到问题？把下面的 prompt 复制到你的 code agent（Claude Code、Codex 等）中，它会自动收集环境信息并帮你创建一个规范的 issue。

<details>
<summary>点击展开 prompt</summary>

```
我在使用 Open Island (https://github.com/Octane0411/open-vibe-island) 时遇到了问题。

请帮我提交一个 GitHub issue，按以下步骤操作：

1. 收集我的环境信息：
   - 运行 `sw_vers` 获取 macOS 版本
   - 运行 `swift --version` 获取 Swift 版本
   - 检查 Open Island 是否在运行：`ps aux | grep -i "open.island\|OpenIslandApp" | grep -v grep`
   - 获取 app 版本：`defaults read ~/Applications/Open\ Island\ Dev.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown"`
   - 检查我当前使用的终端

2. 询问我：
   - 期望的行为是什么
   - 实际发生了什么
   - 复现步骤

3. 使用 `gh issue create` 在 GitHub 上创建 issue，格式如下：
   - 标题：简洁的问题概述
   - 正文包含以下部分：**环境信息**、**问题描述**、**复现步骤**、**期望行为 vs 实际行为**
   - 如果是 bug 请添加 "bug" 标签

仓库：Octane0411/open-vibe-island
```

</details>

### Star History

<a href="https://star-history.com/#Octane0411/open-vibe-island&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Octane0411/open-vibe-island&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Octane0411/open-vibe-island&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Octane0411/open-vibe-island&type=Date" />
 </picture>
</a>

### Contributors

<a href="https://github.com/Octane0411/open-vibe-island/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Octane0411/open-vibe-island" />
</a>

## 路线图

4.6 发布测试版

---

## Agent Parts

这部分内容是给 agents 阅读的。

这是一个面向终端原生 AI coding 工作流的开源 macOS companion app。

`Open Island` 会在刘海区域或顶部栏放置一个轻量控制界面，让你可以在不中断当前 flow 的前提下观察 live coding agents、跟踪会话进度，并快速跳回正确的 terminal 上下文。

## 为什么会有这个产品

AI coding 正在成为日常开发流程的一部分，但围绕它的控制层仍然经常意味着把你的机器交给一个闭源、收费的 app。

`Open Island` 选择了相反的路线：

- 开源
- Local first，无服务器依赖
- 原生 macOS（SwiftUI + AppKit）
- 适配 terminal 工作流，而不是替代它

## 适合谁

已经长期工作在 terminal 里的开发者，希望在 macOS 上和 coding agents 协作时拥有更好的上下文感，而不是在工具之间来回丢失状态。

## 功能特性

### Agent 集成

- **Codex** — 完整的 hook 集成。默认接收 `SessionStart`、`UserPromptSubmit` 和 `Stop` 事件。从本地 rollout 文件读取 5 小时和 7 天 account usage windows。支持从控制中心或 CLI 安装/卸载受管 hooks。
- **Claude Code** — 基于 hook 的集成，通过 `~/.claude/settings.json` 配置。从 `~/.claude/projects/` JSONL transcript 自动发现会话。跨应用启动持久化和恢复会话。受管 status line bridge，opt-in 安装。读取缓存的 5 小时和 7 天 usage windows。

### 终端支持

- **Terminal.app**、**Ghostty**、**cmux**、**Kaku**、**WezTerm** 和 **iTerm2** — 完整的 jump-back 支持，带会话附着匹配（cmux 通过 Unix socket API，Kaku/WezTerm 通过 CLI pane 定位，iTerm2 通过 AppleScript session/TTY 探针）
- **Warp** — 降级检测和基本进程发现

### UI 与显示

- **刘海覆盖层** — 在有刘海的 Mac 上，island 位于刘海区域；在外接显示器或无刘海 Mac 上，降级为紧凑的顶部居中栏
- **控制中心** — Codex/Claude hook 状态、用量仪表盘、调试场景
- **设置** — 通用、显示、声音、快捷键、实验室（高级）、关于
- **通知模式** — 自适应高度的通知面板，用于权限请求和会话事件
- **通知音效** — 可配置的系统音效（默认：Bottle），支持静音切换
- **国际化** — 英文和简体中文

### 会话管理

- Live session 可见性，支持可展开的详情行
- Session state reducer（`SessionState.apply`）作为唯一真相源
- 从本地 transcript 文件和缓存自动发现会话
- 通过 `ps`/`lsof` 进行进程发现，匹配活跃的 agent

### 架构

一个 Swift package 中的四个 target：

| Target | 角色 |
|---|---|
| **OpenIslandApp** | SwiftUI + AppKit shell — 菜单栏、覆盖面板、控制中心、设置 |
| **OpenIslandCore** | 共享库 — 模型、bridge 传输（Unix socket IPC）、hooks、会话持久化 |
| **OpenIslandHooks** | 轻量 CLI，由 agent hooks 调用，通过 Unix socket 转发 payload |
| **OpenIslandSetup** | 安装器 CLI，管理 `~/.codex/config.toml` 和 hook entries |

## 快速开始

本地构建并运行：

```bash
open Package.swift
```

构建本地 `.app` 包：

```bash
zsh scripts/package-app.sh
```

该脚本会创建 `output/package/Open Island.app` 和 `output/package/Open Island.zip`。传入 `OPEN_ISLAND_SIGN_IDENTITY` 可以签名。详见 [docs/packaging.md](docs/packaging.md)。

### 连接 Codex

在 Xcode 中打开 package 并运行 macOS app target。启动时，app 会恢复本地缓存，扫描最近的 `~/.codex/sessions/**/rollout-*.jsonl` 文件来恢复已有 Codex sessions，然后启动 live bridge 接收新 hook events。

控制中心展示来自 `~/.codex` 的实时 Codex hook 安装状态，并可直接安装或卸载受管 hook entries。安装过程会把 helper 复制到 `~/Library/Application Support/OpenIsland/bin/OpenIslandHooks`，repo 重命名不会破坏已有 hooks。

```bash
swift build -c release --product OpenIslandHooks
swift run OpenIslandSetup install
swift run OpenIslandSetup status
swift run OpenIslandSetup uninstall
```

### 连接 Claude Code

Claude usage 设置可在 app 控制中心启用，保持 opt-in。bridge 会把受管 `statusLine.command` 写入 `~/.open-island/bin/open-island-statusline`，把 `rate_limits` 缓存到 `/tmp/open-island-rl.json`，不会自动覆盖已有的自定义 status line。

## 仓库导航

- 从 [docs/index.md](docs/index.md) 开始查看文档地图。
- 阅读 [docs/quality.md](docs/quality.md) 了解质量基线和验证方式。

## 系统要求

- macOS 14+
- Swift 6.2
- Xcode（用于 app target）

## 产品方向

目标很简单：让 AI coding 在 macOS 上更像原生体验。

这意味着：

- 更少的上下文切换
- 更少的标签页来回寻找
- 更少的会话感知摩擦
- 更快地回到当前活跃 agent session

## 贡献

目前项目还在早期阶段，欢迎 issue 和 pull request。
