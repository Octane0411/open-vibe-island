# Privacy Policy / 隐私政策

**Last updated: 2026-09-11**

## English

Open Island is a companion app for AI coding agents. It does not include analytics or a third-party crash-reporting service. It does use third-party libraries, including Sparkle for updates and MarkdownUI for rendering.

### Data on your devices

The Mac app reads local coding-tool transcripts and hook events to show session activity, requests, replies, working directories and usage information. It stores session registries and preferences locally. The optional Claude status-line integration also caches quota information locally. The app can control supported terminals and IDEs when you use its navigation and reply features.

The OpenCode plugin does not log event payloads. Logs left by older versions are not automatically deleted. Agent Markdown images are not downloaded automatically; opening a link is a user action.

### Network communication

Release builds check GitHub for updates through Sparkle and can download updates you accept. These requests expose ordinary network metadata, including your IP address, to the update host. They are not session-content uploads.

Phone/Watch notifications are optional and off by default. When enabled, Bonjour announces the Mac's service on the local network. After explicit pairing, the Mac and iPhone exchange encrypted session events, permission requests, answers and decisions. The iPhone forwards supported notifications and actions to Apple Watch through Apple's WatchConnectivity framework. Notification previews may contain session details; use your device's notification privacy settings as needed.

Remote SSH integration is a separate, optional feature. It forwards hook traffic from an environment you configure. Phone pairing does not require SSH. See [security boundaries and pairing](docs/security.md) for authentication, revocation and migration details.

### Local storage

Mac session registries can include conversation summaries and paths. Preferences stay in UserDefaults. iPhone pairing keys and tokens use the device-only Keychain, while notification preferences and the paired Mac name remain in UserDefaults. The iPhone also keeps recent events in memory. Mac pairing credentials are memory-only and expire when the service stops. Removing a pairing invalidates access; it does not erase previously delivered notifications or local coding-tool transcripts.

### Contact

Questions can be raised through the [project issue tracker](https://github.com/Octane0411/open-vibe-island/issues). Avoid including private session contents in a public issue.

## 中文

Open Island 是 AI 编程助手的配套应用。本应用不包含分析统计或第三方崩溃报告服务，但使用 Sparkle 更新组件及 MarkdownUI 等第三方库。

### 设备上的数据

Mac 应用读取本地编程工具的会话记录和 hook 事件，显示会话活动、请求、回复、工作目录及用量，并在本地保存会话注册信息和偏好设置。可选的 Claude 状态栏集成还会缓存配额信息。使用跳转和回复功能时，应用可以控制受支持的终端及 IDE。

OpenCode 插件不再记录事件内容。旧版本遗留的日志不会被自动删除。应用不会自动下载助手回复中的 Markdown 图片；链接由用户主动打开。

### 网络通信

正式版本通过 Sparkle 向 GitHub 检查更新，并可下载用户接受的更新。更新服务器会收到 IP 地址等常规网络信息，但不会收到会话内容上传。

手机和手表通知默认关闭。启用后，Bonjour 会在局域网公告 Mac 服务。用户主动配对后，Mac 与 iPhone 通过加密连接交换会话事件、权限请求、回答及操作决定。iPhone 使用 Apple WatchConnectivity 框架向手表转发受支持的通知和操作。通知预览可能包含会话内容，可通过系统通知隐私设置控制显示。

远程 SSH 集成是独立的可选功能，用于从用户配置的远程环境转发 hook 流量。手机配对不需要 SSH。认证、撤销及升级说明见[安全边界与配对](docs/security.md)。

### 本地存储

Mac 会话注册信息可能包含对话摘要和路径。偏好设置保存在 UserDefaults 中。iPhone 配对密钥及令牌保存在仅限本设备的钥匙串中，通知偏好及 Mac 名称仍保存在 UserDefaults 中，最近事件保存在内存中。Mac 配对凭据仅保存在内存中，服务停止后失效。撤销配对不会删除已发送的通知或编程工具自身的会话记录。

### 联系方式

如有疑问，请通过[项目问题追踪器](https://github.com/Octane0411/open-vibe-island/issues)联系。请勿在公开问题中包含私人会话内容。
