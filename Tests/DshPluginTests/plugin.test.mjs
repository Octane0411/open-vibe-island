import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { createServer } from 'node:net'
import { mkdtemp, rm, lstat, access } from 'node:fs/promises'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { setTimeout as delay } from 'node:timers/promises'
import test from 'node:test'
import * as plugin from '../../Sources/OpenIslandApp/Resources/open-island-dsh/open-island-dsh.js'

async function bridge(t, { pause = false } = {}) {
  const directory = await mkdtemp('/tmp/oi-dsh-')
  const path = join(directory, 'bridge.sock')
  const lines = []
  const sockets = new Set()
  const server = createServer(socket => {
    sockets.add(socket)
    socket.on('close', () => sockets.delete(socket))
    socket.on('error', () => {})
    socket.write('{"type":"hello","hello":{"protocolVersion":1,"serverLabel":"test"}}\n')
    let buffer = ''
    socket.on('data', chunk => {
      buffer += chunk.toString()
      const parts = buffer.split('\n')
      buffer = parts.pop()
      for (const part of parts) lines.push(JSON.parse(part))
    })
    if (pause) socket.pause()
  })
  await new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(path, resolve)
  })
  t.after(async () => {
    for (const socket of sockets) socket.destroy()
    await new Promise(resolve => server.close(resolve))
    await rm(directory, { recursive: true, force: true })
  })
  return { path, lines, server }
}

async function eventually(check) {
  const deadline = Date.now() + 2000
  while (!check()) {
    assert.ok(Date.now() < deadline, 'Expected socket observation before deadline')
    await delay(5)
  }
}

function state() {
  return { tools: new Map() }
}

function event(type, data) {
  return { type, seq: 1, time: 1_794_000_000_000, data }
}

test('normalizes DSH event data without leaking reasoning, injected context, or tool results', () => {
  const current = state()
  const normalize = (type, data) => plugin.normalizeEvent(current, event(type, data))
  assert.equal(normalize('user/message', {
    source: { kind: 'runtime-context' }, content: [{ type: 'text', text: 'private context' }],
  }), undefined)
  assert.deepEqual(normalize('user/message', {
    source: { kind: 'user' }, content: [{ type: 'text', text: 'Fix it\nplease' }, { type: 'image', url: 'private' }],
  }), { hook_event_name: 'UserPromptSubmit', prompt: 'Fix it\nplease' })
  assert.equal(normalize('request/header', { header: { config: { provider: 'deepseek', model: 'test' } } }), undefined)
  assert.equal(current.model, 'deepseek/test')
  assert.deepEqual(normalize('tool/call', { callId: 'a', name: 'bash', arguments: '{"command":"pwd"}' }), {
    hook_event_name: 'PreToolUse', tool_name: 'bash', tool_input: '{"command":"pwd"}',
  })
  normalize('tool/call', { callId: 'b', name: 'read', arguments: '{"file_path":"README.md"}' })
  assert.deepEqual(normalize('tool/result', { message: { toolCallId: 'a', content: [{ type: 'text', text: 'secret output' }] } }), {
    hook_event_name: 'PostToolUse', tool_name: 'bash',
  })
  assert.deepEqual(normalize('tool/result', { message: { toolCallId: 'b', isError: true } }), {
    hook_event_name: 'PostToolUse', tool_name: 'read',
  })
  normalize('assistant/message', { message: {
    source: { provider: 'gpt', model: 'test' },
    content: [{ type: 'reasoning', text: 'private reasoning' }, { type: 'text', text: 'Done' }],
  } })
  assert.deepEqual(normalize('turn/end', { turn: 1, reason: { kind: 'completed' } }), {
    hook_event_name: 'Stop', last_assistant_message: 'Done', turn_outcome: 'completed',
  })
  normalize('turn/start', { turn: 2 })
  assert.deepEqual(normalize('turn/end', { turn: 2, reason: { kind: 'aborted' } }), {
    hook_event_name: 'Stop', last_assistant_message: undefined, turn_outcome: 'aborted',
  })
  assert.equal(normalize('approval/asked', { toolName: 'bash' }), undefined)
  assert.equal(normalize('approval/policy', { policy: 'never' }), undefined)
  assert.equal(normalize('unknown/event', {}), undefined)
  assert.equal(plugin.normalizeEvent(current, null), undefined)
  assert.equal(normalize('tool/call', { arguments: {} }), undefined)
  assert.equal(normalize('tool/result', { message: null }), undefined)
  const longPrompt = normalize('user/message', { source: { kind: 'user' }, content: 'x'.repeat(100_000) })
  assert.equal(longPrompt.prompt.length, 4096)
})

