#!/usr/bin/env node
// Exercises the bundled OpenCode plugin's OpenCode 2 entrypoint against a fake
// bridge socket and a fake form endpoint. OpenCode 1.x cannot be exercised here
// because it loads the plugin through its own Bun runtime.
//
// Usage: node scripts/test-opencode-plugin.mjs [path-to-plugin.js]
import { createServer as createHttpServer } from "http";
import { createServer as createSocketServer } from "net";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pluginPath = resolve(
  process.argv[2] || join(repoRoot, "Sources/OpenIslandApp/Resources/open-island-opencode.js"),
);

const workDir = mkdtempSync(join(tmpdir(), "open-island-plugin-test-"));
const socketPath = join(workDir, "bridge.sock");
const stateHome = join(workDir, "state");
const modulePath = join(workDir, "plugin.mjs");
copyFileSync(pluginPath, modulePath);

const commands = [];
const directives = new Map(); // request id -> directive returned to a blocking request
const formReplies = [];
const results = [];

function check(name, ok, detail) {
  results.push({ name, ok: Boolean(ok), detail });
}

const socket = createSocketServer((client) => {
  let buffer = "";
  client.write(JSON.stringify({ type: "hello", hello: { protocolVersion: 1, serverLabel: "test" } }) + "\n");
  client.on("error", () => {});
  client.on("data", (chunk) => {
    buffer += chunk.toString();
    const newline = buffer.indexOf("\n");
    if (newline === -1) return;
    const envelope = JSON.parse(buffer.slice(0, newline));
    buffer = buffer.slice(newline + 1);
    commands.push(envelope.command);

    const hook = envelope.command.openCodeHook;
    const requestID = hook?._opencode_request_id;
    const blocking = hook?.hook_event_name === "PermissionRequest" || hook?.hook_event_name === "QuestionAsked";
    const directive = blocking && requestID ? directives.get(requestID) : undefined;
    if (!directive) {
      client.write(JSON.stringify({ type: "response", response: { type: "acknowledged" } }) + "\n");
      client.end();
      return;
    }
    setTimeout(() => {
      client.write(JSON.stringify({ type: "response", response: { type: "openCodeHookDirective", directive } }) + "\n");
      client.end();
    }, 5);
  });
});

const formServer = createHttpServer((request, response) => {
  let body = "";
  request.on("data", (chunk) => { body += chunk; });
  request.on("end", () => {
    formReplies.push({ method: request.method, url: request.url, body: body ? JSON.parse(body) : null });
    response.writeHead(204);
    response.end();
  });
});

const waiters = [];
function pushEvent(event) {
  for (const waiter of waiters.splice(0)) waiter(event);
}
async function* subscribe() {
  while (true) {
    yield await new Promise((resolve) => waiters.push(resolve));
  }
}

const repliedPermissions = [];
const ctx = {
  session: {
    async get({ sessionID }) {
      return { data: { sessionID, location: { directory: "/tmp/looked-up" } } };
    },
  },
  permission: {
    async reply(input) { repliedPermissions.push(input); },
  },
  shell: { hook: async () => ({ dispose: async () => {} }) },
  event: { subscribe },
};

