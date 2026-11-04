// Open Island plugin for OpenCode
// Bridges OpenCode events to the Open Island desktop app via Unix socket.
// Install: copy to ~/.config/opencode/plugins/open-island.js
//
// One file serves both OpenCode plugin APIs:
// - OpenCode 1.x calls `server()` and uses the hooks it returns.
// - OpenCode 2 reads `id` + `setup(ctx)` and ignores `server()`. It runs plugins
//   in a background server and streams `{ type, data }` events instead of the
//   1.x `{ type, properties }` shape, and turns the question tool into a form.
import { connect } from "net";
import { appendFileSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { execFileSync } from "child_process";

const DEBUG_LOG = "/tmp/open-island-opencode-debug.log";
function debugLog(msg) {
  try { appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] ${msg}\n`); } catch {}
}

const SOCKET_PATH =
  process.env.OPEN_ISLAND_SOCKET_PATH ||
  `${process.env.HOME || homedir()}/Library/Application Support/OpenIsland/bridge.sock`;

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
const ENV_KEYS = [
  "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID",
  "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID",
  "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_SOCKET_PATH",
  "ZELLIJ", "ZELLIJ_PANE_ID", "ZELLIJ_SESSION_NAME",
];

function detectTerminalApp(env) {
  if (env.ITERM_SESSION_ID) return "iTerm";
  if (env.CMUX_WORKSPACE_ID || env.CMUX_SOCKET_PATH) return "cmux";
  if (env.ZELLIJ != null) return "Zellij";
  if (env.GHOSTTY_RESOURCES_DIR || (env.TERM_PROGRAM || "").toLowerCase().includes("ghostty")) return "Ghostty";
  if (env.TERM_PROGRAM === "Apple_Terminal") return "Terminal";
  if (env.TERM_PROGRAM) return env.TERM_PROGRAM;
  return null;
}

function detectTerminalTTY() {
  try {
    let walkPid = process.pid;
    for (let i = 0; i < 8; i++) {
      const info = execFileSync("ps", ["-o", "tty=,ppid=", "-p", String(walkPid)], { timeout: 1000 })
        .toString()
        .trim();
      const parts = info.split(/\s+/);
      const tty = parts[0];
      const ppid = parseInt(parts[1]);
      if (tty && tty !== "??" && tty !== "?") return `/dev/${tty}`;
      if (!ppid || ppid <= 1) break;
      walkPid = ppid;
    }
  } catch {}
  return null;
}

/// Terminal hints for the payload. OpenCode 2 runs plugins in the shared
/// background service (`serve --service`), which outlives the client that
/// started it: a tab, pane or TTY id there belongs to that first client, not to
/// the session's own terminal. Only app-level hints are meaningful in that case.
function terminalFields(env, tty, sharedService = false) {
  const result = {};
  const app = detectTerminalApp(env);
  if (app) result.terminal_app = app;

  if (!sharedService) {
    if (env.ITERM_SESSION_ID) {
      result.terminal_session_id = env.ITERM_SESSION_ID;
    } else if (env.CMUX_WORKSPACE_ID || env.CMUX_SOCKET_PATH) {
      if (env.CMUX_SURFACE_ID) result.terminal_session_id = env.CMUX_SURFACE_ID;
    } else if (env.ZELLIJ != null) {
      const paneID = env.ZELLIJ_PANE_ID || "";
      const sessionName = env.ZELLIJ_SESSION_NAME || "";
      if (paneID) result.terminal_session_id = `${paneID}:${sessionName}`;
    }
    if (tty) result.terminal_tty = tty;
  }

  return result;
}

function makeHookPayload(terminal, hookEventName, sessionID, cwd, extra = {}) {
  return {
    type: "processOpenCodeHook",
    openCodeHook: {
      hook_event_name: hookEventName,
      session_id: `opencode-${sessionID}`,
      cwd: cwd || ".",
      ...terminal,
      ...extra,
    },
  };
}

function normalizeQuestionOption(option) {
  if (typeof option === "string") {
    return { label: option };
  }
  if (!option || typeof option !== "object") {
    return null;
  }

  const label = option.label || option.text || option.value || option.name;
  if (!label) return null;

  return {
    label: String(label),
    description: option.description || option.hint || option.detail || "",
    allows_freeform: Boolean(option.allowsFreeform || option.allows_freeform),
  };
}

function normalizeQuestion(question, index) {
  if (!question || typeof question !== "object") {
    return null;
  }

  const questionText = question.question || question.title || question.prompt;
  if (!questionText) return null;

  const options = Array.isArray(question.options)
    ? question.options.map(normalizeQuestionOption).filter(Boolean)
    : [];
  if (options.length === 0) return null;

  return {
    question: String(questionText),
    header: question.header || question.label || `Question ${index + 1}`,
    options,
    multi_select: Boolean(question.multiSelect || question.multi_select),
  };
}

// ---------------------------------------------------------------------------
// OpenCode 1.x — default-exported `server()` hooks
// ---------------------------------------------------------------------------

let v1Terminal = null;
function v1TerminalFields() {
  if (!v1Terminal) {
    v1Terminal = terminalFields(process.env, detectTerminalTTY(), false);
  }
  return v1Terminal;
}

function makeV1Payload(hookEventName, sessionID, cwd, extra = {}) {
  return makeHookPayload(v1TerminalFields(), hookEventName, sessionID, cwd, extra);
}

async function openCodeV1Plugin({ client, serverUrl }) {
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
      return makeV1Payload("SessionStart", p.info.id, cwd);
    }

    // session.deleted
    if (t === "session.deleted" && p.info) {
      const cwd = sessionCwd.get(p.info.id);
      sessions.delete(p.info.id);
      sessionCwd.delete(p.info.id);
      return makeV1Payload("SessionEnd", p.info.id, cwd);
    }

    // session.updated (archived)
    if (t === "session.updated" && p.info) {
      if (p.info.directory) sessionCwd.set(p.info.id, p.info.directory);
      if (p.info.time?.archived) {
        const cwd = sessionCwd.get(p.info.id);
        sessions.delete(p.info.id);
        sessionCwd.delete(p.info.id);
        return makeV1Payload("SessionEnd", p.info.id, cwd);
      }
      return null;
    }

    // session.status → idle = Stop (busy is ignored; session creation
    // comes from session.created or ensureOpenCodeSessionExists on first event)
    if (t === "session.status" && p.sessionID) {
      if (p.status?.type === "idle") {
        const s = getSession(p.sessionID);
        return makeV1Payload("Stop", p.sessionID, sessionCwd.get(p.sessionID), {
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
        return makeV1Payload("UserPromptSubmit", meta.sessionID, sessionCwd.get(meta.sessionID), {
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
        return makeV1Payload("PreToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
          tool_input: typeof p.part.state?.input === "string"
            ? p.part.state.input
            : JSON.stringify(p.part.state?.input || {}).slice(0, 200),
        });
      }
      if (st === "completed" || st === "error") {
        return makeV1Payload("PostToolUse", p.part.sessionID, cwd, {
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
      return makeV1Payload("PermissionRequest", p.sessionID, sessionCwd.get(p.sessionID), {
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
      return makeV1Payload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    // question.asked
    if (t === "question.asked" && p.id && p.sessionID) {
      const questions = Array.isArray(p.questions)
        ? p.questions.map(normalizeQuestion).filter(Boolean)
        : [];
      return makeV1Payload("QuestionAsked", p.sessionID, sessionCwd.get(p.sessionID), {
        question_id: p.id,
        question_text: (p.questions || []).map(q => q.question).join("; ") || "OpenCode has a question",
        questions,
        _opencode_request_id: p.id,
      });
    }

    // question.replied / question.rejected
    if ((t === "question.replied" || t === "question.rejected") && p.sessionID) {
      return makeV1Payload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
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
}

// ---------------------------------------------------------------------------
// OpenCode 2 — `id` + `setup(ctx)`
// ---------------------------------------------------------------------------

const V2_TOOL_NAMES = {
  shell: "Bash",
  subagent: "Task",
  webfetch: "WebFetch",
  websearch: "WebSearch",
  external_directory: "External directory",
};

function prettyToolName(name) {
  const raw = String(name || "");
  if (!raw) return "Tool";
  return V2_TOOL_NAMES[raw] || raw.charAt(0).toUpperCase() + raw.slice(1);
}

/// OpenCode 2 loads the plugin once per location and delivers location-less
/// events to every instance in the same process. All instances share one store
/// so each event is handled once and session state stays consistent.
function sharedState() {
  const key = Symbol.for("open-island.opencode.v2");
  if (!globalThis[key]) {
    globalThis[key] = {
      claimed: new Set(),
      sessions: new Map(),
      tools: new Map(),
      pending: new Set(),
    };
  }
  return globalThis[key];
}

function claimEvent(state, id) {
  if (!id) return true;
  if (state.claimed.has(id)) return false;
  state.claimed.add(id);
  if (state.claimed.size > 2000) {
    state.claimed.delete(state.claimed.values().next().value);
  }
  return true;
}

function sessionState(state, sessionID) {
  if (!state.sessions.has(sessionID)) {
    state.sessions.set(sessionID, { cwd: "", lastAssistantText: "", lookedUp: false });
  }
  return state.sessions.get(sessionID);
}

function rememberTool(state, sessionID, callID, name) {
  if (!sessionID || !callID || !name) return;
  state.tools.set(`${sessionID}:${callID}`, name);
  if (state.tools.size > 500) {
    state.tools.delete(state.tools.keys().next().value);
  }
}

function toolNameFor(state, sessionID, callID) {
  return state.tools.get(`${sessionID}:${callID}`) || "Tool";
}

function previewJSON(value) {
  try {
    return (typeof value === "string" ? value : JSON.stringify(value || {})).slice(0, 200);
  } catch {
    return "";
  }
}

function permissionToolInput(action, resources, metadata) {
  const patterns = Array.isArray(resources) ? resources : [];
  const input = { patterns, metadata };
  if ((action === "shell" || action === "bash") && patterns.length > 0) {
    input.command = patterns.join(" && ");
  }
  if ((action === "edit" || action === "write" || action === "patch") && patterns.length > 0) {
    input.file_path = patterns[0];
  }
  return input;
}

/// The question tool asks through a form: `metadata.kind === "question"`, one
/// field per question. Other forms (MCP elicitation, auth) are not questions the
/// island can answer.
function questionsFromForm(form) {
  if (!form || form.metadata?.kind !== "question" || !Array.isArray(form.fields)) return [];
  return form.fields
    .map((field, index) => {
      const options = (field.options || []).map((option) => ({
        label: String(option.label ?? option.value ?? ""),
        description: option.description || "",
      })).filter((option) => option.label.length > 0);
      return normalizeQuestion({
        question: field.description || field.title || field.key,
        header: field.title || `Question ${index + 1}`,
        options,
        multiSelect: field.type === "multiselect",
      }, index);
    })
    .filter(Boolean);
}

/// Form answers must use option values, not labels. The island reports the
/// selected labels, joined by ", " per question.
function formValueFor(field, text) {
  const options = Array.isArray(field?.options) ? field.options : [];
  const toValue = (label) => {
    const match = options.find((option) => option.label === label || option.value === label);
    return match ? match.value : label;
  };

  if (field?.type === "multiselect") {
    return text.split(", ").map(toValue).filter((value) => value !== "");
  }

  const match = options.find((option) => option.label === text || option.value === text);
  return match ? match.value : text;
}

/// Build the `answer` object for a form from one user response. The bridge
/// reports a single string, which is the answered label for one question and
/// "question: answer · question: answer" for several.
function formAnswerFromText(form, text) {
  const fields = Array.isArray(form?.fields) ? form.fields : [];
  if (fields.length === 0 || typeof text !== "string" || text.length === 0) return null;

  if (fields.length === 1) {
    return { [fields[0].key]: formValueFor(fields[0], text) };
  }

  const answer = {};
  const segments = text.split(" · ");
  for (const field of fields) {
    const label = field.description || field.title || field.key;
    const prefix = `${label}: `;
    const segment = segments.find((entry) => entry.startsWith(prefix));
    if (!segment) continue;
    answer[field.key] = formValueFor(field, segment.slice(prefix.length));
  }

  return Object.keys(answer).length > 0 ? answer : null;
}

function firstOptionAnswer(form) {
  const fields = Array.isArray(form?.fields) ? form.fields : [];
  const answer = {};
  for (const field of fields) {
    const option = (field.options || [])[0];
    if (!option) continue;
    answer[field.key] = field.type === "multiselect" ? [option.value] : option.value;
  }
  return Object.keys(answer).length > 0 ? answer : null;
}

/// The shared service registers its HTTP endpoint; forms have no plugin API, so
/// answering a question needs that route. Accept the file only when it names
/// this very process.
function serviceEndpoint() {
  try {
    const stateHome = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
    const info = JSON.parse(readFileSync(join(stateHome, "opencode", "service.json"), "utf8"));
    if (info?.pid !== process.pid || typeof info.url !== "string") return null;
    return { url: info.url, password: info.password };
  } catch {
    return null;
  }
}

async function formRequest(endpoint, method, path, body) {
  if (!endpoint) return false;
  const headers = { "Content-Type": "application/json" };
  if (endpoint.password) {
    headers.Authorization = "Basic " + Buffer.from(`opencode:${endpoint.password}`).toString("base64");
  }
  try {
    const response = await fetch(new URL(path, endpoint.url), {
      method,
      headers,
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) {
      debugLog(`FORM REQUEST FAILED ${method} ${path} -> ${response.status}`);
    }
    return response.ok;
  } catch (error) {
    debugLog(`FORM REQUEST ERROR ${method} ${path}: ${String(error)}`);
    return false;
  }
}

function replyForm(endpoint, sessionID, formID, answer) {
  return formRequest(
    endpoint,
    "POST",
    `/api/session/${encodeURIComponent(sessionID)}/form/${encodeURIComponent(formID)}/reply`,
    { answer },
  );
}

function cancelForm(endpoint, sessionID, formID) {
  return formRequest(
    endpoint,
    "DELETE",
    `/api/session/${encodeURIComponent(sessionID)}/form/${encodeURIComponent(formID)}`,
  );
}

/// Map one OpenCode 2 event to an Open Island hook payload. Returns
/// `{ payload, form? }` or null. No I/O: session lookups happen in the caller.
function mapV2Event(state, terminal, event) {
  const type = event?.type;
  const data = event?.data || {};
  const sessionID = data.sessionID || data.form?.sessionID;
  if (!sessionID) return null;

  const session = sessionState(state, sessionID);
  const payload = (hookEventName, extra) =>
    makeHookPayload(terminal, hookEventName, sessionID, session.cwd, extra);

  switch (type) {
    case "session.created":
      if (data.location?.directory) session.cwd = data.location.directory;
      return { payload: payload("SessionStart") };

    case "session.moved":
      if (data.location?.directory) session.cwd = data.location.directory;
      return null;

    case "session.renamed":
      return null;

    case "session.deleted":
    case "session.archived": {
      const result = { payload: payload("SessionEnd") };
      state.sessions.delete(sessionID);
      return result;
    }

    // A new user prompt was admitted. Reset the assistant text so Stop only
    // reports this turn.
    case "session.inbox.enqueued": {
      if (data.item?.type !== "user") return null;
      session.lastAssistantText = "";
      const prompt = data.item.payload?.text || "";
      return { payload: payload("UserPromptSubmit", prompt ? { prompt } : {}) };
    }

    case "session.text.ended":
      if (data.text) session.lastAssistantText = data.text;
      return null;

    // Plugins do not receive session.status / session.idle in OpenCode 2, so a
    // finished execution is the turn boundary.
    case "session.execution.succeeded":
    case "session.execution.failed":
    case "session.execution.interrupted":
      return {
        payload: payload("Stop", {
          last_assistant_message: session.lastAssistantText || undefined,
        }),
      };

    // Only this event names the tool; called/success/failed carry the call id.
    case "session.tool.input.started":
      rememberTool(state, sessionID, data.id, prettyToolName(data.name));
      return null;

    case "session.tool.called":
      return {
        payload: payload("PreToolUse", {
          tool_name: toolNameFor(state, sessionID, data.id),
          tool_input: previewJSON(data.input),
        }),
      };

    case "session.tool.success":
    case "session.tool.failed":
      return {
        payload: payload("PostToolUse", {
          tool_name: toolNameFor(state, sessionID, data.id),
        }),
      };

    case "permission.asked": {
      if (!data.id) return null;
      const toolName = prettyToolName(data.action);
      const resources = Array.isArray(data.resources) ? data.resources : [];
      const input = permissionToolInput(data.action, resources, data.metadata);
      return {
        payload: payload("PermissionRequest", {
          tool_name: toolName,
          tool_input: previewJSON(input),
          permission_id: data.id,
          permission_title: `Allow ${toolName}`,
          permission_description: resources.length > 0
            ? `OpenCode wants to run ${toolName}: ${resources[0]}`
            : `OpenCode wants to run ${toolName}`,
          _opencode_request_id: data.id,
        }),
        permissionRequestID: data.id,
      };
    }

    case "permission.replied":
      return { payload: payload("PostToolUse") };

    case "form.created": {
      const form = data.form;
      const questions = questionsFromForm(form);
      if (!form?.id || questions.length === 0) return null;
      const questionText = (form.fields || [])
        .map((field) => field.description || field.title || field.key)
        .filter(Boolean)
        .join("; ");
      return {
        payload: payload("QuestionAsked", {
          question_id: form.id,
          question_text: questionText || form.title || "OpenCode has a question",
          questions,
          _opencode_request_id: form.id,
        }),
        form,
      };
    }

    case "form.replied":
    case "form.cancelled":
      return { payload: payload("PostToolUse") };

    default:
      return null;
  }
}

function setupOpenCodeV2(ctx) {
  const sharedService = process.argv.includes("serve") && process.argv.includes("--service");
  const terminal = terminalFields(
    process.env,
    sharedService ? null : detectTerminalTTY(),
    sharedService,
  );
  const state = sharedState();
  let endpoint = null;
  // Computed lazily: the shared service may write its registration after the
  // plugin loads, so keep retrying until it names this process.
  function currentEndpoint() {
    if (!endpoint) endpoint = serviceEndpoint();
    return endpoint;
  }

  async function adoptSession(sessionID) {
    const session = sessionState(state, sessionID);
    if (session.cwd || session.lookedUp) return;
    session.lookedUp = true;
    try {
      const response = await ctx.session.get({ sessionID });
      const info = response?.data ?? response;
      if (info?.location?.directory) session.cwd = info.location.directory;
    } catch {}
  }

  function settlePermission(requestID, sessionID, directive) {
    const reply = directive.type === "allow" ? "once" : "reject";
    const message = directive.type === "deny" ? directive.reason : undefined;
    return ctx.permission
      .reply({ sessionID, requestID, decision: reply, ...(message ? { message } : {}) })
      .catch((error) => debugLog(`PERMISSION REPLY FAILED ${requestID}: ${String(error)}`));
  }

  async function settleForm(form, directive) {
    const target = currentEndpoint();
    if (!target) return;
    if (directive.type === "deny") {
      await cancelForm(target, form.sessionID, form.id);
      return;
    }
    const answer = directive.type === "answer"
      ? formAnswerFromText(form, directive.text)
      : firstOptionAnswer(form);
    if (!answer) return;
    await replyForm(target, form.sessionID, form.id, answer);
  }

  async function handle(event) {
    if (!claimEvent(state, event?.id)) return;

    try {
      const sessionID = event?.data?.sessionID || event?.data?.form?.sessionID;
      if (sessionID && event.type !== "session.created") await adoptSession(sessionID);

      const mapped = mapV2Event(state, terminal, event);
      if (!mapped) return;

      const rawSessionID = sessionID || "";
      const hookEventName = mapped.payload.openCodeHook.hook_event_name;
      debugLog(`V2 EVENT: ${event.type} ${rawSessionID} id=${event.id} -> ${hookEventName}`);

      // While Open Island holds a request for a session, unrelated activity must
      // not clear the pending card. Replies, start and end always flow.
      const isReply = event.type === "permission.replied"
        || event.type === "form.replied"
        || event.type === "form.cancelled";
      if (!isReply
          && state.pending.has(rawSessionID)
          && hookEventName !== "SessionStart"
          && hookEventName !== "SessionEnd") {
        return;
      }

      if (hookEventName === "PermissionRequest" && mapped.permissionRequestID) {
        const requestID = mapped.permissionRequestID;
        state.pending.add(rawSessionID);
        sendAndWaitResponse(mapped.payload)
          .then((response) => {
            const directive = response?.response?.directive;
            if (!directive) return;
            return settlePermission(requestID, rawSessionID, directive);
          })
          .catch(() => {})
          .finally(() => state.pending.delete(rawSessionID));
        return;
      }

      if (hookEventName === "QuestionAsked" && mapped.form) {
        // Forms have no plugin API. Without the shared service's HTTP endpoint
        // the island cannot answer, so leave the question in the client.
        if (!currentEndpoint()) {
          debugLog(`QUESTION SKIPPED (no endpoint) ${mapped.form.id}`);
          return;
        }
        const form = mapped.form;
        state.pending.add(rawSessionID);
        sendAndWaitResponse(mapped.payload)
          .then((response) => {
            const directive = response?.response?.directive;
            if (!directive) return;
            return settleForm(form, directive);
          })
          .catch(() => {})
          .finally(() => state.pending.delete(rawSessionID));
        return;
      }

      const delivered = await sendToSocket(mapped.payload);
      if (!delivered) debugLog(`SOCKET SEND FAILED ${event.type} -> ${hookEventName}`);
    } catch (error) {
      // Fail open: if Open Island is unavailable, don't block OpenCode
      debugLog(`V2 EVENT ERROR ${event?.type}: ${String(error)}`);
    }
  }

  const controller = new AbortController();
  // setup() is awaited before the plugin counts as loaded, so consume the stream
  // in the background and stop it from the cleanup below.
  void (async () => {
    try {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        await handle(event);
      }
    } catch (error) {
      if (!controller.signal.aborted) debugLog(`V2 STREAM ERROR: ${String(error)}`);
    }
  })();

  if (typeof ctx.shell?.hook === "function") {
    try {
      const registration = ctx.shell.hook("create.before", (event) => {
        event.env.OPEN_ISLAND_ACTIVE = "1";
        if (sharedService) return;
        for (const key of ENV_KEYS) {
          if (process.env[key]) event.env[`_OI_${key}`] = process.env[key];
        }
      });
      if (registration && typeof registration.catch === "function") {
        registration.catch(() => {});
      }
    } catch {}
  }

  return () => controller.abort();
}

export default {
  id: "open-island",
  setup: setupOpenCodeV2,
  server: openCodeV1Plugin,
};
