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
const { createFocusRelay, createInteractionController } = plugin

async function until(check) {
  const deadline = Date.now() + 2000
  while (!check()) {
    assert.ok(Date.now() < deadline, 'Expected interaction transition')
    await delay(5)
  }
}
async function observe(path, { pong = true, observerID = randomUUID() } = {}) {
  const frames = []
  const socket = connect(path)
  socket.on('error', () => {})
  let buffer = ''
  socket.on('data', chunk => {
    buffer += chunk
    while (buffer.includes('\n')) {
      const index = buffer.indexOf('\n')
      const frame = JSON.parse(buffer.slice(0, index))
      buffer = buffer.slice(index + 1)
      frames.push(frame)
      if (pong && frame.type === 'interaction_ping') socket.write(JSON.stringify({
        type: 'interaction_pong', observer_id: observerID, nonce: frame.nonce,
      }) + '\n')
    }
  })
  await new Promise(resolve => socket.once('connect', resolve))
  socket.write(JSON.stringify({ type: 'observe_interactions', protocol_version: 1, observer_id: observerID }) + '\n')
  await until(() => frames.length)
  return { socket, frames, observerID }
}
function command(path, body) {
  return new Promise((resolve, reject) => {
    const socket = connect(path, () => socket.write(JSON.stringify(body) + '\n'))
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
const questions = [{ id: 'choice', question: 'Which?', options: [{ label: 'A' }, { label: 'B' }], multiSelect: true }]
const answer = { answers: [{ id: 'choice', selected: ['A'], custom: 'Extra' }] }

async function fixture(t, options = {}) {
  const session = { id: 'isolated-session' }
  const agent = { id: 'isolated-agent', session }
  const controller = createInteractionController({ isLive: candidate => candidate === agent, ...options })
  const relay = await createFocusRelay({ hasSession: id => id === session.id, interactions: controller })
  t.after(async () => {
    controller.close()
    await relay.close()
  })
  return { session, agent, controller, relay }
}

test('private interaction ownership validates full structured answers and rejects replay or observer impersonation', async t => {
  const { agent, controller, relay } = await fixture(t)
  let nativeCalls = 0
  const native = () => {
    nativeCalls += 1
    return answer
  }
  assert.deepEqual(await controller.request('question', { agent, questions }, native), answer)
  const observer = await observe(relay.socketPath)
  t.after(() => observer.socket.destroy())
  assert.equal(observer.frames[0].observer_id, observer.observerID)
  const other = await observe(relay.socketPath)
  t.after(() => other.socket.destroy())
  assert.equal(other.frames[0].error, 'busy')
  const waiting = controller.request('question', { agent, questions }, native)
  await until(() => observer.frames.some(frame => frame.interaction?.status === 'pending'))
  const pending = observer.frames.find(frame => frame.interaction?.status === 'pending')
  const body = { type: 'respond_interaction', observer_id: observer.observerID, session_id: agent.session.id,
    request_id: pending.interaction.request_id }
  assert.match(body.request_id, /^[0-9a-f-]{36}$/)
  for (const invalid of [
    { ...body, observer_id: randomUUID(), ...answer },
    { ...body, session_id: 'wrong', ...answer },
    { ...body, answers: [{ id: 'wrong', selected: [] }] },
    { ...body, answers: [{ id: 'choice', selected: ['invented'] }] },
    { ...body, answers: [{ id: 'choice', selected: ['A', 'A'] }] },
    { ...body, decision: 'allowed-once' },
  ]) assert.equal((await command(relay.socketPath, invalid)).ok, false)
  assert.equal(nativeCalls, 1)
  assert.deepEqual(await command(relay.socketPath, { ...body, ...answer }), { ok: true })
  assert.deepEqual(await waiting, answer)
  assert.deepEqual(await command(relay.socketPath, { ...body, ...answer }), { ok: false, error: 'stale-request' })
  await until(() => observer.frames.some(frame => frame.interaction?.status === 'resolved'))
  assert.equal(observer.frames.at(-1).interaction.resolution, 'answered')
  assert.equal(nativeCalls, 1)
})

test('a delayed app answers only one outstanding lease challenge without duplicate-pong disconnects', async t => {
  const { agent, controller, relay } = await fixture(t, { pingMs: 10, leaseMs: 200 })
  const observer = await observe(relay.socketPath, { pong: false })
  t.after(() => observer.socket.destroy())
  const waiting = controller.request('question', { agent, questions }, () => assert.fail('Healthy lease delegated'))
  await until(() => observer.frames.some(frame => frame.type === 'interaction_ping'))
  await delay(35)
  assert.equal(observer.frames.filter(frame => frame.type === 'interaction_ping').length, 1)
  const ping = observer.frames.find(frame => frame.type === 'interaction_ping')
  observer.socket.write(JSON.stringify({ type: 'interaction_pong', observer_id: observer.observerID, nonce: ping.nonce }) + '\n')
  await until(() => observer.frames.filter(frame => frame.type === 'interaction_ping').length === 2)
  const requestID = observer.frames.find(frame => frame.interaction?.status === 'pending').interaction.request_id
  assert.deepEqual(await command(relay.socketPath, { type: 'respond_interaction', observer_id: observer.observerID,
    session_id: agent.session.id, request_id: requestID, ...answer }), { ok: true })
  assert.deepEqual(await waiting, answer)
})

test('lease loss, explicit delegation, cancellation, result and disposal revoke IDs without competing resolvers', async t => {
  const { agent, controller, relay } = await fixture(t, { pingMs: 10, leaseMs: 45 })
  let nativeCalls = 0
  const native = () => {
    nativeCalls += 1
    return answer
  }
  const observer = await observe(relay.socketPath, { pong: false })
  const waiting = controller.request('question', { agent, questions }, native)
  await until(() => observer.frames.some(frame => frame.interaction))
  const staleID = observer.frames.find(frame => frame.interaction).interaction.request_id
  assert.deepEqual(await waiting, answer)
  assert.equal(nativeCalls, 1)
  const current = await observe(relay.socketPath)
  t.after(() => current.socket.destroy())
  assert.equal(controller.respond({ type: 'respond_interaction', observer_id: current.observerID,
    session_id: agent.session.id, request_id: staleID, ...answer }).error, 'stale-request')
  const cancellation = new AbortController()
  const aborted = controller.request('question', { agent, questions, signal: cancellation.signal }, native)
  cancellation.abort()
  await assert.rejects(aborted, { name: 'UserQuestionError', code: 'ASK_ABORTED' })
  const resultEnded = controller.request('question', { agent, questions, wait: { callId: 'call' } }, native)
  controller.cancelCall(agent.session, 'call')
  await assert.rejects(resultEnded, { code: 'ASK_ABORTED' })
  const approvalEnded = controller.request('approval', { agent, toolName: 'synthetic' }, native)
  controller.cancelSession(agent.session)
  assert.equal(await approvalEnded, 'cancelled')
  assert.equal(nativeCalls, 1)
  const delegated = controller.request('question', { agent, questions }, native)
  await until(() => current.frames.filter(frame => frame.interaction?.status === 'pending').length === 4)
  const id = current.frames.filter(frame => frame.interaction?.status === 'pending').at(-1).interaction.request_id
  assert.deepEqual(controller.respond({ type: 'respond_interaction', observer_id: current.observerID,
    session_id: agent.session.id, request_id: id, decision: 'delegate' }), { ok: true })
  assert.deepEqual(await delegated, answer)
  const unloaded = controller.request('question', { agent, questions }, native)
  controller.close()
  assert.deepEqual(await unloaded, answer)
  assert.equal(nativeCalls, 3)
})

async function installedRuntime() {
  try {
    const require = process.env.DSH_PACKAGE_ROOT ? createRequire(join(process.env.DSH_PACKAGE_ROOT, 'package.json')) : createRequire(import.meta.url)
    const load = async name => import(pathToFileURL(require.resolve(`@deepseek-ai/${name}`)).href)
    const [{ Context }, { default: SessionStore }, { UserQuestionService }, { ApprovalService }, { PlanModeController }, { AgentRegistry }] = await Promise.all([
      load('cordis'), load('dsh-session'), load('dsh-user-questions'), load('dsh-user-approval'), load('dsh-plan-mode'), load('dsh-agent'),
    ])
    return { Context, SessionStore, UserQuestionService, ApprovalService, PlanModeController, AgentRegistry }
  } catch (error) {
    if (process.env.DSH_PACKAGE_ROOT) throw error
  }
}
const runtime = await installedRuntime()

test('actual host plugin publishes endpoint and cancels cards on terminal results and unload', {
  skip: !runtime && 'Set DSH_PACKAGE_ROOT for published host integration',
}, async t => {
  const { Context, SessionStore, UserQuestionService } = runtime
  const directory = await mkdtemp('/tmp/oi-dsh-interaction-test-')
  const path = join(directory, 'bridge.sock')
  const hooks = []
  const server = createServer(socket => {
    socket.on('error', () => {})
    socket.write('{"type":"hello"}\n')
    let buffer = ''
    socket.on('data', chunk => { buffer += chunk })
    socket.on('end', () => hooks.push(JSON.parse(buffer).command.dshHook))
  })
  await new Promise(resolve => server.listen(path, resolve))
  t.after(async () => {
    await new Promise(resolve => server.close(resolve))
    // This exact directory was created above and contains only the test socket.
    await rm(directory, { recursive: true, force: true })
  })
  const ctx = new Context()
  t.after(() => ctx.fiber.dispose())
  await ctx.plugin(SessionStore).inertia
  const session = ctx.sessions.create('actual-host-session')
  const agent = { id: session.id, ctx, session }
  await ctx.plugin(runtime.AgentRegistry).inertia
  await ctx.agents.register(agent)
  ctx.provide('connection', { browserPeer: {}, rpc: { handle: () => () => {} } })
  ctx.provide('webApp', { getAdvertisedUrl: () => 'http://127.0.0.1:3080/' })
  await ctx.plugin(UserQuestionService).inertia
  let nativeCalls = 0
  ctx.on('user-questions/request', () => {
    nativeCalls += 1
    return answer
  })
  const host = ctx.plugin(plugin, { socketPath: path })
  await host.inertia
  await until(() => hooks.some(hook => hook.web_focus_socket))
  const endpoint = hooks.find(hook => hook.web_focus_socket).web_focus_socket
  const observer = await observe(endpoint)
  t.after(() => observer.socket.destroy())
  session.append('turn/start', { turn: 1 })
  session.append('tool/call', { turn: 1, step: 1, callId: 'actual-question-call', name: 'ask_user_question', arguments: JSON.stringify({ questions }) })
  const result = ctx.userQuestions.ask({ agent, questions })
  const settled = result.then(value => ({ value }), error => ({ error }))
  await until(() => observer.frames.some(frame => frame.interaction?.status === 'pending'))
  assert.equal(observer.frames.find(frame => frame.interaction).interaction.call_id, 'actual-question-call')
  assert.equal(observer.frames.find(frame => frame.interaction).interaction.turn_id, 1)
  session.append('tool/result', { turn: 1, step: 1, message: { id: 'actual-result', role: 'tool',
    source: { kind: 'tool', callId: 'actual-question-call' }, toolCallId: 'actual-question-call', content: [],
  } }, { surfaceOp: 'append' })
  assert.equal((await settled).error.code, 'ASK_ABORTED')
  await until(() => observer.frames.some(frame => frame.interaction?.status === 'resolved'))
  assert.equal(observer.frames.find(frame => frame.interaction?.status === 'resolved').interaction.turn_id, 1)
  const unloading = ctx.userQuestions.ask({ agent, questions })
  const unloaded = unloading.then(value => ({ value }), error => ({ error }))
  await until(() => observer.frames.filter(frame => frame.interaction?.status === 'pending').length === 2)
  await host.dispose()
  assert.equal((await unloaded).error.code, 'ASK_ABORTED')
  assert.equal(nativeCalls, 0)
})

test('published DSH services preserve native waterfall fallback, approval audit ordering and never policy', {
  skip: !runtime && 'Set DSH_PACKAGE_ROOT for published service integration',
}, async t => {
  const { Context, SessionStore, UserQuestionService, ApprovalService, PlanModeController } = runtime
  const ctx = new Context()
  t.after(() => ctx.fiber.dispose())
  await ctx.plugin(SessionStore).inertia
  const session = ctx.sessions.create('synthetic-approval-session')
  const agent = { id: 'synthetic-root', session, ctx }
  ctx.provide('agents', { get: id => id === agent.id ? agent : undefined, roots: () => [agent] })
  await ctx.plugin(UserQuestionService).inertia
  await ctx.plugin(ApprovalService, { policy: 'ask' }).inertia
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
  const controller = createInteractionController({ isLive: candidate => candidate === agent })
  t.after(() => controller.close())
  ctx.on('user-questions/request', (request, next) => controller.request('question', request, next), { prepend: true })
  ctx.on('approval/request', (request, next) => controller.request('approval', request, next), { prepend: true })
  const relay = await createFocusRelay({ hasSession: () => true, interactions: controller })
  t.after(() => relay.close())
  assert.deepEqual(await ctx.userQuestions.ask({ agent, questions }), answer)
  const observer = await observe(relay.socketPath)
  t.after(() => observer.socket.destroy())
  const questionResult = ctx.userQuestions.ask({ agent, questions })
  await until(() => observer.frames.some(frame => frame.interaction?.kind === 'question'))
  const questionID = observer.frames.find(frame => frame.interaction?.kind === 'question').interaction.request_id
  assert.deepEqual(await command(relay.socketPath, { type: 'respond_interaction', observer_id: observer.observerID,
    session_id: session.id, request_id: questionID, ...answer }), { ok: true })
  assert.deepEqual(await questionResult, answer)
  assert.equal(nativeQuestions, 1)

  session.append('turn/start', { turn: 1 })
  const audit = []
  ctx.on('session/event', (_session, event) => {
    if (event.type.startsWith('approval/')) audit.push(event)
  })
  const approval = ctx.approval.request({ agent, toolName: 'synthetic-test-only', callId: 'synthetic-call' })
  assert.equal(audit[0].type, 'approval/asked')
  await until(() => observer.frames.some(frame => frame.interaction?.kind === 'approval'))
  const approvalID = observer.frames.find(frame => frame.interaction?.kind === 'approval').interaction.request_id
  assert.equal(audit.length, 1)
  assert.deepEqual(await command(relay.socketPath, { type: 'respond_interaction', observer_id: observer.observerID,
    session_id: session.id, request_id: approvalID, decision: 'allowed-once' }), { ok: true })
  assert.equal(await approval, 'allowed-once')
  assert.equal(audit[1].type, 'approval/decided')
  assert.equal(audit[1].data.id, audit[0].data.id)
  assert.equal(nativeApprovals, 0)
  session.append('approval/policy', { policy: 'never' })
  const count = observer.frames.filter(frame => frame.interaction?.status === 'pending').length
  assert.equal(await ctx.approval.request({ agent, toolName: 'synthetic-policy-test' }), 'rejected')
  await delay(10)
  assert.equal(observer.frames.filter(frame => frame.interaction?.status === 'pending').length, count)
  assert.equal(nativeApprovals, 0)

  // Execute the actual published plan tool, not a local imitation of its review.
  let planTool
  ctx.provide('tools', { register: tool => { planTool = tool } })
  ctx.provide('systemPrompt', { section() {}, context() {}, getSectionOrder: () => 0, getContextOrder: () => 0 })
  ctx.provide('sessionProjections', { register() {}, stateOf: () => ({ active: true }) })
  await ctx.plugin(PlanModeController, { section: 'Synthetic plan test guidance' }).inertia
  const markdown = '# Synthetic plan\n' + 'Full plan detail.\n'.repeat(20000)
  for (const approved of [true, false]) {
    const callId = approved ? 'plan-approve' : 'plan-feedback'
    const planResult = planTool.execute({ plan: markdown }, { agent, callId, signal: new AbortController().signal })
    // Attach rejection handling before exercising the explicit feedback response.
    const settled = planResult.then(value => ({ value }), error => ({ error }))
    await until(() => observer.frames.some(frame => frame.interaction?.call_id === callId))
    const frame = observer.frames.find(frame => frame.interaction?.call_id === callId)
    const review = frame.interaction.questions[0]
    assert.equal(frame.interaction.kind, 'plan')
    assert.equal(review.detail, markdown)
    assert.equal(review.intent.approve, 'Approve')
    assert.equal(review.intent.callId, callId)
    assert.deepEqual(await command(relay.socketPath, { type: 'respond_interaction', observer_id: observer.observerID,
      session_id: session.id, request_id: frame.interaction.request_id,
      answers: [{ id: review.id, selected: [approved ? review.intent.approve : 'Keep planning'],
        ...(approved ? {} : { custom: 'Synthetic feedback only' }) }],
    }), { ok: true })
    const outcome = await settled
    if (approved) assert.deepEqual(outcome.value, { approved: true })
    else assert.match(outcome.error.message, /Synthetic feedback only/)
  }

  // Timed waits retain their native claim and countdown protocol unchanged.
  assert.deepEqual(await ctx.userQuestions.ask({ agent, questions, wait: { callId: 'timed', timed: true } }), answer)
  assert.equal(nativeQuestions, 2)
  observer.socket.destroy()
  await delay(10)
  session.append('approval/policy', { policy: 'ask' })
  assert.equal(await ctx.approval.request({ agent, toolName: 'synthetic-fallback-test' }), 'rejected')
  assert.equal(nativeApprovals, 1)
})
