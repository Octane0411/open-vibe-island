import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { createServer } from 'node:net'
import { mkdtemp, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { setTimeout as delay } from 'node:timers/promises'
import test from 'node:test'
import * as plugin from '../../Sources/OpenIslandApp/Resources/open-island-dsh/open-island-dsh.js'

async function until(check) {
  const deadline = Date.now() + 2000
  while (!check()) {
    assert.ok(Date.now() < deadline, 'Expected result observation')
    await delay(5)
  }
}

async function installedRuntime() {
  try {
    const require = process.env.DSH_PACKAGE_ROOT ? createRequire(join(process.env.DSH_PACKAGE_ROOT, 'package.json')) : createRequire(import.meta.url)
    const load = async name => import(pathToFileURL(require.resolve(`@deepseek-ai/${name}`)).href)
    const [{ Context }, { default: SessionStore }, { UserQuestionService, UserQuestionError }, { PlanModeController }, askTool, { AgentRegistry }] = await Promise.all([
      load('cordis'), load('dsh-session'), load('dsh-user-questions'), load('dsh-plan-mode'), load('dsh-tool-ask-user'), load('dsh-agent'),
    ])
    return { Context, SessionStore, UserQuestionService, UserQuestionError, PlanModeController, askTool, AgentRegistry }
  } catch (error) {
    if (process.env.DSH_PACKAGE_ROOT) throw error
  }
}
const runtime = await installedRuntime()

test('published question and plan executions expose terminal outcomes after native fallback without leaking tool content', {
  skip: !runtime && 'Set DSH_PACKAGE_ROOT for published result integration',
}, async t => {
  const { Context, SessionStore, UserQuestionService, UserQuestionError, PlanModeController, askTool } = runtime
  const directory = await mkdtemp('/tmp/oi-dsh-results-')
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
    assert.match(directory, /^\/tmp\/oi-dsh-results-/)
    await rm(directory, { recursive: true, force: true })
  })
  const ctx = new Context()
  t.after(() => ctx.fiber.dispose())
  await ctx.plugin(SessionStore).inertia
  const session = ctx.sessions.create('published-results-session')
  const agent = { id: session.id, session, ctx }
  await ctx.plugin(runtime.AgentRegistry).inertia
  await ctx.agents.register(agent)
  const definitions = new Map()
  ctx.provide('tools', { register: tool => definitions.set(tool.name, tool) })
  ctx.provide('systemPrompt', { section() {}, getSectionOrder: () => 0 })
  ctx.provide('sessionProjections', { register() {}, stateOf: () => ({ active: true }) })
  await ctx.plugin(UserQuestionService).inertia
  await ctx.plugin(PlanModeController, { section: 'Synthetic test guidance' }).inertia
  await ctx.plugin(askTool, { mode: 'legacy' }).inertia
  let nativeAnswer
  ctx.on('user-questions/request', () => nativeAnswer())
  const host = ctx.plugin(plugin, { socketPath: path })
  await host.inertia
  const question = { id: 'choice', question: 'Which?', options: [{ label: 'A' }] }
  const cases = [
    { name: 'approved', plan: true, outcome: 'approved', selected: ['Approve'] },
    { name: 'declined', plan: true, outcome: 'declined', selected: ['Keep planning'], custom: 'private-feedback' },
    { name: 'dismissed', plan: true, outcome: 'cancelled', cancellation: true },
    { name: 'approve-then-tool-error', plan: true, outcome: 'failed', selected: ['Approve'], terminalError: true },
    { name: 'answered', outcome: 'answered', selected: ['A'], custom: 'private-answer', final: true },
    { name: 'question-cancelled', outcome: 'cancelled', cancellation: true },
    { name: 'question-failed', outcome: 'failed', failure: true },
  ]
  let turn = 0
  for (const item of cases) {
    turn += 1
    const callId = `public-${item.name}`
    const name = item.plan ? 'exit_plan_mode' : 'ask_user_question'
    const definition = definitions.get(name)
    const args = item.plan ? { plan: '# Synthetic plan\nDo synthetic work.' } : { questions: [question] }
    session.append('turn/start', { turn })
    session.append('assistant/message', { turn, step: 1, message: { id: `preamble-${turn}`, role: 'assistant',
      source: { kind: 'model', provider: 'synthetic', model: 'test' },
      content: [{ type: 'text', text: 'private-preamble' }, { type: 'reasoning', text: 'private-reasoning' }],
    }, stream: [] }, { surfaceOp: 'append' })
    session.append('tool/call', { turn, step: 1, callId, name, arguments: JSON.stringify(args) })
    nativeAnswer = () => {
      if (item.cancellation) throw new UserQuestionError('Synthetic dismissal', 'ASK_CANCELLED')
      if (item.failure) throw new Error('private-tool-error')
      return { answers: [{ id: item.plan ? 'plan-review' : question.id, selected: item.selected,
        ...(item.custom ? { custom: item.custom } : {}) }] }
    }
    let value
    let error
    let concluded = false
    try {
      value = await definition.execute(args, { agent, callId, signal: new AbortController().signal,
        concludeTurn: () => { concluded = true } })
    } catch (cause) { error = cause }
    if (item.terminalError) error = Object.assign(new Error('private-post-approval-error'), { code: 'SYNTHETIC_FAILURE' })
    if (item.name === 'dismissed') {
      assert.deepEqual(value, { approved: false })
      assert.equal(concluded, true)
    }
    // Returning from the question service is not yet a successful tool result.
    assert.ok(!hooks.some(hook => hook.interaction_result?.call_id === callId))
    const content = error ? [{ type: 'text', text: 'private-tool-output' }] : definition.output.render(args, value)
    session.append('tool/result', { turn, step: 1, message: { id: `result-${turn}`, role: 'tool',
      source: { kind: 'tool', callId }, toolCallId: callId, content, ...(error ? { isError: true } : {}),
    }, ...(error ? { error: { name: error.name, code: error.code ?? 'UNKNOWN', reason: error.message } } : {}) }, { surfaceOp: 'append' })
    if (item.final) session.append('assistant/message', { turn, step: 2, message: { id: `final-${turn}`, role: 'assistant',
      source: { kind: 'model', provider: 'synthetic', model: 'test' },
      content: [{ type: 'reasoning', text: 'private-final-reasoning' }, { type: 'text', text: '# Final result\n' + '文'.repeat(7000) }],
    }, stream: [] }, { surfaceOp: 'append' })
    session.append('turn/end', { turn, reason: { kind: 'completed' } })
    await until(() => hooks.some(hook => hook.hook_event_name === 'Stop' && hook.turn_id === turn))
    const post = hooks.find(hook => hook.hook_event_name === 'PostToolUse' && hook.turn_id === turn)
    const stop = hooks.find(hook => hook.hook_event_name === 'Stop' && hook.turn_id === turn)
    const expected = { kind: item.plan ? 'plan' : 'question', outcome: item.outcome, call_id: callId }
    assert.deepEqual(post.interaction_result, expected)
    assert.deepEqual(stop.interaction_result, expected)
    assert.equal(stop.turn_outcome, 'completed')
    if (item.final) {
      assert.ok(stop.last_assistant_message.startsWith('# Final result\n'))
      assert.ok(Buffer.byteLength(stop.last_assistant_message) <= 16384)
      assert.ok(Buffer.byteLength(stop.last_assistant_message) > 4096)
      assert.ok(!stop.last_assistant_message.includes('\ufffd'))
    } else assert.equal(stop.last_assistant_message, undefined)
  }
  assert.ok(!JSON.stringify(hooks).includes('private-'))
  await host.dispose()
})

