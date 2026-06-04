// Open Island extension for Pi
// Bridges Pi runtime events to the Open Island desktop app via Unix socket.
// Install: copy to ~/.pi/agent/extensions/open-island.ts, then run /reload in Pi.
import { connect } from "node:net";
import { appendFileSync } from "node:fs";
import { homedir } from "node:os";
import { execFileSync } from "node:child_process";

const DEBUG_LOG = "/tmp/open-island-pi-debug.log";
const APPROVAL_TOOL_NAMES = new Set(["bash", "edit", "write"]);

function debugLog(message: string) {
  if (process.env.OPEN_ISLAND_PI_DEBUG !== "1") return;
  try { appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] ${message}\n`); } catch {}
}

const SOCKET_PATH =
  process.env.OPEN_ISLAND_SOCKET_PATH ||
  `${process.env.HOME || homedir()}/Library/Application Support/OpenIsland/bridge.sock`;

function encodeEnvelope(command: unknown) {
  return JSON.stringify({ type: "command", command }) + "\n";
}

function sendToSocket(command: unknown, timeoutMs = 3000): Promise<unknown | null> {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET_PATH }, () => {
        sock.write(encodeEnvelope(command));
      });
      let buffer = "";
      let resolved = false;
      const finish = (value: unknown | null) => {
        if (resolved) return;
        resolved = true;
        try { sock.destroy(); } catch {}
        resolve(value);
      };
      sock.on("data", (chunk) => {
        buffer += chunk.toString();
        const lines = buffer.split("\n").filter(Boolean);
        // BridgeServer sends hello first, then the command response.
        if (lines.length < 2) return;
        try { finish(JSON.parse(lines[1])); } catch { finish(null); }
      });
      sock.on("end", () => finish(null));
      sock.on("error", () => finish(null));
      sock.setTimeout(timeoutMs, () => finish(null));
    } catch {
      resolve(null);
    }
  });
}

function fireAndForget(command: unknown) {
  void sendToSocket(command).catch((error) => debugLog(`send failed: ${String(error)}`));
}

let detectedTty: string | undefined;
try {
  const tty = execFileSync("/usr/bin/tty", { timeout: 1000 }).toString().trim();
  if (tty && tty !== "not a tty") detectedTty = tty;
} catch {}

function terminalFields() {
  const env = process.env;
  const result: Record<string, string> = {};
  if (env.ITERM_SESSION_ID) {
    result.terminal_app = "iTerm";
    result.terminal_session_id = env.ITERM_SESSION_ID;
  } else if (env.CMUX_WORKSPACE_ID || env.CMUX_SOCKET_PATH) {
    result.terminal_app = "cmux";
    if (env.CMUX_SURFACE_ID) result.terminal_session_id = env.CMUX_SURFACE_ID;
  } else if (env.GHOSTTY_RESOURCES_DIR || (env.TERM_PROGRAM || "").toLowerCase().includes("ghostty")) {
    result.terminal_app = "Ghostty";
  } else if (env.TERM_PROGRAM === "Apple_Terminal") {
    result.terminal_app = "Terminal";
  } else if (env.TERM_PROGRAM) {
    result.terminal_app = env.TERM_PROGRAM;
  }
  if (detectedTty) result.terminal_tty = detectedTty;
  return result;
}

function textFromContent(content: unknown): string | undefined {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return undefined;
  const text = content
    .map((block: any) => block?.type === "text" ? block.text : undefined)
    .filter(Boolean)
    .join("\n");
  return text || undefined;
}

function compact(value: unknown, limit = 4000): string | undefined {
  if (value == null) return undefined;
  let text: string;
  if (typeof value === "string") text = value;
  else {
    try { text = JSON.stringify(value); } catch { text = String(value); }
  }
  if (text.length <= limit) return text;
  return `${text.slice(0, limit)}…`;
}

export default function (pi: any) {
  let heartbeatTimer: ReturnType<typeof setInterval> | undefined;
  let heartbeatContext: any | undefined;

  function sessionID(ctx: any): string {
    return `pi-${ctx.sessionManager?.getSessionId?.() || ctx.sessionManager?.getSessionFile?.() || "ephemeral"}`;
  }

  function basePayload(ctx: any) {
    const model = ctx.model ? `${ctx.model.provider || ""}/${ctx.model.id || ctx.model.name || ""}`.replace(/^\//, "") : undefined;
    return {
      session_id: sessionID(ctx),
      cwd: ctx.cwd || process.cwd(),
      transcript_path: ctx.sessionManager?.getSessionFile?.(),
      model,
      ...terminalFields(),
    };
  }

  function command(ctx: any, hook_event_name: string, extra: Record<string, unknown> = {}) {
    return {
      type: "processPiHook",
      piHook: {
        hook_event_name,
        ...basePayload(ctx),
        ...extra,
      },
    };
  }

  function sendHeartbeat() {
    if (!heartbeatContext) return;
    fireAndForget(command(heartbeatContext, "Heartbeat"));
  }

  pi.on("session_start", async (_event: any, ctx: any) => {
    heartbeatContext = ctx;
    fireAndForget(command(ctx, "SessionStart"));
    if (!heartbeatTimer) {
      heartbeatTimer = setInterval(sendHeartbeat, 10_000);
    }
  });

  pi.on("input", async (event: any, ctx: any) => {
    if (event.source === "extension") return { action: "continue" };
    fireAndForget(command(ctx, "UserPromptSubmit", { prompt: event.text }));
    return { action: "continue" };
  });

  pi.on("agent_start", async (_event: any, ctx: any) => {
    fireAndForget(command(ctx, "AgentStart"));
  });

  pi.on("tool_call", async (event: any, ctx: any) => {
    const payload = {
      tool_name: event.toolName,
      tool_use_id: event.toolCallId,
      tool_input: compact(event.input),
    };

    if (!APPROVAL_TOOL_NAMES.has(event.toolName)) {
      fireAndForget(command(ctx, "PostToolUse", payload));
      return;
    }

    const response: any = await sendToSocket(command(ctx, "PreToolUse", payload), 24 * 60 * 60 * 1000);
    const directive = response?.response?.directive;
    if (response?.response?.type === "piHookDirective" && directive?.type === "deny") {
      return { block: true, reason: directive.reason || "Denied by Open Island" };
    }
  });

  pi.on("tool_result", async (event: any, ctx: any) => {
    fireAndForget(command(ctx, "PostToolUse", {
      tool_name: event.toolName,
      tool_use_id: event.toolCallId,
      tool_input: compact(event.input),
    }));
  });

  pi.on("agent_end", async (event: any, ctx: any) => {
    const lastAssistant = [...(event.messages || [])].reverse().find((m: any) => m?.role === "assistant");
    fireAndForget(command(ctx, "Stop", {
      last_assistant_message: textFromContent(lastAssistant?.content),
    }));
  });

  pi.on("session_shutdown", async (_event: any, ctx: any) => {
    if (heartbeatTimer) {
      clearInterval(heartbeatTimer);
      heartbeatTimer = undefined;
    }
    heartbeatContext = undefined;
    fireAndForget(command(ctx, "SessionEnd"));
  });
}
