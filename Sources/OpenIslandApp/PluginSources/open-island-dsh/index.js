// Open Island bridge plugin for DeepSeek Harness (dsh).
//
// Forwards cordis lifecycle events to the Open Island Unix socket so the
// notch app can show session cards, activity, and completion alerts.
//
// Iron rules baked into this file:
// - Fail-open: any error here is swallowed and never affects dsh itself.
// - `tools/pre-execute` is a middleware: `next()` is ALWAYS awaited, in a
//   try/finally, so tool execution can never be blocked by this plugin.
// - Zero dependencies — plain Node builtins only, no build step.
import { connect } from "node:net";
import { homedir } from "node:os";
import { appendFileSync } from "node:fs";
import { join } from "node:path";

const SOCKET_PATH =
  process.env.OPEN_ISLAND_SOCKET_PATH ||
  `${process.env.HOME || homedir()}/Library/Application Support/OpenIsland/bridge.sock`;
const DEBUG = process.env.OPEN_ISLAND_DSH_DEBUG === "1";
const DEBUG_LOG = join(homedir(), "Library/Logs/open-island-dsh.log");

function debug(tag, data) {
  if (!DEBUG) return;
  try {
    appendFileSync(DEBUG_LOG, `${new Date().toISOString()} [${tag}] ${JSON.stringify(data)}\n`);
  } catch {}
}

function sendEvent(dshHook) {
  try {
    const socket = connect({ path: SOCKET_PATH }, () => {
      socket.end(
        JSON.stringify({
          type: "command",
          command: { type: "processDshHook", dshHook },
        }) + "\n",
      );
    });
    socket.once("error", () => {});
    socket.once("close", () => {});
    socket.setTimeout(3000, () => socket.destroy());
  } catch {}
}

// DSH Session objects expose `.id` and creation metadata via `.header`
// (format version, cwd, lineage). Read defensively — DSH is a developer
// preview and payload shapes may change between versions.
function readSessionFields(session) {
  const s = session ?? {};
  const header = s.header ?? {};
  return {
    id: String(s.id ?? header.id ?? ""),
    cwd: String(s.cwd ?? header.cwd ?? process.cwd()),
  };
}

function terminalFields() {
  const env = process.env;
  const out = {};
  if (env.ITERM_SESSION_ID) {
    out.terminal_app = "iTerm";
  } else if (env.GHOSTTY_RESOURCES_DIR || (env.TERM_PROGRAM || "").toLowerCase().includes("ghostty")) {
    out.terminal_app = "Ghostty";
  } else if (env.TERM_PROGRAM === "Apple_Terminal") {
    out.terminal_app = "Terminal";
  } else if (env.TERM_PROGRAM) {
    out.terminal_app = env.TERM_PROGRAM;
  }
  return out;
}

// Durable message text: content is an array of blocks; only "text" blocks
// carry human-readable text (reasoning / tool-call blocks are skipped).
function messageText(message) {
  const content = message?.content;
  if (!Array.isArray(content)) return undefined;
  const texts = content
    .filter((b) => b && typeof b === "object" && b.type === "text" && typeof b.text === "string")
    .map((b) => b.text.trim())
    .filter((t) => t.length > 0);
  return texts.length > 0 ? texts.join("\n") : undefined;
}

