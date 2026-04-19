import CoreGraphics
import Foundation
import OpenIslandCore

struct IslandDebugSnapshot {
    let title: String
    let summary: String
    let previewHeight: CGFloat
    let notchStatus: NotchStatus
    let notchOpenReason: NotchOpenReason?
    let islandSurface: IslandSurface
    let sessions: [AgentSession]
    let selectedSessionID: String?
}

enum IslandDebugScenario: String, CaseIterable, Identifiable {
    case closed
    case sessionList
    case approvalCard
    case questionCard
    case completionCard
    case longCompletionCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closed:
            "Closed Notch"
        case .sessionList:
            "Session List"
        case .approvalCard:
            "Approval Card"
        case .questionCard:
            "Question Card"
        case .completionCard:
            "Completion Card"
        case .longCompletionCard:
            "Long Completion Card"
        }
    }

    var summary: String {
        switch self {
        case .closed:
            "Collapsed idle/running notch with live count and attention affordance."
        case .sessionList:
            "Manual expanded list with running, active, and inactive session rows."
        case .approvalCard:
            "Auto-expanded permission surface with approve and deny actions."
        case .questionCard:
            "Auto-expanded question surface with selectable answer buttons."
        case .completionCard:
            "Auto-expanded finished-task reminder surface after a turn completes."
        case .longCompletionCard:
            "Long finished-task reply stays inside the card and scrolls internally."
        }
    }

    func snapshot(at now: Date = .now) -> IslandDebugSnapshot {
        switch self {
        case .closed:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .sessionList:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .approvalCard:
            let session = DebugSessionFactory.approvalSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 330,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .questionCard:
            let session = DebugSessionFactory.questionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 270,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .completionCard:
            let session = DebugSessionFactory.completionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .longCompletionCard:
            let session = DebugSessionFactory.longCompletionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 290,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )
        }
    }
}

private enum DebugSessionFactory {
    static func listSessions(now: Date) -> [AgentSession] {
        [
            runningSession(now: now),
            recentCompletedSession(now: now),
            inactiveSession(
                id: "session-claude-research",
                workspace: "claude-research",
                initialPrompt: "我更关注获取的部分 我想在其他 app 里实时展示我的 usage。",
                latestPrompt: "为什么要查 Cursor 官方呢？这个事跟 Cursor 有什么关系？",
                assistant: "不建议按“最古老”来选。最古老不等于最轻量且最适合这个任务。",
                age: 27 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-personal",
                workspace: "Personal",
                initialPrompt: "[Image #1]我给你截了 3 张图，这个是我现在 Cursor 里面可用的模型。",
                latestPrompt: "[Image #1]我给你截了 3 张图，这个是我现在 Cursor 里面可用的模型。",
                assistant: "这张图里的模型，严格说不是这个 `voice-input` App 应该选的模…",
                age: 32 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-open-agent-sdk",
                workspace: "open-agent-sdk",
                initialPrompt: "OK，那现在你是不是需要提一个 PR？",
                latestPrompt: "那你直接提个 PR 吧",
                assistant: "PR 已经提好了：",
                age: 60 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-voice-input",
                workspace: "voice-input",
                initialPrompt: "看看 voice-input 这个仓库，重点关注模型选型。",
                latestPrompt: "严格来说它应该选哪个模型？",
                assistant: "如果目标是轻量实时，不建议直接按 Cursor 现成套餐来映射。",
                age: 78 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-agents",
                workspace: "agents",
                initialPrompt: "把你的分支和 worktree 都给我。",
                latestPrompt: "所以你是要先重启吗？",
                assistant: "已经重启了。现在跑的是新的 dev 进程。",
                age: 92 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-claude",
                workspace: "claude-code",
                initialPrompt: "我们先把整个 notch 的背景换成纯黑。",
                latestPrompt: "下面那块空白要去掉。",
                assistant: "展开态高度已经改成按内容自适应。",
                age: 118 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-hooks",
                workspace: "hooks",
                initialPrompt: "假如我想实时监控 Claude Code 的 usage 应该怎么做？",
                latestPrompt: "如果是在别的 app 里展示呢？",
                assistant: "代码里已经有几条更直接的路可以走。",
                age: 130 * 60,
                now: now
            ),
        ]
    }

    static func notificationSessions(lead: AgentSession, now: Date) -> [AgentSession] {
        var sessions = listSessions(now: now)
        if sessions.isEmpty {
            return [lead]
        }
        sessions[0] = lead
        return sessions
    }