const events = [
  { id: "e1", type: "session.created", data: { sessionID: "ses_a", location: { directory: "/work/a" } } },
  { id: "e2", type: "session.inbox.enqueued", data: { sessionID: "ses_a", item: { type: "user", payload: { text: "fix the bug" } } } },
  { id: "e3", type: "session.inbox.enqueued", data: { sessionID: "ses_a", item: { type: "synthetic", payload: { text: "ignored" } } } },
  { id: "e4", type: "session.tool.input.started", data: { sessionID: "ses_a", id: "call_1", name: "shell" } },
  { id: "e5", type: "session.tool.called", data: { sessionID: "ses_a", id: "call_1", input: { command: "ls -la" } } },
  { id: "e6", type: "session.tool.success", data: { sessionID: "ses_a", id: "call_1" } },
  { id: "e7", type: "session.text.ended", data: { sessionID: "ses_a", text: "All set." } },
  { id: "e8", type: "session.execution.succeeded", data: { sessionID: "ses_a" } },
  // The same event reaches every plugin instance in OpenCode 2.
  { id: "e8", type: "session.execution.succeeded", data: { sessionID: "ses_a" } },
  { id: "e9", type: "permission.asked", data: { sessionID: "ses_a", id: "per_1", action: "shell", resources: ["rm -rf build"] } },
  { id: "e10", type: "permission.replied", data: { sessionID: "ses_a", requestID: "per_1", reply: "once" } },
  {
    id: "e11",
    type: "form.created",
    data: {
      form: {
        id: "frm_1",
        sessionID: "ses_a",
        title: "Question",
        metadata: { kind: "question" },
        fields: [{
          key: "choice",
          type: "string",
          title: "Pick one",
          description: "Which one?",
          options: [{ value: "a", label: "Alpha" }, { value: "b", label: "Beta" }],
        }],
      },
    },
  },
  { id: "e12", type: "form.replied", data: { sessionID: "ses_a", id: "frm_1", answer: { choice: "a" } } },
  {
    id: "e13",
    type: "form.created",
    data: {
      form: {
        id: "frm_2",
        sessionID: "ses_a",
        title: "Question",
        metadata: { kind: "question" },
        fields: [
          { key: "first", type: "string", title: "First", description: "Pick first", options: [{ value: "a", label: "Alpha" }, { value: "b", label: "Beta" }] },
          { key: "second", type: "multiselect", title: "Second", description: "Pick second", options: [{ value: "c", label: "Charlie" }, { value: "d", label: "Delta" }] },
        ],
      },
    },
  },
  { id: "e14", type: "session.execution.succeeded", data: { sessionID: "ses_b" } },
  { id: "e15", type: "session.deleted", data: { sessionID: "ses_b" } },
];