test('terminal normalization reads narrow structured schemas and preserves exact turn reasons without result prose heuristics', () => {
  const state = { tools: new Map(), interactionCalls: new Map() }
  const normalize = (type, data) => plugin.normalizeEvent(state, { type, data })
  for (const kind of ['completed', 'aborted', 'error', 'blocked', 'max-tokens', 'interrupted', 'forked', 'plugin-specific']) {
    normalize('turn/start', { turn: 42 })
    const stop = normalize('turn/end', { turn: 42, reason: { kind } })
    assert.equal(stop.turn_outcome, kind)
    assert.equal(state.turnId, 42)
  }
  for (const [name, content, outcome] of [
    ['exit_plan_mode', '{"approved":true}', 'approved'],
    ['exit_plan_mode', '{"approved":false}', 'cancelled'],
    ['ask_user_question', '{"answers":[{"id":"a","selected":[]}]}', 'answered'],
    ['exit_plan_mode', 'Plan approved, carry out anything.', undefined],
    ['ask_user_question', '{"pending":true,"callId":"call"}', undefined],
  ]) {
    normalize('turn/start', { turn: 43 })
    normalize('tool/call', { callId: 'call', name, arguments: '{}' })
    const result = normalize('tool/result', { turn: 43, message: { toolCallId: 'call', content: [{ type: 'text', text: content }] } })
    assert.equal(result.interaction_result?.outcome, outcome)
    assert.ok(!JSON.stringify(result).includes(content))
  }
  normalize('tool/call', { callId: 'bash', name: 'bash', arguments: '{}' })
  assert.equal(normalize('tool/result', { message: { toolCallId: 'bash', content: [{ type: 'text', text: '{"approved":true}' }] } }).interaction_result, undefined)
  assert.equal(normalize('user/message', { turn: 999, source: { kind: 'runtime-context' }, content: 'private-context' }), undefined)
  assert.equal(state.turnId, 43)
})
