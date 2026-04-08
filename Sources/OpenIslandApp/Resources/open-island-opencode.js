// Open Island plugin for OpenCode
// Bridges OpenCode events to the Open Island desktop app via Unix socket.
// Install: copy to ~/.config/opencode/plugins/open-island.js
import { connect } from "net";
import { appendFileSync } from "fs";

const DEBUG_LOG = "/tmp/open-island-opencode-debug.log";
function debugLog(msg) {
  try { appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] ${msg}\n`); } catch {}
}

const SOCKET_PATH =
  process.env.OPEN_ISLAND_SOCKET_PATH ||
  `${process.env.HOME}/Library/Application Support/OpenIsland/bridge.sock`;

function encodeEnvelope(command) {
  return JSON.stringify({ type: "command", command }) + "\n";
}

function sendToSocket(json) {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET_PATH }, () => {
        sock.end(encodeEnvelope(json));
      });
      let buf = "";
      sock.on("data", (chunk) => { buf += chunk.toString(); });
      sock.on("end", () => { resolve(true); });
      sock.on("error", () => resolve(false));
      sock.setTimeout(3000, () => { sock.destroy(); resolve(false); });
    } catch { resolve(false); }
  });
}

function sendAndWaitResponse(json, timeoutMs = 300000) {
  return new Promise((resolve) => {
    try {
      const sock = connect({ path: SOCKET_PATH }, () => {
        sock.write(encodeEnvelope(json));
      });
      let buf = "";
      sock.on("data", (chunk) => {
        buf += chunk.toString();
        // BridgeServer sends hello first, then response after processing
        const lines = buf.split("\n").filter(Boolean);
        if (lines.length >= 2) {
          sock.destroy();
          try { resolve(JSON.parse(lines[1])); } catch { resolve(null); }
        }
      });
      sock.on("end", () => {
        const lines = buf.split("\n").filter(Boolean);
        if (lines.length >= 2) {
          try { resolve(JSON.parse(lines[1])); } catch { resolve(null); }
        } else {
          resolve(null);
        }
      });
      sock.on("error", () => resolve(null));
      sock.setTimeout(timeoutMs, () => { sock.destroy(); resolve(null); });
    } catch { resolve(null); }
  });
}

// Terminal environment detection
let detectedTty = null;
try {
  const { execSync } = require("child_process");
  let walkPid = process.pid;
  for (let i = 0; i < 8; i++) {
    const info = execSync(`ps -o tty=,ppid= -p ${walkPid}`, { timeout: 1000 }).toString().trim();
    const parts = info.split(/\s+/);
    const tty = parts[0], ppid = parseInt(parts[1]);
    if (tty && tty !== "??" && tty !== "?") { detectedTty = `/dev/${tty}`; break; }
    if (!ppid || ppid <= 1) break;
    walkPid = ppid;
  }
} catch {}

const ENV_KEYS = [
  "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID",
  "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID",
  "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_SOCKET_PATH",
];

function collectEnv() {
  const env = {};
  for (const k of ENV_KEYS) { if (process.env[k]) env[k] = process.env[k]; }
  return env;
}

function terminalFields() {
  const env = process.env;
  const result = {};
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

function makePayload(hookEventName, sessionID, cwd, extra = {}) {
  return {
    type: "processOpenCodeHook",
    openCodeHook: {
      hook_event_name: hookEventName,
      session_id: `opencode-${sessionID}`,
      cwd: cwd || ".",
      ...terminalFields(),
      ...extra,
    },
  };
}

export default async ({ client, serverUrl }) => {
  const serverPort = serverUrl ? parseInt(serverUrl.port) || 4096 : 4096;
  const internalFetch = client?._client?.getConfig?.()?.fetch || null;
  const msgRoles = new Map();
  const sessionCwd = new Map();
  const sessions = new Map();

  function getSession(sid) {
    if (!sessions.has(sid)) sessions.set(sid, { lastAssistantText: "" });
    return sessions.get(sid);
  }

  function mapEvent(ev) {
    const t = ev.type;
    const p = ev.properties || {};

    // session.created
    if (t === "session.created" && p.info) {
      const cwd = p.info.directory || "";
      sessionCwd.set(p.info.id, cwd);
      return makePayload("SessionStart", p.info.id, cwd);
    }

    // session.deleted
    if (t === "session.deleted" && p.info) {
      sessions.delete(p.info.id);
      sessionCwd.delete(p.info.id);
      return makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id));
    }

    // session.updated (archived)
    if (t === "session.updated" && p.info) {
      if (p.info.directory) sessionCwd.set(p.info.id, p.info.directory);
      if (p.info.time?.archived) {
        sessions.delete(p.info.id);
        sessionCwd.delete(p.info.id);
        return makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id));
      }
      return null;
    }

    // session.status → idle = Stop (busy is ignored; session creation
    // comes from session.created or ensureOpenCodeSessionExists on first event)
    if (t === "session.status" && p.sessionID) {
      if (p.status?.type === "idle") {
        const s = getSession(p.sessionID);
        return makePayload("Stop", p.sessionID, sessionCwd.get(p.sessionID), {
          last_assistant_message: s.lastAssistantText || undefined,
        });
      }
      return null;
    }

    // message.updated — track role for message parts
    if (t === "message.updated" && p.info?.id && p.info?.sessionID) {
      msgRoles.set(p.info.id, { role: p.info.role, sessionID: p.info.sessionID });
      if (msgRoles.size > 200) { msgRoles.delete(msgRoles.keys().next().value); }
      return null;
    }

    // message.part.updated — text
    if (t === "message.part.updated" && p.part?.type === "text" && p.part?.messageID) {
      const meta = msgRoles.get(p.part.messageID);
      if (!meta) return null;
      const text = p.part.text || "";
      if (meta.role === "user" && text) {
        return makePayload("UserPromptSubmit", meta.sessionID, sessionCwd.get(meta.sessionID), {
          prompt: text,
        });
      }
      if (meta.role === "assistant" && text) {
        getSession(meta.sessionID).lastAssistantText = text;
      }
      return null;
    }

    // message.part.updated — tool
    if (t === "message.part.updated" && p.part?.type === "tool" && p.part?.sessionID) {
      const st = p.part.state?.status;
      const cwd = sessionCwd.get(p.part.sessionID);
      const toolName = (p.part.tool || "").charAt(0).toUpperCase() + (p.part.tool || "").slice(1);
      if (st === "running" || st === "pending") {
        return makePayload("PreToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
          tool_input: typeof p.part.state?.input === "string"
            ? p.part.state.input
            : JSON.stringify(p.part.state?.input || {}).slice(0, 200),
        });
      }
      if (st === "completed" || st === "error") {
        return makePayload("PostToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
        });
      }
      return null;
    }

    // permission.asked
    if (t === "permission.asked" && p.id && p.sessionID) {
      const toolName = (p.permission || "").charAt(0).toUpperCase() + (p.permission || "").slice(1);
      const patterns = p.patterns || [];
      const toolInput = { patterns, metadata: p.metadata };
      if (p.permission === "bash" && patterns.length > 0) {
        toolInput.command = patterns.join(" && ");
      }
      if ((p.permission === "edit" || p.permission === "write") && patterns.length > 0) {
        toolInput.file_path = patterns[0];
      }
      return makePayload("PermissionRequest", p.sessionID, sessionCwd.get(p.sessionID), {
        tool_name: toolName,
        tool_input: JSON.stringify(toolInput).slice(0, 200),
        permission_id: p.id,
        permission_title: `Allow ${toolName}`,
        permission_description: patterns.length > 0
          ? `OpenCode wants to run ${toolName}: ${patterns[0]}`
          : `OpenCode wants to run ${toolName}`,
        _opencode_request_id: p.id,
      });
    }

    // permission.replied
    if (t === "permission.replied" && p.sessionID) {
      return makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    // question.asked
    if (t === "question.asked" && p.id && p.sessionID) {
      return makePayload("QuestionAsked", p.sessionID, sessionCwd.get(p.sessionID), {
        question_id: p.id,
        question_text: (p.questions || []).map(q => q.question).join("; ") || "OpenCode has a question",
        _opencode_request_id: p.id,
      });
    }

    // question.replied / question.rejected
    if ((t === "question.replied" || t === "question.rejected") && p.sessionID) {
      return makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    return null;
  }

  return {
    "event": async ({ event }) => {
      try {
        debugLog(`EVENT: ${event.type} | props: ${JSON.stringify(event.properties || {}).slice(0, 300)}`);
        const mapped = mapEvent(event);
        if (mapped) {
          debugLog(`MAPPED: ${mapped.openCodeHook.hook_event_name} sid=${mapped.openCodeHook.session_id}`);
        }
        if (!mapped) return;

        // Permission request — hold connection for approval
        if (mapped.openCodeHook.hook_event_name === "PermissionRequest" && internalFetch) {
          const requestId = mapped.openCodeHook._opencode_request_id;
          sendAndWaitResponse(mapped).then(async (response) => {
            if (!response) return;
            const directive = response?.response?.directive;
            if (!directive) return;
            const reply = directive.type === "allow" ? "once" : "reject";
            const message = directive.type === "deny" ? directive.reason : undefined;
            try {
              await internalFetch(new Request(`http://localhost:${serverPort}/permission/${requestId}/reply`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ reply, message }),
              }));
            } catch {}
          });
          return;
        }

        // Question — hold connection for answer
        if (mapped.openCodeHook.hook_event_name === "QuestionAsked" && internalFetch) {
          const requestId = mapped.openCodeHook._opencode_request_id;
          sendAndWaitResponse(mapped).then(async (response) => {
            if (!response) return;
            const directive = response?.response?.directive;
            if (!directive) return;
            if (directive.type === "answer") {
              try {
                await internalFetch(new Request(`http://localhost:${serverPort}/question/${requestId}/reply`, {
                  method: "POST",
                  headers: { "Content-Type": "application/json" },
                  body: JSON.stringify({ answers: [[directive.text]] }),
                }));
              } catch {}
            }
          });
          return;
        }

        // Regular events — fire and forget
        await sendToSocket(mapped);
      } catch {
        // Fail open: if Open Island is unavailable, don't block OpenCode
      }
    },

    "shell.env": async (input, output) => {
      output.env.OPEN_ISLAND_ACTIVE = "1";
      for (const v of ENV_KEYS) {
        if (process.env[v]) output.env["_OI_" + v] = process.env[v];
      }
    },
  };
};
