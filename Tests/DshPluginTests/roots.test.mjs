import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { createRequire } from 'node:module'
import { connect, createServer } from 'node:net'
import { mkdtemp, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { setTimeout as delay } from 'node:timers/promises'
import test from 'node:test'
import * as plugin from '../../Sources/OpenIslandApp/Resources/open-island-dsh/open-island-dsh.js'

async function until(check) {
  const deadline = Date.now() + 2500
  while (!check()) {
    assert.ok(Date.now() < deadline, 'Expected root classification transition')
    await delay(5)
  }
}
async function runtime() {
  try {
    const require = process.env.DSH_PACKAGE_ROOT ? createRequire(join(process.env.DSH_PACKAGE_ROOT, 'package.json')) : createRequire(import.meta.url)
    const load = async name => import(pathToFileURL(require.resolve(`@deepseek-ai/${name}`)).href)
    const [{ Context }, { default: SessionStore }, { AgentRegistry }, { UserQuestionService }, { ApprovalService }, { scopeTarget }] = await Promise.all([
      load('cordis'), load('dsh-session'), load('dsh-agent'), load('dsh-user-questions'), load('dsh-user-approval'), load('dsh-scope'),
    ])
    return { Context, SessionStore, AgentRegistry, UserQuestionService, ApprovalService, scopeTarget }
  } catch (error) {
    if (process.env.DSH_PACKAGE_ROOT) throw error
  }
}
const api = await runtime()

function command(path, body) {
  return new Promise((resolve, reject) => {
    const socket = connect(path, () => socket.write(JSON.stringify(body) + '\n'))
    socket.setEncoding('utf8')
    socket.on('error', reject)
    let buffer = ''
    socket.on('data', chunk => {
      buffer += chunk
      if (!buffer.includes('\n')) return
      socket.destroy()
      resolve(JSON.parse(buffer.trim()))
    })
  })
}

test('published registry excludes children before and after registration, suppresses all child traffic and preserves proven roots', {
  skip: !api && 'Set DSH_PACKAGE_ROOT for published root and child integration',
}, async t => {
  const { Context, SessionStore, AgentRegistry, UserQuestionService, ApprovalService, scopeTarget } = api
  const directory = await mkdtemp('/tmp/oi-dsh-roots-')
  const path = join(directory, 'bridge.sock')
  const hooks = []
  const server = createServer(socket => {
    socket.setEncoding('utf8')
    socket.on('error', () => {})
    socket.write('{"type":"hello"}\n')
    let buffer = ''
    socket.on('data', chunk => { buffer += chunk })
    socket.on('end', () => hooks.push(JSON.parse(buffer).command.dshHook))
  })
  await new Promise(resolve => server.listen(path, resolve))
  t.after(async () => {
    await new Promise(resolve => server.close(resolve))
    assert.match(directory, /^\/tmp\/oi-dsh-roots-/)
    await rm(directory, { recursive: true, force: true })
  })
  const ctx = new Context()
  t.after(() => ctx.fiber.dispose())
  await ctx.plugin(SessionStore).inertia
  ctx.provide('connection', { browserPeer: {}, rpc: { handle: () => () => {} } })
  ctx.provide('webApp', { getAdvertisedUrl: () => 'http://127.0.0.1:3080/' })
  const rootSession = ctx.sessions.create('root-late-registration', { meta: { parentSession: 'fork-ancestor' } })
  const host = ctx.plugin(plugin, { socketPath: path, heartbeatIntervalMs: 15 })
  await host.inertia
  rootSession.append('turn/start', { turn: 1 })
  rootSession.append('user/message', { id: 'before-proof', role: 'user', source: { kind: 'user' },
    content: [{ type: 'text', text: 'Never replay uncertain traffic' }] }, { surfaceOp: 'append' })
  await delay(40)
  assert.equal(hooks.length, 0)
  await ctx.plugin(AgentRegistry).inertia
  await delay(25)
  assert.equal(hooks.length, 0)
  const root = { id: rootSession.id, session: rootSession, ctx }
  await ctx.agents.register(root)
  await until(() => hooks.some(hook => hook.session_id === root.id && hook.web_focus_socket))
  assert.ok(hooks.every(hook => hook.is_subagent === false && hook.session_id === root.id))
  assert.ok(hooks.every(hook => hook.parent_session_id === 'fork-ancestor'))
  assert.ok(hooks.every(hook => !hook.prompt))
  const endpoint = hooks.find(hook => hook.web_focus_socket).web_focus_socket
  const observerID = randomUUID()
  const observer = connect(endpoint)
  observer.setEncoding('utf8')
  observer.on('error', () => {})
  t.after(() => observer.destroy())
  const frames = []
  let observerBuffer = ''
  observer.on('data', chunk => {
    observerBuffer += chunk
    while (observerBuffer.includes('\n')) {
      const index = observerBuffer.indexOf('\n')
      const frame = JSON.parse(observerBuffer.slice(0, index))
      observerBuffer = observerBuffer.slice(index + 1)
      frames.push(frame)
      if (frame.type === 'interaction_ping') observer.write(JSON.stringify({
        type: 'interaction_pong', observer_id: observerID, nonce: frame.nonce,
      }) + '\n')
    }
  })
  await new Promise(resolve => observer.once('connect', resolve))
  observer.write(JSON.stringify({ type: 'observe_interactions', protocol_version: 1, observer_id: observerID }) + '\n')
  await until(() => frames.some(frame => frame.type === 'interaction_ready'))
  await ctx.plugin(UserQuestionService).inertia
  await ctx.plugin(ApprovalService, { policy: 'ask' }).inertia
  const answer = { answers: [{ id: 'choice', selected: ['A'] }] }
  const questions = [{ id: 'choice', question: 'Which?', options: [{ label: 'A' }] }]
  let nativeQuestions = 0
  let nativeApprovals = 0
  ctx.on('user-questions/request', () => {
    nativeQuestions += 1
    return answer
  })
  ctx.on('approval/request', () => {
    nativeApprovals += 1
    return 'rejected'
  })
  const children = []
  for (let index = 0; index < 4; index += 1) {
    const session = ctx.sessions.create(`child-${index}`, { meta: index % 2 === 0
      ? { origin: 'subagent', delegationDepth: 1, parentSession: root.id } : {} })
    const child = { id: session.id, session, ctx }
    const detach = ctx.agents.enter(child, root)
    t.after(detach)
    // Ownership is already authoritative before agent/created announcement.
    session.append('turn/start', { turn: 1 })
    await ctx.agents.announce(child, 'create')
    children.push(child)
  }
  const resumedSession = ctx.sessions.create('durable-child-resumed-root', {
    meta: { origin: 'subagent', delegationDepth: 1, parentSession: root.id },
  })
  const resumed = { id: resumedSession.id, session: resumedSession, ctx }
  await ctx.agents.register(resumed)
  resumedSession.append('turn/start', { turn: 1 })
  // Runtime-root admission allows this public service call, but durable child
  // classification must still delegate without creating an Open Island card.
  assert.deepEqual(await ctx.userQuestions.ask({ agent: resumed, questions }), answer)
  for (const child of children) {
    await assert.rejects(ctx.userQuestions.ask({ agent: child, questions }), { code: 'DELEGATED_CALLER' })
    assert.deepEqual(await ctx.waterfall(scopeTarget(child, child), 'user-questions/request', { agent: child, questions }, () => assert.fail('Native question missing')), answer)
    assert.equal(await ctx.approval.request({ agent: child, toolName: 'synthetic-child' }), 'rejected')
  }
  assert.equal(nativeQuestions, children.length + 1)
  assert.equal(nativeApprovals, children.length)
  const traffic = agent => {
    const session = agent.session
    session.append('tool/call', { turn: 1, step: 1, callId: `${agent.id}-tool`, name: 'read', arguments: '{}' })
    session.append('tool/result', { turn: 1, step: 1, message: { id: `${agent.id}-result`, role: 'tool',
      source: { kind: 'tool', callId: `${agent.id}-tool` }, toolCallId: `${agent.id}-tool`, content: [{ type: 'text', text: 'child-private-output' }],
    } }, { surfaceOp: 'append' })
    session.append('assistant/message', { turn: 1, step: 1, message: { id: `${agent.id}-assistant`, role: 'assistant',
      source: { kind: 'model', provider: 'test', model: 'test' }, content: [{ type: 'text', text: 'child-private-completion' }],
    }, stream: [] }, { surfaceOp: 'append' })
    session.append('turn/end', { turn: 1, reason: { kind: 'completed' } })
  }
  await Promise.all([...children, resumed].map(async child => traffic(child)))
  rootSession.append('tool/call', { turn: 1, step: 1, callId: 'root-question', name: 'ask_user_question', arguments: JSON.stringify({ questions }) })
  const rootQuestion = ctx.userQuestions.ask({ agent: root, questions })
  await until(() => frames.some(frame => frame.interaction?.status === 'pending'))
  const pending = frames.find(frame => frame.interaction?.status === 'pending')
  assert.equal(pending.session_id, root.id)
  assert.deepEqual(await command(endpoint, { type: 'respond_interaction', observer_id: observerID,
    session_id: root.id, request_id: pending.interaction.request_id, ...answer }), { ok: true })
  assert.deepEqual(await rootQuestion, answer)
  await until(() => hooks.filter(hook => hook.is_subagent === true).length === children.length + 1)
  await delay(45)
  const childHooks = hooks.filter(hook => hook.session_id !== root.id)
  assert.equal(childHooks.length, children.length + 1)
  assert.ok(childHooks.every(hook => hook.is_subagent === true && hook.hook_event_name === 'SessionEnd'
    && !hook.web_focus_socket && !hook.tool_name && !hook.model && !hook.interaction_result))
  assert.ok(frames.filter(frame => frame.interaction).every(frame => frame.session_id === root.id))
  assert.ok(hooks.some(hook => hook.session_id === root.id && hook.hook_event_name === 'Heartbeat' && hook.is_subagent === false))
  assert.ok(!JSON.stringify(hooks).includes('child-private'))

  // Reclassify a previously tracked session with public ownership primitives.
  const changingSession = ctx.sessions.create('late-child-classification')
  const changing = { id: changingSession.id, session: changingSession, ctx }
  const detachRoot = ctx.agents.enter(changing, undefined)
  await ctx.agents.announce(changing, 'create')
  await until(() => hooks.some(hook => hook.session_id === changing.id && hook.hook_event_name === 'SessionStart'))
  detachRoot()
  const detachChild = ctx.agents.enter(changing, root)
  t.after(detachChild)
  await ctx.agents.announce(changing, 'resume')
  await until(() => hooks.some(hook => hook.session_id === changing.id && hook.is_subagent === true))
  const last = hooks.length
  await delay(45)
  assert.ok(hooks.slice(last).every(hook => hook.session_id !== changing.id))
  await host.dispose()
})