    static func runningSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-running",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Reading IslandPanelView.swift and AppModel.swift",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-running"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "把 DEV 完全重构成一个 debug 页面，我需要稳定验收这些 card 的 UI。",
                lastUserPrompt: "之前也有错误的改动吧 你应该重新改",
                lastAssistantMessage: "读取现有 notch 状态与事件路由，准备把提醒态从 session list 里拆出来。",
                currentTool: "exec_command",
                currentCommandPreview: "sed -n '1,260p' Sources/OpenIslandApp/Views/ControlCenterView.swift"
            )
        )
    }

    static func recentCompletedSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-recent",
            title: "Codex · open-agent-sdk",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The session list now matches the original island more closely.",
            updatedAt: now.addingTimeInterval(-3 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-agent-sdk",
                paneTitle: "codex ~/Personal/open-agent-sdk",
                workingDirectory: "/Users/wangruobing/Personal/open-agent-sdk",
                terminalSessionID: "ghostty-recent"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "读一下这篇论文 https://arxiv.org/html/2603.28052",
                lastUserPrompt: "读一下这篇论文 https://arxiv.org/html/2603.28052v1 感觉和我们在做的 agent 很像。",
                lastAssistantMessage: "整理完了，已经提炼出和 autoreserach 相关的几段关键差异。"
            )
        )
    }

    static func inactiveSession(
        id: String,
        workspace: String,
        initialPrompt: String,
        latestPrompt: String,
        assistant: String,
        age: TimeInterval,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspace)",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: assistant,
            updatedAt: now.addingTimeInterval(-age),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "codex ~/Personal/\(workspace)",
                workingDirectory: "/Users/wangruobing/Personal/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: initialPrompt,
                lastUserPrompt: latestPrompt,
                lastAssistantMessage: assistant
            )
        )
    }

    static func approvalSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-approval",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Allow exec_command to rewrite ControlCenterView.swift?",
            updatedAt: now.addingTimeInterval(-20),
            permissionRequest: PermissionRequest(
                title: "Approve file rewrite",
                summary: "Allow exec_command to rewrite ControlCenterView.swift?",
                affectedPath: "Sources/OpenIslandApp/Views/ControlCenterView.swift",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny"
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-approval"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "接下来我打算继续补齐一些能力。",
                lastUserPrompt: "askUserquestion 和权限审批，我想把他们也做到我们的 island 里。",
                lastAssistantMessage: "已经准备好重写 DEV 页面，需要批准文件改动。",
                currentTool: "exec_command",
                currentCommandPreview: "head -5000 /Users/wangruobing/Personal/claude-research/extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt"
            )
        )
    }

    static func questionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-question",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "这个提醒态需要自动收起吗？",
            updatedAt: now.addingTimeInterval(-18),
            questionPrompt: QuestionPrompt(
                title: "Which authentication method should we use?",
                questions: [
                    QuestionPromptItem(
                        question: "Which authentication method should we use?",
                        header: "Auth",
                        options: [
                            QuestionOption(label: "JWT tokens", description: "Stateless, scalable"),
                            QuestionOption(label: "Session cookies", description: "Traditional approach"),
                            QuestionOption(label: "OAuth 2.0", description: "Third-party auth"),
                            QuestionOption(label: "Other", description: "", allowsFreeform: true),
                        ]
                    )
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-question"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "原产品看起来像是单 notch surface + 多 content surface。",
                lastUserPrompt: "我们应该怎么做？",
                lastAssistantMessage: "建议先把 approvalCard、questionCard、completionCard 拆成独立 surface。"
            )
        )
    }

    static func completionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "DEV 页面已经切到 mock-driven card 调试模式。",
            updatedAt: now.addingTimeInterval(-15),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-completion"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "这次我可能确实需要一些 mock 手段，让我能验收这些 Card 的 UI。",
                lastUserPrompt: "可以把 DEV 完全重构成一个 debug 页面。",
                lastAssistantMessage: "Plan 文件已写好。你的 hooks 触发情况如何？"
            )
        )
    }

    static func longCompletionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion-long",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "README 提交已经完成，长回复现在应该在卡片内部滚动。",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-completion-long"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "帮我把这个 README 也提交了，然后把结果贴给我。",
                lastUserPrompt: "顺便确认一下当前工作树和验证情况。",
                lastAssistantMessage: """
[README.md](/Users/wangruobing/Personal/open-island/README.md) 的现有改动已经单独提交了，commit 是 `f196316`，message 是 `docs: update readme tagline`。

这轮没有跑测试，因为只是文案改动。当前工作树是干净的，`main` 相对 `origin/main` 现在是 `ahead 6`。

如果你要我继续做下一轮，我建议把工作切到独立 worktree 里，这样不会和共享 `main` 上的并行改动互相打架。

下一步我会先检查当前仓库状态，然后从 `origin/main` 新建一个 worktree 和分支，在新工作区里继续处理这个样式问题并做完验证。
"""
            )
        )
    }
}
