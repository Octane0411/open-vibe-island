# Privacy and local data / 隐私与本地数据

Updated October 31, 2026. This describes the hardened development fork, not previously distributed upstream builds.

## English

Open Island reads local agent events, session metadata, and supported agents' transcript/configuration files to display activity, approvals, questions, and completion text. This can include prompts, tool inputs, file paths, answers, terminal identifiers, and process information. macOS Automation or Accessibility permission may be needed for supported terminal navigation; denying permission can limit those actions.

The app keeps preferences in its bundle's UserDefaults domain and session registries under `~/Library/Application Support/open-island/`. The registries can retain prompt/response summaries and terminal/workspace metadata between launches. Runtime discovery limits do not guarantee deletion of all historical data. The Unix socket and managed helper use `~/Library/Application Support/OpenIsland/`; older helpers may use the compatibility socket in `/tmp`. Claude usage integration can also use `/tmp/open-island-rl.json` and its legacy equivalent.

Installing integrations writes agent configuration and a managed helper or plugin. The Codex and OpenCode installers retain original bytes in private `.open-island-recovery-<UUID>` directories beside configuration files. These backups can contain credentials or other secrets from the original configuration. They have no automatic deletion schedule. Other integration installers may retain their own backups.

The OpenCode plugin no longer logs event payloads. Old `/tmp/open-island-opencode-debug.log` files are not automatically removed. System and development logs can still contain operational errors and identifiers. This project does not configure an analytics or remote crash-reporting service; it does include third-party libraries, including Sparkle and MarkdownUI.

Agent-authored Markdown uses local image placeholders, including inline images: image URLs and local image paths are not fetched. Clicking a link can open the destination in your browser. OpenCode replies use that agent's local service interface. Sparkle automatic and manual update checks are disabled in this fork; future update traffic requires a separately configured and verified release channel. Phone/Watch networking and terminal reply injection are disabled by runtime guards in this fork. SSH setup is disabled pending safe configuration merging. Separately running agents and user-configured SSH tunnels have their own data flows and privacy policies.

To remove retained app data, quit the app, uninstall unwanted managed integrations, then review and remove its session registry files and preferences for the installed bundle identity. Review recovery directories and old diagnostic/usage files separately. Removing app caches does not delete transcripts owned by your agents, operating-system logs, or backups made by your backup software. Upstream and fork storage names currently overlap; do not delete shared data while another build uses it. There is no single in-app “erase all data” control.

Report concerns through the [fork issue tracker](https://github.com/RobinEdquist/open-vibe-island/issues). Do not include private prompts, credentials, or configuration contents in a public report.

## 中文

本说明适用于加固后的开发分支，不代表此前发布的上游版本。

应用读取本地代理事件、会话信息以及所支持代理的记录和配置，以显示活动、审批、问题和完成内容。这些信息可能包含提示词、工具输入、文件路径、答案、终端标识和进程信息。终端跳转可能需要 macOS 自动化或辅助功能权限；拒绝权限会限制相关操作。

偏好设置保存在应用的 UserDefaults 域中。会话缓存位于 `~/Library/Application Support/open-island/`，可能在重启后保留提示词、回复摘要和终端信息。套接字和辅助程序使用 `~/Library/Application Support/OpenIsland/`；兼容套接字和部分用量缓存位于 `/tmp`。发现流程的时间限制不等于历史数据会自动删除。

集成安装会修改代理配置。Codex 和 OpenCode 安装器会在配置旁的私有 `.open-island-recovery-<UUID>` 目录保留原始文件。这些备份可能包含密钥，且不会自动过期。其他集成可能保留各自的备份。

OpenCode 插件已停止记录事件内容；旧的临时日志不会自动删除。系统和开发日志仍可能包含运行错误和标识。本项目未配置分析或远程崩溃报告服务，但包含 Sparkle、MarkdownUI 等第三方库。

代理 Markdown 中的独立图片和行内图片都显示为本地图标，不读取其网址或文件路径。点击链接仍可能打开浏览器。OpenCode 回复通过代理的本地服务处理。本分支已禁用自动和手动更新检查，未来启用更新渠道前必须完成独立配置和验证。手机和 Watch 联网、终端回复以及 SSH 安装目前被代码禁用。代理自身和用户配置的 SSH 隧道另有数据流及隐私政策。

删除数据前请退出应用并卸载不再需要的集成，然后分别检查会话缓存、该安装身份的偏好设置、恢复备份及旧日志。应用缓存的删除不会删除代理记录、系统日志或其他备份。分支与上游仍使用部分相同存储路径，请勿在其他版本使用时删除共享数据。目前没有一个可以删除所有数据的应用内按钮。