export default class OpenIslandDshPlugin {
  constructor(ctx, config) {
    this.ctx = ctx;
    this.config = config ?? {};
    this.profile = this.config.profile ?? process.env.DSH_PROFILE ?? "";
    this.sessionBase = null;
    this.pendingUserPrompt = null;
    this.lastAssistantText = null;

    const emit = (hookEventName, extra = {}) => {
      if (!this.sessionBase) return;
      try {
        sendEvent({
          hook_event_name: hookEventName,
          ...this.sessionBase,
          profile: this.profile,
          ...extra,
        });
      } catch (e) {
        debug("emit-failed", { error: String(e) });
      }
    };
    this.emit = emit;

    // Durable session log: the authoritative source for user prompts and
    // assistant messages. `session/event` delivers (session, event) where the
    // event is `{type, seq, time, data, …}` — the append payload lives under
    // `event.data` (NOT spread onto the event). `user/message` appends the
    // message itself as data; `assistant/message` appends `{turn, step,
    // message}`. Handle both, plus a spread fallback for forward-compat.
    // NOTE the `{ global: true }` option: `session/event` is dispatched with
    // per-listener containment on the session's carrier fiber. Every in-tree
    // consumer (api-session-controller, dsh-user-questions, …) registers
    // globally; a profile plugin outside the session carrier tree otherwise
    // NEVER receives the event.
    ctx.on("session/event", (session, event) => {
      try {
        const type = event?.type;
        if (type !== "user/message" && type !== "assistant/message") return;
        const f = readSessionFields(session);
        if (!f.id) return;
        if (!this.sessionBase || this.sessionBase.session_id !== f.id) {
          this.sessionBase = { session_id: f.id, cwd: f.cwd, ...terminalFields() };
        }
        const message = event.data?.message ?? event.data ?? event.message;
        const text = messageText(message);
        if (type === "user/message") {
          this.pendingUserPrompt = text ?? this.pendingUserPrompt;
          if (text) emit("activity", { summary: `Prompt: ${text.slice(0, 100)}` });
        } else {
          this.lastAssistantText = text ?? this.lastAssistantText;
        }
        debug("session/event", { type, hasText: typeof text === "string" });
      } catch (e) {
        debug("session-event-failed", { error: String(e) });
      }
    }, { global: true });

    ctx.on("session/created", (session) => {
      const f = readSessionFields(session);
      debug("session/created", f);
      if (!f.id) return;
      this.sessionBase = { session_id: f.id, cwd: f.cwd, ...terminalFields() };
      emit("sessionStart", {
        summary: `Started dsh${this.profile ? ` (${this.profile})` : ""} session.`,
      });
    });

    ctx.on("session/disposed", (session) => {
      const f = readSessionFields(session);
      debug("session/disposed", f);
      if (!f.id) return;
      this.sessionBase = { session_id: f.id, cwd: f.cwd, ...terminalFields() };
      emit("sessionEnd");
    });

    ctx.on("agent/status", (data) => {
      debug("agent/status", data);
      const status = data?.status;
      if (status === "idle") {
        emit("turnCompleted", {
          last_assistant_message: this.lastAssistantText,
        });
        this.lastAssistantText = null;
        this.pendingUserPrompt = null;
      } else if (status === "running") {
        // A new turn begins: discard the previous turn's messages so the
        // completion card always reflects the work of THIS turn.
        this.lastAssistantText = null;
        emit("activity", {
          summary: this.pendingUserPrompt ? `Prompt: ${this.pendingUserPrompt.slice(0, 100)}` : "Thinking…",
        });
      }
    });

    ctx.on("agent/error", (data) => {
      debug("agent/error", data);
      emit("turnCompleted", { summary: "DeepSeek Harness reported an error." });
    });

    // `tools/pre-execute` is a cordis WATERFALL: every listener receives
    // (value, next) and its return value is passed on. The chain's tail
    // resolves to { kind: "allow" }; a listener that fails to return the
    // waterfall result makes the final gate `undefined` and the agent loop
    // crashes reading `gate.kind`. So: ALWAYS return next()'s value, even
    // when the telemetry above threw (try/finally guarantees it).
    ctx.on("tools/pre-execute", async (exec, next) => {
      try {
        debug("tools/pre-execute", { name: exec?.name });
        emit("activity", {
          tool_name: typeof exec?.name === "string" ? exec.name : undefined,
          tool_input_preview: (() => {
            try {
              const raw = JSON.stringify(exec?.arguments ?? exec?.args ?? {});
              return raw.length > 110 ? `${raw.slice(0, 109)}…` : raw;
            } catch {
              return undefined;
            }
          })(),
        });
      } catch {}
      return await next();
    });
  }

  async stop() {
    // cordis dispose hook — nothing persistent to clean up.
  }
}
