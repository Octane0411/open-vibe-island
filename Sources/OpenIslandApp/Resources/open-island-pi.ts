// Open Island extension for Pi and Oh My Pi.
// Installed into ~/.pi/agent/extensions or ~/.omp/agent/extensions.
import { connect } from "node:net";
import { homedir } from "node:os";
import { execFileSync } from "node:child_process";

const AGENT_SOURCE = "__OPEN_ISLAND_PI_SOURCE__";
const SESSION_PREFIX = AGENT_SOURCE === "oh-my-pi" ? "omp" : "pi";
const SOCKET_PATH =
  process.env.OPEN_ISLAND_SOCKET_PATH ||
  `${process.env.HOME || homedir()}/Library/Application Support/OpenIsland/bridge.sock`;
const DEFAULT_HEARTBEAT_INTERVAL_MS = 15_000;
const MAX_TIMER_INTERVAL_MS = 2_147_483_647;

function heartbeatIntervalFromEnvironment(value: string | undefined): number {
  if (value === undefined) return DEFAULT_HEARTBEAT_INTERVAL_MS;

  const parsed = Number(value);
  if (
    !Number.isSafeInteger(parsed)
    || parsed <= 0
    || parsed > MAX_TIMER_INTERVAL_MS
  ) {
    return DEFAULT_HEARTBEAT_INTERVAL_MS;
  }

  return parsed;
}

const HEARTBEAT_INTERVAL_MS = heartbeatIntervalFromEnvironment(
  process.env.OPEN_ISLAND_HEARTBEAT_INTERVAL_MS,
);

interface SessionManagerLike {
  getSessionId?: () => string;
  getSessionFile?: () => string | undefined;
}

interface ModelLike {
  provider?: string;
  id?: string;
}

interface ExtensionContextLike {
  cwd: string;
  sessionManager?: SessionManagerLike;
  model?: ModelLike;
}

interface ExtensionEvent {
  prompt?: string;
  toolName?: string;
  args?: unknown;
  reason?: string;
  message?: {
    role?: string;
    content?: unknown;
  };
}

type ExtensionHandler = (event: ExtensionEvent, ctx: ExtensionContextLike) => void | Promise<void>;

interface ExtensionAPICompat {
  on(event: string, handler: ExtensionHandler): void;
}


function sendToSocket(command: unknown): Promise<void> {
  const { promise, resolve } = Promise.withResolvers<void>();

  try {
    const socket = connect({ path: SOCKET_PATH }, () => {
      socket.end(JSON.stringify({ type: "command", command }) + "\n");
    });
    socket.once("close", resolve);
    socket.once("error", resolve);
    socket.setTimeout(3000, () => {
      socket.destroy();
      resolve();
    });
  } catch {
    resolve();
  }

  return promise;
}

function detectTTY(): string | undefined {
  try {
    let pid = process.pid;
    for (let depth = 0; depth < 8; depth += 1) {
      const output = execFileSync("/bin/ps", ["-o", "tty=,ppid=", "-p", String(pid)], {
        timeout: 1000,
      }).toString().trim();
      const [tty, parent] = output.split(/\s+/);
      if (tty && tty !== "??" && tty !== "?") return `/dev/${tty}`;
      const parentPID = Number.parseInt(parent || "", 10);
      if (!parentPID || parentPID <= 1) break;
      pid = parentPID;
    }
  } catch {}
  return undefined;
}

const detectedTTY = detectTTY();

function terminalFields(): Record<string, string> {
  const env = process.env;
  const result: Record<string, string> = {};
  if (env.ITERM_SESSION_ID) {
    result.terminal_app = "iTerm";
    result.terminal_session_id = env.ITERM_SESSION_ID;
  } else if (env.CMUX_WORKSPACE_ID || env.CMUX_SOCKET_PATH) {
    result.terminal_app = "cmux";
    if (env.CMUX_SURFACE_ID) result.terminal_session_id = env.CMUX_SURFACE_ID;
  } else if (env.ZELLIJ != null) {
    result.terminal_app = "Zellij";
    const paneID = env.ZELLIJ_PANE_ID || "";
    const sessionName = env.ZELLIJ_SESSION_NAME || "";
    if (paneID) result.terminal_session_id = `${paneID}:${sessionName}`;
  } else if (env.GHOSTTY_RESOURCES_DIR || (env.TERM_PROGRAM || "").toLowerCase().includes("ghostty")) {
    result.terminal_app = "Ghostty";
  } else if (env.TERM_PROGRAM === "Apple_Terminal") {
    result.terminal_app = "Terminal";
  } else if (env.TERM_PROGRAM) {
    result.terminal_app = env.TERM_PROGRAM;
  }
  if (env.TERM_SESSION_ID && !result.terminal_session_id) {
    result.terminal_session_id = env.TERM_SESSION_ID;
  }
  if (detectedTTY) result.terminal_tty = detectedTTY;
  return result;
}

function textContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  const texts: string[] = [];
  for (const part of content) {
    if (
      part !== null
      && typeof part === "object"
      && "type" in part
      && part.type === "text"
      && "text" in part
      && typeof part.text === "string"
    ) {
      texts.push(part.text);
    }
  }
  return texts.join("\n").trim();
}

function safeJSON(value: unknown): string | undefined {
  try {
    const encoded = JSON.stringify(value);
    return encoded.length > 500 ? `${encoded.slice(0, 499)}…` : encoded;
  } catch {
    return undefined;
  }
}

export default function openIslandPiExtension(pi: ExtensionAPICompat) {
  let lastAssistantMessage = "";
  let stopSent = false;
  let heartbeatTimer: NodeJS.Timeout | undefined;
  function contextFields(ctx: ExtensionContextLike): Record<string, unknown> {
    const sessionManager = ctx.sessionManager;
    const rawID = sessionManager?.getSessionId?.()
      || sessionManager?.getSessionFile?.()
      || `${ctx.cwd}:${process.pid}`;
    const model = ctx.model
      ? [ctx.model.provider, ctx.model.id].filter(Boolean).join("/")
      : undefined;
    return {
      agent: AGENT_SOURCE,
      session_id: `${SESSION_PREFIX}-${rawID}`,
      cwd: ctx.cwd || process.cwd(),
      model,
      transcript_path: sessionManager?.getSessionFile?.(),
      ...terminalFields(),
    };
  }

  function send(
    eventName: string,
    ctx: ExtensionContextLike,
    extra: Record<string, unknown> = {},
  ): Promise<void> {
    return sendToSocket({
      type: "processPiHook",
      piHook: {
        hook_event_name: eventName,
        ...contextFields(ctx),
        ...extra,
      },
    });
  }
  function stopHeartbeat(): void {
    if (heartbeatTimer === undefined) return;
    clearInterval(heartbeatTimer);
    heartbeatTimer = undefined;
  }

  function startHeartbeat(ctx: ExtensionContextLike): void {
    stopHeartbeat();
    heartbeatTimer = setInterval(() => {
      void send("Heartbeat", ctx);
    }, HEARTBEAT_INTERVAL_MS);
    heartbeatTimer.unref();
  }


  function sendStop(ctx: ExtensionContextLike): Promise<void> {
    if (stopSent) return Promise.resolve();
    stopSent = true;
    return send("Stop", ctx, {
      last_assistant_message: lastAssistantMessage || undefined,
    });
  }

  pi.on("session_start", (_event, ctx) => {
    lastAssistantMessage = "";
    stopSent = false;
    void send("SessionStart", ctx);
    startHeartbeat(ctx);
  });

  pi.on("before_agent_start", (event, ctx) => {
    lastAssistantMessage = "";
    stopSent = false;
    void send("UserPromptSubmit", ctx, { prompt: event.prompt });
    process.env.OPEN_ISLAND_ACTIVE = "1";
  });

  pi.on("agent_start", () => {
    stopSent = false;
  });

  pi.on("tool_execution_start", (event, ctx) => {
    void send("PreToolUse", ctx, {
      tool_name: event.toolName,
      tool_input: safeJSON(event.args),
    });
  });


  pi.on("tool_execution_end", (event, ctx) => {
    void send("PostToolUse", ctx, { tool_name: event.toolName });
  });


  pi.on("message_end", (event) => {
    if (event.message?.role !== "assistant") return;
    const text = textContent(event.message.content);
    if (text) lastAssistantMessage = text;
  });

  if (AGENT_SOURCE === "oh-my-pi") {
    pi.on("session_stop", (_event, ctx) => sendStop(ctx));
  } else {
    pi.on("agent_settled", (_event, ctx) => sendStop(ctx));
  }

  pi.on("session_shutdown", (event, ctx) => {
    stopHeartbeat();
    if (event.reason === "reload") return;
    return send("SessionEnd", ctx);
  });
}
