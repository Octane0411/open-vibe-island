import assert from 'node:assert/strict'
import { connect } from 'node:net'
import { lstat, access, readFile, writeFile, unlink, rmdir } from 'node:fs/promises'
import { dirname } from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import { runInNewContext } from 'node:vm'
import test from 'node:test'
import { createFocusRelay } from '../../Sources/OpenIslandApp/Resources/open-island-dsh/open-island-dsh.js'

const signal = () => new AbortController().signal
const presence = (id, epoch = 1, focused = true) => ({ client_id: id, standalone: true, focused, focus_epoch: epoch })
async function until(check) {
  const deadline = Date.now() + 2000
  while (!check()) {
    assert.ok(Date.now() < deadline, 'Expected focus transition')
    await delay(5)
  }
}
function send(path, line, halfClose = false) {
  return new Promise((resolve, reject) => {
    const socket = connect(path, () => halfClose ? socket.end(line) : socket.write(line))
    let text = ''
    socket.on('error', reject)
    socket.on('data', chunk => {
      text += chunk
      if (text.includes('\n')) {
        resolve(JSON.parse(text.trim()))
        socket.destroy()
      }
    })
  })
}

test('private Unix relay selects one recent PWA, supersedes stale clicks, and rejects stale acknowledgements', async t => {
  const live = new Set(['alpha', 'beta', '中文'])
  const relay = await createFocusRelay({ hasSession: id => live.has(id), timeoutMs: 500, pollMs: 30 })
  t.after(() => relay.close())
  const stat = await lstat(relay.socketPath)
  assert.equal(stat.mode & 0o777, 0o600)
  assert.equal(stat.uid, process.getuid())
  assert.ok(stat.isSocket())
  assert.match(relay.socketPath, /^\/tmp\/oi-dsh-focus-[a-f0-9]+\/focus\.sock$/)
  const parent = await lstat(dirname(relay.socketPath))
  assert.ok(parent.isDirectory())
  assert.equal(parent.uid, process.getuid())
  assert.equal(parent.mode & 0o777, 0o700)

  await relay.rpc('poll', presence('older'), signal())
  await relay.rpc('poll', presence('recent'), signal())
  const oldPoll = relay.rpc('poll', presence('older'), signal())
  const newPoll = relay.rpc('poll', presence('recent'), signal())
  const first = send(relay.socketPath, '{"session_id":"alpha"}\n', true)
  const commandA = (await newPoll).command
  assert.equal(commandA.session_id, 'alpha')
  assert.equal((await oldPoll).command, null)
  assert.deepEqual(await relay.rpc('ack', { client_id: 'older', request_id: commandA.request_id, ok: true }, signal()), { ok: false, error: 'superseded' })

  const nextPoll = relay.rpc('poll', presence('recent'), signal())
  const second = send(relay.socketPath, '{"session_id":"beta"}\n')
  const commandB = (await nextPoll).command
  assert.deepEqual(await first, { ok: false, error: 'superseded' })
  assert.equal(commandB.session_id, 'beta')
  assert.deepEqual(await relay.rpc('ack', { client_id: 'recent', request_id: commandA.request_id, ok: true }, signal()), { ok: false, error: 'superseded' })
  live.delete('beta')
  await relay.rpc('ack', { client_id: 'recent', request_id: commandB.request_id, ok: true }, signal())
  assert.deepEqual(await second, { ok: false, error: 'not-found' })

  const unicodePoll = relay.rpc('poll', presence('recent'), signal())
  const unicode = send(relay.socketPath, '{"session_id":"中文"}\n')
  const commandC = (await unicodePoll).command
  await relay.rpc('ack', { client_id: 'recent', request_id: commandC.request_id, ok: true }, signal())
  assert.deepEqual(await unicode, { ok: true })
  const refocusedPoll = relay.rpc('poll', presence('older', 2), signal())
  const refocused = send(relay.socketPath, '{"session_id":"alpha"}\n')
  const commandD = (await refocusedPoll).command
  assert.equal(commandD.session_id, 'alpha')
  await relay.rpc('ack', { client_id: 'older', request_id: commandD.request_id, ok: true }, signal())
  assert.deepEqual(await refocused, { ok: true })
  await relay.close()
  await assert.rejects(access(relay.socketPath), { code: 'ENOENT' })
})

