# Agent 支持范围审计（本机）

- 日期：2026-09-01
- 机器：Vincent Liu 的 Mac（arm64, macOS 26）
- 基线代码：`origin/main` @ bbbe08c
- 方法：扫描 `PATH` 上常见 agent CLI、`~` 下的 agent 配置目录、`/Applications` 与 `~/Applications`、npm 全局包、VS Code 扩展；对照代码权威清单 `Sources/OpenIslandCore/AgentHookIntent.swift` 的 `AgentIdentifier` 枚举与各 Hook 实现文件，以及 `docs/product.md` 的声明矩阵。

## 结论速览

- 代码实际支持 **10** 个 agent（含 `cursor`），`docs/product.md` 只声明了 9 个，**漏了 Cursor**（代码里有完整的 `CursorHooks.swift` / `CursorTranscriptReader.swift`）。
- 本机已安装但项目不支持的核心缺口：**Antigravity（agy）、DeepSeek（dsh）、TRAE / TRAE SOLO、MiniMax Code、ZCode、Hermes（ACP）**；另有 **Warp** 属于 Planned（仅 fallback 检测）。
- 项目支持但本机已无可用安装的：Qwen Code、Factory（零痕迹）；OpenCode、Gemini CLI、CodeBuddy（仅配置痕迹，CLI 不在 PATH）。

## 一、已安装且已支持（覆盖确认）

| Agent | 形态 | 本机证据 |
|---|---|---|
| Claude Code | CLI + VS Code 扩展 | `~/.local/bin/claude`；`anthropic.claude-code` 扩展 ×2 版本；`~/.claude` |
| Codex | CLI | `/opt/homebrew/bin/codex`；`~/.codex`（sessions/auth 齐全）；无独立 Codex.app |
| Cursor | 桌面 IDE（agent） | `Cursor.app`；`~/.cursor`。**代码支持但 docs/product.md 未列** |
| Qoder | 桌面 IDE（agent） | `Qoder.app` |
| Kimi CLI | CLI | `~/.kimi-code/bin/kimi`（hooks 配置 `~/.kimi` 尚未生成） |
| OpenCode | CLI | `~/.config/opencode` 含 `open-island-opencode-plugin-install.json`（插件装过）；**CLI 二进制当前不在 PATH** |
| Gemini CLI | CLI | `~/.gemini`（GEMINI.md、settings.json）；**CLI 二进制当前不在 PATH**；注意该目录同时被 Antigravity 占用（`antigravity-*` 子目录） |
| CodeBuddy | CLI | 仅 `~/.codebuddy/code-ratio` 残留；CLI 不在 PATH |

## 二、已安装但不在支持范围（缺口，重点）

| Agent | 形态 | 本机证据 | 说明 / 接入可行性初判 |
|---|---|---|---|
| **Antigravity** | CLI + App | `~/.local/bin/agy`（agent CLI，`--agent/--continue/--conversation`）；`Antigravity.app`、`Antigravity IDE.app`（com.google.antigravity）；配置寄生在 `~/.gemini/antigravity*` | Google 的 agent 入口。若 CLI 是 Gemini/Claude fork 则可复用现有 hook 路径，需确认 |
| **DeepSeek (dsh)** | CLI | `/opt/homebrew/bin/dsh`（`@deepseek-ai/dsh`，deepseek-harness CLI） | DeepSeek 官方 agent CLI，独立 hook 体系未知，需调研 |
| **TRAE / TRAE SOLO** | App（+IDE 启动器） | `TRAE SOLO.app`、`TRAE SOLO CN.app`（com.trae.solo.app）、`Trae.app`；`/usr/local/bin/trae` 只是 IDE 启动器（VS Code fork 的 `code` 等价物），不是终端 agent | SOLO 是 GUI 内置 agent，hook 接入可能性低，或需走 process/会话文件检测 |
| **MiniMax Code** | App | `MiniMax Code.app`（com.minimax.agent.cn） | 独立编码 agent 桌面端 |
| **ZCode** | App + CLI 数据目录 | `ZCode.app`（dev.zcode.app）；`~/.zcode`（cli、workspace、computer-use） | 智谱 ZCode（本审计运行所在的 CLI）。CLI + App 双形态，与本项目目标用户高度重合 |
| **Hermes** | CLI（ACP） | `~/.local/bin/hermes`、`hermes-acp`（`~/.hermes/hermes-agent` Python venv）；`Hermes.app`、`Hermes Studio.app` | 走 Agent Client Protocol 的 agent；身份待确认（第三方或自建）。ACP 是 Zed 系协议，接入需独立适配 |
| Warp | 终端内置 agent | `Warp.app` | 项目已列为 Planned（仅 fallback 检测，无精确 jump-back） |

## 三、项目支持但本机未安装/无痕迹

| Agent | 状态 |
|---|---|
| Qwen Code | 无任何痕迹（无 `~/.qwen`、无 `qwen` 二进制） |
| Factory | 无任何痕迹（无 `~/.factory`、无 `droid` 二进制） |

## 四、边界外的 AI 应用（不计入缺口）

聊天/浏览器/办公类，非编码 Agent，超出产品「terminal-native 编码 agent 监控」范围：ChatGPT.app / ChatGPT Classic、Claude.app（Claude Desktop，注意区别于 Claude Code）、Gemini.app、Doubao / DoubaoWork、QwenWorkCN、QoderWork、WorkBuddy、Monica、Cherry Studio、Coze、Fellou、Dia、Cola、Ollama（本地推理运行时）、PyCharm（JetBrains AI 未单独支持）。

## 建议下一步

1. **补文档**：`docs/product.md` 增加 Cursor 行（代码已支持，属文档漂移）。
2. **优先调研接入**：ZCode（双形态、用户重度使用）→ Antigravity `agy`（先确认是否 Claude/Gemini fork，若是则接入成本低）→ DeepSeek `dsh`。
3. TRAE SOLO / MiniMax Code 属 GUI agent，评估 process/会话文件检测路径的成本后再决定。
