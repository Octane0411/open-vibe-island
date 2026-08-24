import Foundation

/// The semantic meaning of a rollout record, independent of which literal
/// Codex used to spell it.
///
/// Codex renames and reshuffles transcript record types between releases. A
/// single user's machine routinely holds transcripts from many versions at
/// once, so the decoder cannot assume one vocabulary. Mapping every known
/// spelling onto a small set of kinds keeps the version churn confined to one
/// table.
public enum CodexRecordKind: String, Equatable, Sendable, CaseIterable {
    /// Session header. Carries identity, cwd, originator, source, version.
    case sessionMeta
    /// A message from the user.
    case userMessage
    /// A message from the assistant.
    case assistantMessage
    /// Model reasoning, used only to detect activity.
    case reasoning
    /// A tool invocation started.
    case toolCallBegin
    /// A tool invocation finished.
    case toolCallEnd
    /// A turn started.
    case turnStarted
    /// A turn finished, was aborted, or the task completed.
    case turnEnded
    /// Token accounting.
    case tokenCount
    /// Activity by a spawned subagent.
    case subAgentActivity
    /// Per-turn context Codex records alongside the turn.
    case turnContext
    /// Codex's snapshot of workspace state.
    case worldState
    /// Thread-level bookkeeping: goal edits, settings, rollbacks, compaction.
    case threadBookkeeping
    /// Metadata about communication between agents.
    case interAgentMetadata
}

/// Maps rollout record type literals onto `CodexRecordKind`.
///
/// Two properties matter more than completeness:
///
/// 1. **Unknown literals are reported, never dropped.** The previous decoder
///    funnelled anything it did not recognize into a `default` branch, so
///    format drift stayed invisible until it surfaced as an unexplained bug
///    months later.
/// 2. **Retired literals stay listed.** Types Codex no longer writes still
///    appear in historical transcripts on user machines, and cold-start
///    recovery has to read them.
public enum CodexRecordTable {
    /// Top-level `type` values.
    public static let topLevel: [String: CodexRecordKind] = [
        "session_meta": .sessionMeta,
        "turn_context": .turnContext,
        "world_state": .worldState,
        "inter_agent_communication_metadata": .interAgentMetadata,
        "compacted": .threadBookkeeping,
    ]

    /// `payload.type` values inside `event_msg` and `response_item` records.
    public static let payload: [String: CodexRecordKind] = [
        // Messages
        "user_message": .userMessage,
        "agent_message": .assistantMessage,
        "compaction_summary": .assistantMessage,

        // Reasoning
        "reasoning": .reasoning,
        "agent_reasoning": .reasoning,
        "agent_reasoning_raw_content": .reasoning,
        "agent_reasoning_section_break": .reasoning,

        // Tool calls — current vocabulary
        "function_call": .toolCallBegin,
        "function_call_output": .toolCallEnd,
        "custom_tool_call": .toolCallBegin,
        "custom_tool_call_output": .toolCallEnd,
        "local_shell_call": .toolCallBegin,
        "mcp_tool_call_begin": .toolCallBegin,
        "mcp_tool_call_end": .toolCallEnd,
        "web_search_call": .toolCallBegin,
        "tool_search_call": .toolCallBegin,
        "tool_search_output": .toolCallEnd,
        "view_image_tool_call": .toolCallBegin,

        // Tool calls — retired spellings, still present in older transcripts
        "exec_command_begin": .toolCallBegin,
        "exec_command_end": .toolCallEnd,
        "patch_apply_begin": .toolCallBegin,
        "patch_apply_end": .toolCallEnd,
        "web_search_begin": .toolCallBegin,
        "web_search_end": .toolCallEnd,
        "image_generation_begin": .toolCallBegin,
        "image_generation_end": .toolCallEnd,
        "dynamic_tool_call_request": .toolCallBegin,
        "dynamic_tool_call_response": .toolCallEnd,

        // Turn boundaries
        "task_started": .turnStarted,
        "turn_started": .turnStarted,
        "task_complete": .turnEnded,
        "turn_complete": .turnEnded,
        "turn_aborted": .turnEnded,

        // Accounting and multi-agent
        "token_count": .tokenCount,
        "sub_agent_activity": .subAgentActivity,

        // Thread bookkeeping — recognized so it does not register as drift,
        // but carrying no facet this layer is allowed to write.
        "thread_goal_updated": .threadBookkeeping,
        "thread_settings_applied": .threadBookkeeping,
        "thread_rolled_back": .threadBookkeeping,
        "item_completed": .threadBookkeeping,
        "context_compacted": .threadBookkeeping,
        "compaction": .threadBookkeeping,
        "image_generation_call": .toolCallBegin,
    ]

    /// Record types that once carried approvals and questions.
    ///
    /// Codex moved both into the hook system; a scan of every transcript
    /// written in a recent month found zero occurrences of any of these. They
    /// are listed so the decoder recognizes them in historical data without
    /// treating them as actionable state — approvals now come from hooks only,
    /// per `CodexAuthorityMatrix`.
    public static let retiredApprovalTypes: Set<String> = [
        "request_permissions",
        "elicitation_request",
        "exec_approval_request",
        "apply_patch_approval_request",
        "request_user_input",
    ]

    public static func kind(forTopLevel type: String) -> CodexRecordKind? {
        topLevel[type]
    }

    public static func kind(forPayload type: String) -> CodexRecordKind? {
        payload[type]
    }

    public static func isRetiredApprovalType(_ type: String) -> Bool {
        retiredApprovalTypes.contains(type)
    }
}