test('relay bounds malformed input, cold registration, timeouts, and teardown', async t => {
  const relay = await createFocusRelay({ hasSession: id => id === 'live', timeoutMs: 150, pollMs: 20 })
  t.after(() => relay.close())
  for (const line of ['null\n', '{"session_id":""}\n', '{"session_id":"live","eval":"no"}\n', '{}\n{}\n', 'x'.repeat(8193)]) {
    assert.deepEqual(await send(relay.socketPath, line), { ok: false, error: 'invalid-request' })
  }
  assert.deepEqual(await send(relay.socketPath, '{"session_id":"missing"}\n'), { ok: false, error: 'not-found' })
  assert.deepEqual(await send(relay.socketPath, '{"session_id":"live"}\n'), { ok: false, error: 'no-client' })
  const cold = send(relay.socketPath, '{"session_id":"live"}\n')
  await delay(10)
  assert.deepEqual(await relay.rpc('poll', { ...presence('tab'), standalone: false }, signal()), { ok: false, error: 'invalid-request' })
  const command = (await relay.rpc('poll', presence('cold-pwa'), signal())).command
  assert.equal(command.session_id, 'live')
  assert.deepEqual(await cold, { ok: false, error: 'timeout' })
  const poll = relay.rpc('poll', presence('cold-pwa'), signal())
  await relay.close()
  assert.equal((await poll).command, null)
  assert.deepEqual(await relay.rpc('poll', presence('cold-pwa'), signal()), { ok: false, error: 'disposed' })
})

test('connection and client registries reject overload without retaining unbounded work', async t => {
  const relay = await createFocusRelay({ hasSession: () => true, timeoutMs: 500 })
  t.after(() => relay.close())
  const sockets = await Promise.all(Array.from({ length: 16 }, () => new Promise((resolve, reject) => {
    const socket = connect(relay.socketPath, () => resolve(socket))
    socket.on('error', reject)
  })))
  t.after(() => sockets.forEach(socket => socket.destroy()))
  assert.deepEqual(await send(relay.socketPath, '{"session_id":"live"}\n'), { ok: false, error: 'busy' })
  const controller = new AbortController()
  const polls = Array.from({ length: 16 }, (_, index) => relay.rpc('poll', presence(`pwa-${index}`), controller.signal))
  assert.deepEqual(await relay.rpc('poll', presence('overflow'), signal()), { ok: false, error: 'busy' })
  controller.abort()
  assert.ok((await Promise.all(polls)).every(result => result.command === null))
  await relay.rpc('leave', { client_id: 'pwa-0' }, signal())
  const replacement = relay.rpc('poll', presence('replacement'), signal())
  await relay.close()
  assert.equal((await replacement).command, null)
})

test('teardown does not recursively remove unrelated files from its private directory', async () => {
  const relay = await createFocusRelay({ hasSession: () => true })
  const directory = dirname(relay.socketPath)
  assert.match(directory, /^\/tmp\/oi-dsh-focus-[a-f0-9]+$/)
  const marker = directory + '/unrelated.txt'
  await writeFile(marker, 'unrelated owner file', { flag: 'wx' })
  try {
    await relay.close()
    assert.equal(await readFile(marker, 'utf8'), 'unrelated owner file')
    await assert.rejects(access(relay.socketPath), { code: 'ENOENT' })
  } finally {
    // Absolute targets were verified above and created by this test.
    await unlink(marker)
    await rmdir(directory)
  }
})