test('sends ordered NDJSON to a real Unix socket and recovers when the app returns', async t => {
  const receiver = await bridge(t)
  const transport = plugin.createSocketTransport(receiver.path)
  t.after(() => transport.close())
  const payloads = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop', 'SessionEnd']
    .map(hook_event_name => ({ type: 'command', command: { type: 'processDshHook', dshHook: {
      hook_event_name, session_id: 'session-a', cwd: '/workspace', prompt: 'line one\nline two',
    } } }))
  assert.deepEqual(await Promise.all(payloads.map(value => transport.send(value))), payloads.map(() => true))
  await eventually(() => receiver.lines.length === payloads.length)
  assert.deepEqual(receiver.lines, payloads)
  const circular = {}
  circular.self = circular
  assert.equal(await transport.send(circular), false)
  assert.equal(await transport.send(undefined), false)

  const missingPath = join('/tmp', `oi-dsh-missing-${process.pid}.sock`)
  const unavailable = plugin.createSocketTransport(missingPath)
  t.after(() => unavailable.close())
  assert.equal(await unavailable.send(payloads[0]), false)
  await new Promise((resolve, reject) => {
    receiver.server.once('error', reject)
    receiver.server.close(() => receiver.server.listen(missingPath, resolve))
  })
  t.after(() => rm(missingPath, { force: true }))
  assert.equal(await unavailable.send(payloads[1]), true)
  await eventually(() => receiver.lines.length === payloads.length + 1)
  assert.deepEqual(receiver.lines.at(-1), payloads[1])
})

test('bounds transport backlog and closes pending work without surfacing failures', async t => {
  const receiver = await bridge(t)
  const transport = plugin.createSocketTransport(receiver.path, { maxPending: 1 })
  const first = transport.send({ sequence: 1 })
  assert.equal(await transport.send({ sequence: 2 }), false)
  await first
  transport.close()
  assert.equal(await transport.send({ sequence: 3 }), false)
  await transport.flush()
  const invalid = plugin.createSocketTransport({ invalid: true })
  assert.equal(await invalid.send({ sequence: 4 }), false)
  invalid.close()
  const stalled = await bridge(t, { pause: true })
  const deadline = plugin.createSocketTransport(stalled.path, { timeoutMs: 20 })
  t.after(() => deadline.close())
  // Exceed the Unix socket buffer so a peer that never reads cannot stall forever.
  assert.equal(await deadline.send({ content: 'x'.repeat(2_000_000) }), false)
  await deadline.flush()
})

async function installedRuntime() {
  try {
    const require = process.env.DSH_PACKAGE_ROOT
      ? createRequire(join(process.env.DSH_PACKAGE_ROOT, 'package.json')) : createRequire(import.meta.url)
    const { Context } = await import(pathToFileURL(require.resolve('@deepseek-ai/cordis')).href)
    const { default: SessionStore, Session } = await import(pathToFileURL(require.resolve('@deepseek-ai/dsh-session')).href)
    return { Context, SessionStore, Session }
  } catch (error) {
    if (process.env.DSH_PACKAGE_ROOT) throw error
    return undefined
  }
}

const runtime = await installedRuntime()

test('optional web services advertise only ready private endpoints and restrict RPC to the browser owner', {
  skip: !runtime && 'Set DSH_PACKAGE_ROOT for real Cordis coverage',
}, async t => {
  const { Context, SessionStore } = runtime
  const receiver = await bridge(t)
  const ctx = new Context()
  t.after(() => ctx.fiber.dispose())
  await ctx.plugin(SessionStore).inertia
  ctx.sessions.create('web-session', { meta: { cwd: '/workspace' } })
  const browserPeer = { principal: { kind: 'owner' } }
  let handler
  let unregistered = false
  ctx.provide('connection', {
    browserPeer,
    rpc: { handle: (_channel, callback) => {
      handler = callback
      return async () => { unregistered = true }
    } },
  })
  ctx.provide('webApp', { getAdvertisedUrl: () => 'http://127.0.0.1:3080/?ignored=not-a-credential' })
  const observer = ctx.plugin(plugin, { socketPath: receiver.path })
  await observer.inertia
  await eventually(() => receiver.lines.some(line => line.command.dshHook.web_focus_socket))
  const payload = receiver.lines.find(line => line.command.dshHook.web_focus_socket).command.dshHook
  assert.equal(payload.web_origin, 'http://127.0.0.1:3080/')
  assert.equal((await lstat(payload.web_focus_socket)).mode & 0o777, 0o600)
  const request = { client_id: 'pwa', standalone: true, focused: true, focus_epoch: 1 }
  const denied = await handler('poll', request, new AbortController().signal, { principal: { kind: 'api' } })
  assert.equal(denied.ok, false)
  assert.equal(denied.error.code, 'FORBIDDEN')
  const cancellation = new AbortController()
  const poll = handler('poll', request, cancellation.signal, browserPeer)
  cancellation.abort()
  assert.equal((await poll).ok, true)
  await observer.dispose()
  assert.equal(unregistered, true)
  await assert.rejects(access(payload.web_focus_socket), { code: 'ENOENT' })
})

