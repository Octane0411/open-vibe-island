<p align="center">
  <img src="Assets/Brand/app-icon-cat.png" alt="Open Island" width="128" height="128">
</p>

<h1 align="center">Open Island (Enhanced)</h1>

<p align="center">
  <strong>基于 <a href="https://github.com/Octane0411/open-vibe-island">open-vibe-island</a> 的增强版，新增即时终端识别和手动刷新机制</strong>
  <br>
  开源、本地优先、原生 macOS AI 编程助手伴侣应用
  <br><br>
  <a href="#安装">安装</a> ·
  <a href="#新增功能">新增功能</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#english">English</a>
</p>

<p align="center">
  <a href="https://github.com/8676311081/open-island/releases/latest"><img src="https://img.shields.io/github/v/release/8676311081/open-island?style=flat-square&label=release&color=blue" alt="Latest Release"></a>
  <a href="https://github.com/8676311081/open-island/stargazers"><img src="https://img.shields.io/github/stars/8676311081/open-island?style=flat-square&color=yellow" alt="Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-green?style=flat-square" alt="License: GPL v3"></a>
</p>

<p align="center">
  <img src="docs/images/demo.gif" alt="Open Island in action" width="720">
</p>

---

## 这是什么？

这是 [Open Island (open-vibe-island)](https://github.com/Octane0411/open-vibe-island) 的增强版本。原版是一个优秀的开源 macOS AI 编程助手伴侣应用，常驻 Mac 的 notch/顶栏区域，实时监控 AI 编程 agent 会话。

本仓库在原版基础上增加了**即时终端识别**和**手动刷新**机制，解决了新开终端无法被及时识别的问题。

## 新增功能

### 即时终端识别
原版依赖 2 秒一次的轮询来发现新终端。增强版在收到 Hook 事件时**立即触发**进程扫描和终端匹配，新开的终端运行 AI agent 后**瞬间**出现在面板中。

```
之前：新终端 → Hook 事件 → 等待 2 秒轮询 → 识别
现在：新终端 → Hook 事件 → 立即扫描 → 识别
```

### 手动刷新按钮
面板头部新增 ↻ 刷新按钮，一键触发会话重新扫描。不再需要等待自动轮询。

### 改动文件（仅 3 个）

| 文件 | 改动 |
|---|---|
| `ProcessMonitoringCoordinator.swift` | 新增 `triggerImmediateReconciliation()` |
| `AppModel.swift` | Hook sessionStarted 时立即 reconcile；暴露 `refreshSessions()` |
| `IslandPanelView.swift` | header 添加刷新按钮 |

## 安装

### 方式一：下载 DMG

从 [Releases](https://github.com/8676311081/open-island/releases/latest) 下载最新的 **Open Island.dmg**，打开后拖入 Applications。

> 需要 **macOS 14+**，支持 Apple Silicon 和 Intel Mac。
>
> 首次启动：右键 → 打开，或在系统设置 → 隐私与安全中允许运行。

### 方式二：从源码构建

```bash
git clone https://github.com/8676311081/open-island.git
cd open-island
swift build
swift run OpenIslandApp
```

## 快速开始

1. 启动 Open Island，它会出现在你的 notch/顶栏区域
2. 打开终端，运行 `claude`、`codex` 等 AI agent
3. 面板会立即显示新会话 — 点击可跳转到对应终端
4. 如果需要手动刷新，点击面板头部的 ↻ 按钮

## 支持的 Agent 和终端

**9 种 Agent**：Claude Code, Codex, Cursor, Gemini CLI, OpenCode, Qoder, Qwen Code, Factory, CodeBuddy

**15+ 种终端/IDE**：Terminal.app, Ghostty, iTerm2, WezTerm, Zellij, tmux, cmux, Kaku, VS Code, Cursor, Windsurf, Trae, JetBrains 全家桶

## 工作原理

```
Agent (Claude Code / Codex / ...)
  ↓ hook 事件
OpenIslandHooks CLI (stdin → Unix socket)
  ↓ JSON 数据包
BridgeServer (应用内)
  ↓ 状态更新 + 立即 reconciliation（增强版新增）
Notch 悬浮面板 ← 你在这里看到
  ↓ 点击
跳转到 → 对应的终端 / IDE
```

---

<a name="english"></a>

## English

This is an enhanced version of [Open Island (open-vibe-island)](https://github.com/Octane0411/open-vibe-island), adding **instant terminal detection** and a **manual refresh** mechanism.

### What's New

- **Instant terminal detection** — When a new agent session hook event arrives, triggers immediate process scan + terminal reconciliation instead of waiting for the 2-second polling cycle
- **Manual refresh button (↻)** — One-click session rescan in the island panel header
- **`refreshSessions()` API** — Programmatic session refresh for UI-driven rescans

### Installation

Download the latest DMG from [Releases](https://github.com/8676311081/open-island/releases/latest), or build from source:

```bash
git clone https://github.com/8676311081/open-island.git
cd open-island
swift build && swift run OpenIslandApp
```

Requires macOS 14+. Supports Apple Silicon and Intel.

---

## 致谢

- 原版项目：[Octane0411/open-vibe-island](https://github.com/Octane0411/open-vibe-island)
- 灵感来源：[Vibe Island](https://vibeisland.app/)
- 许可证：GPL v3