directives.set("per_1", { type: "allow" });
directives.set("frm_1", { type: "answer", text: "Alpha" });
directives.set("frm_2", { type: "answer", text: "Pick first: Alpha · Pick second: Delta, Charlie" });

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function run() {
  await new Promise((resolve) => socket.listen(socketPath, resolve));
  await new Promise((resolve) => formServer.listen(0, "127.0.0.1", resolve));

  mkdirSync(join(stateHome, "opencode"), { recursive: true });
  writeFileSync(
    join(stateHome, "opencode", "service.json"),
    JSON.stringify({ pid: process.pid, url: `http://127.0.0.1:${formServer.address().port}`, password: "secret" }),
  );

  process.env.XDG_STATE_HOME = stateHome;
  process.env.OPEN_ISLAND_SOCKET_PATH = socketPath;
  process.env.TERM_PROGRAM = "ghostty";
  process.env.GHOSTTY_RESOURCES_DIR = "/Applications/Ghostty.app/Contents/Resources/ghostty";

  const plugin = (await import(`file://${modulePath}`)).default;
  check("default export id", plugin.id === "open-island", plugin.id);
  check("default export setup", typeof plugin.setup === "function");
  check("default export server (OpenCode 1.x)", typeof plugin.server === "function");

  const cleanup = await plugin.setup(ctx);
  check("setup returns cleanup", typeof cleanup === "function");

  for (const event of events) {
    pushEvent(event);
    await pause(25);
  }

  const hook = (name) => commands.find((command) => command.openCodeHook?.hook_event_name === name);

  const start = hook("SessionStart");
  check("SessionStart sent", Boolean(start), JSON.stringify(start?.openCodeHook));
  check("SessionStart cwd", start?.openCodeHook.cwd === "/work/a", start?.openCodeHook.cwd);
  check("SessionStart session id", start?.openCodeHook.session_id === "opencode-ses_a", start?.openCodeHook.session_id);
  check("SessionStart terminal app", start?.openCodeHook.terminal_app === "Ghostty", start?.openCodeHook.terminal_app);

  const prompts = commands.filter((command) => command.openCodeHook?.hook_event_name === "UserPromptSubmit");
  check("UserPromptSubmit prompt", prompts[0]?.openCodeHook.prompt === "fix the bug", prompts[0]?.openCodeHook.prompt);
  check("synthetic inbox item ignored", prompts.length === 1, String(prompts.length));

  const pre = hook("PreToolUse");
  check("PreToolUse tool name", pre?.openCodeHook.tool_name === "Bash", pre?.openCodeHook.tool_name);
  check("PreToolUse tool input", pre?.openCodeHook.tool_input === '{"command":"ls -la"}', pre?.openCodeHook.tool_input);
  check("PostToolUse sent", Boolean(hook("PostToolUse")), "missing");

  const stops = commands.filter((command) => command.openCodeHook?.hook_event_name === "Stop"
    && command.openCodeHook.session_id === "opencode-ses_a");
  check("Stop sent", stops.length === 1, String(stops.length));
  check("Stop carries assistant text", stops[0]?.openCodeHook.last_assistant_message === "All set.", stops[0]?.openCodeHook.last_assistant_message);

  const permission = hook("PermissionRequest");
  check("PermissionRequest sent", Boolean(permission), JSON.stringify(permission?.openCodeHook));
  check("PermissionRequest tool name", permission?.openCodeHook.tool_name === "Bash", permission?.openCodeHook.tool_name);
  check(
    "PermissionRequest description",
    (permission?.openCodeHook.permission_description || "").includes("rm -rf build"),
    permission?.openCodeHook.permission_description,
  );
  await pause(120);
  check(
    "permission reply forwarded",
    repliedPermissions.some((entry) => entry.requestID === "per_1" && entry.decision === "once" && entry.sessionID === "ses_a"),
    JSON.stringify(repliedPermissions),
  );

  const questions = commands.filter((command) => command.openCodeHook?.hook_event_name === "QuestionAsked");
  check("QuestionAsked sent", questions.length === 2, String(questions.length));
  check("QuestionAsked options", questions[0]?.openCodeHook.questions?.[0]?.options?.length === 2, JSON.stringify(questions[0]?.openCodeHook.questions));

  const singleReply = formReplies.find((entry) => entry.url?.endsWith("/frm_1/reply"));
  check("form reply path", singleReply?.url === "/api/session/ses_a/form/frm_1/reply", singleReply?.url);
  check("form reply uses option value", singleReply?.body?.answer?.choice === "a", JSON.stringify(singleReply?.body));

  const multiReply = formReplies.find((entry) => entry.url?.endsWith("/frm_2/reply"));
  check(
    "multi-question reply maps every field",
    JSON.stringify(multiReply?.body?.answer) === JSON.stringify({ first: "a", second: ["d", "c"] }),
    JSON.stringify(multiReply?.body),
  );

  const unseen = commands.find((command) => command.openCodeHook?.hook_event_name === "Stop"
    && command.openCodeHook.session_id === "opencode-ses_b");
  check("unseen session adopts directory", unseen?.openCodeHook.cwd === "/tmp/looked-up", unseen?.openCodeHook.cwd);

  const end = hook("SessionEnd");
  check("SessionEnd sent", Boolean(end), JSON.stringify(end?.openCodeHook));
  check("SessionEnd keeps cwd", end?.openCodeHook.cwd === "/tmp/looked-up", end?.openCodeHook.cwd);

  cleanup();
}

try {
  await run();
} catch (error) {
  results.push({ name: "harness", ok: false, detail: String(error?.stack || error) });
} finally {
  socket.close();
  formServer.close();
  rmSync(workDir, { recursive: true, force: true });

  let failures = 0;
  for (const result of results) {
    if (!result.ok) failures += 1;
    console.log(`${result.ok ? "PASS" : "FAIL"} ${result.name}${result.ok || !result.detail ? "" : ` :: ${result.detail}`}`);
  }
  console.log(failures === 0 ? "ALL PASS" : `${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}