test('observes real Cordis sessions independently and stops heartbeats at session and plugin disposal', {
  skip: !runtime && 'Set DSH_PACKAGE_ROOT to an installed DSH package directory for real API coverage',
}, async t => {
  const { Context, SessionStore, Session } = runtime
  const receiver = await bridge(t)
  const ctx = new Context()
  t.after(() => ctx.fiber.dispose())
  const storeFiber = ctx.plugin(SessionStore)
  await storeFiber.inertia
  const ownerA = ctx.plugin({ name: 'owner-a', inject: ['sessions'], apply() {} })
  await ownerA.inertia
  const a = ownerA.ctx.sessions.create('session-a', { meta: { cwd: '/workspace/a' } })
  // A detached stored or prepared session is never a liveness signal.
  Session.create('stored-not-loaded')
  const observer = ctx.plugin(plugin, { socketPath: receiver.path, heartbeatIntervalMs: 20 })
  await observer.inertia
  assert.equal(observer.state, 2)
  const ownerB = ctx.plugin({ name: 'owner-b', inject: ['sessions'], apply() {} })
  await ownerB.inertia
  const b = ownerB.ctx.sessions.create('session-b', { meta: { cwd: '/workspace/b' } })
  const append = (type, data, options) => a.append(type, data, ...(options ? [options] : []))
  append('turn/start', { turn: 1 })
  append('user/message', { id: 'user-1', role: 'user', source: { kind: 'user' }, content: [{ type: 'text', text: 'Please fix' }] }, { surfaceOp: 'append' })
  append('tool/call', { turn: 1, step: 1, callId: 'call-1', name: 'bash', arguments: '{"command":"pwd"}' })
  append('tool/result', { turn: 1, step: 1, message: {
    id: 'tool-1', role: 'tool', source: { kind: 'tool', callId: 'call-1' }, toolCallId: 'call-1', content: [{ type: 'text', text: 'ignored' }],
  } }, { surfaceOp: 'append' })
  append('assistant/message', { turn: 1, step: 1, message: {
    id: 'assistant-1', role: 'assistant', source: { kind: 'model', provider: 'deepseek', model: 'test' }, content: [{ type: 'text', text: 'Fixed' }],
  }, stream: [] }, { surfaceOp: 'append' })
  append('turn/end', { turn: 1, reason: { kind: 'completed' } })
  const hooks = () => receiver.lines.map(line => line.command.dshHook)
  await eventually(() => hooks().some(value => value.session_id === b.id && value.hook_event_name === 'Heartbeat'))
  assert.ok(hooks().every(value => value.session_id === a.id || value.session_id === b.id))
  const lifecycle = hooks().filter(value => value.session_id === a.id && value.hook_event_name !== 'Heartbeat')
  assert.deepEqual(lifecycle.map(value => value.hook_event_name), ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop'])
  assert.equal(lifecycle.at(-1).last_assistant_message, 'Fixed')
  assert.equal(lifecycle.at(-1).model, 'deepseek/test')
  assert.equal(lifecycle[0].cwd, '/workspace/a')
  assert.ok(receiver.lines.every(value => value.type === 'command' && value.command.type === 'processDshHook'))
  assert.ok(hooks().every(value => !('agent' in value) && !('terminal_tty' in value)))
  await ownerA.dispose()
  await eventually(() => hooks().some(value => value.session_id === a.id && value.hook_event_name === 'SessionEnd'))
  const countA = hooks().filter(value => value.session_id === a.id).length
  await delay(70)
  assert.equal(hooks().filter(value => value.session_id === a.id).length, countA)
  assert.ok(hooks().filter(value => value.session_id === b.id && value.hook_event_name === 'Heartbeat').length > 1)
  // Reusing an id must not revive the disposed Session object or duplicate starts.
  const replacement = ownerB.ctx.sessions.create(a.id, { meta: { cwd: '/workspace/replacement' } })
  await eventually(() => hooks().some(value => value.cwd === '/workspace/replacement'))
  await observer.dispose()
  await eventually(() => hooks().filter(value => value.hook_event_name === 'SessionEnd').length === 3)
  const count = receiver.lines.length
  b.append('turn/start', { turn: 1 })
  replacement.append('turn/start', { turn: 1 })
  await delay(70)
  assert.equal(receiver.lines.length, count)
  for (const invalidInterval of [0, -1, 1.5, 'abc', Number.MAX_SAFE_INTEGER, true]) {
    const from = receiver.lines.length
    const invalidObserver = ctx.plugin(plugin, { socketPath: receiver.path, heartbeatIntervalMs: invalidInterval })
    await invalidObserver.inertia
    await eventually(() => receiver.lines.length >= from + 2)
    await delay(25)
    assert.ok(hooks().slice(from).every(value => value.hook_event_name !== 'Heartbeat'))
    await invalidObserver.dispose()
    await eventually(() => receiver.lines.length >= from + 4)
  }
})