// The public APIs are exercised by the client, with a delayed editor mount and
// independent mainView retention. No private DSH fields are patched by the test.
async function browser(t, { mode = 'fullscreen', mini = false } = {}) {
  const source = await readFile(new URL('../../Sources/OpenIslandApp/Resources/open-island-dsh/open-island-dsh-client.js', import.meta.url), 'utf8')
  const windowEvents = new EventTarget()
  const documentEvents = new EventTarget()
  let module
  let selected
  let mounted
  let waiting
  const ack = []
  const opened = []
  const document = Object.assign(documentEvents, {
    visibilityState: 'visible', hasFocus: () => true, activeElement: undefined,
  })
  const window = Object.assign(windowEvents, {
    dshMiniWindow: mini ? { version: 1 } : undefined,
    matchMedia: query => ({ matches: query === `(display-mode: ${mode})` }),
    __ModuleLoader__: { load: value => { module = value } },
  })
  let cleanup
  const ctx = {
    effect: callback => { cleanup = callback() },
    connection: { rpc: { call: async (_channel, endpoint, payload, abort) => {
      if (endpoint === 'ack') {
        ack.push(payload)
        return { ok: true, value: { ok: true } }
      }
      if (endpoint === 'leave') return { ok: true, value: { ok: true } }
      return new Promise((resolve, reject) => {
        waiting = { resolve: command => resolve({ ok: true, value: { ok: true, command } }), payload }
        abort.addEventListener('abort', () => reject(new Error('aborted')), { once: true })
      })
    } } },
    uiWorkspace: { openSession: id => {
      selected = id
      opened.push(id)
    } },
    sessions: {
      retainInfo: id => ({ getSnapshot: () => ({ retainedBy: { mainView: selected === id ? 1 : 0 } }) }),
      scope: id => ({ id }),
    },
    conversation: { input: { for: scope => ({ focus: () => {
      if (mounted === scope.id) document.activeElement = { isContentEditable: true, blur: () => { document.activeElement = undefined } }
    } }) } },
  }
  runInNewContext(source, {
    window, document, location: { hash: '' }, crypto: { randomUUID: () => 'test-client' },
    AbortController, AbortSignal, setTimeout, clearTimeout,
    requestAnimationFrame: callback => setTimeout(callback, 2), cancelAnimationFrame: clearTimeout,
  })
  assert.equal(module.id, 'open-island-dsh')
  module.factory().apply(ctx)
  t.after(() => cleanup())
  return {
    ack, opened, waiting: () => waiting,
    mount: id => { mounted = id },
    select: id => { selected = id },
    command: (id, requestId) => {
      const poll = waiting
      waiting = undefined
      poll.resolve({ session_id: id, request_id: requestId, expires_at: Date.now() + 2000 })
    },
  }
}

test('client lazily opens the exact chat, waits for mounted composer, and focuses only latest selection', async t => {
  const client = await browser(t)
  await until(() => client.waiting())
  client.command('alpha', 'a')
  await until(() => client.opened.length === 1 && client.waiting())
  assert.equal(client.ack.length, 0)
  client.command('beta', 'b')
  await until(() => client.opened.length === 2)
  client.mount('alpha')
  await delay(30)
  assert.equal(client.ack.length, 0)
  client.mount('beta')
  await until(() => client.ack.length > 0)
  assert.deepEqual(client.opened, ['alpha', 'beta'])
  assert.equal(client.ack.length, 1)
  assert.equal(client.ack[0].request_id, 'b')
  assert.equal(client.ack[0].ok, true)
  await until(() => client.waiting())
  client.command('alpha', 'c')
  await until(() => client.opened.length === 3)
  client.select('user-selected-other-chat')
  await until(() => client.ack.length === 2)
  assert.equal(client.ack[1].ok, false)
})

test('ordinary tabs and mini windows never register as standalone focus targets', async t => {
  const tab = await browser(t, { mode: 'browser' })
  const mini = await browser(t, { mini: true })
  await delay(20)
  assert.equal(tab.waiting(), undefined)
  assert.equal(mini.waiting(), undefined)
})
