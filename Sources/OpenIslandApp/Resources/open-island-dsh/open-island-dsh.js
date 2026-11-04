// Lifecycle observer and narrow conversation focus relay. No tool or approval controls.
import { connect, createServer } from 'node:net'
import { randomBytes } from 'node:crypto'
import { chmod, lstat, mkdir, rmdir } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const name = 'open-island-dsh'
export const inject = ['sessions']

const DEFAULT_HEARTBEAT_MS = 15_000
const MAX_PREVIEW = 4096

function preview(value) {
  return typeof value === 'string' && value.trim() ? value.slice(0, MAX_PREVIEW) : undefined
}

function textContent(content) {
  if (typeof content === 'string') return preview(content)
  if (!Array.isArray(content)) return undefined
  return preview(content.filter(part => part?.type === 'text' && typeof part.text === 'string')
    .map(part => part.text).join('\n'))
}

function validInterval(value) {
  if (typeof value !== 'number' && typeof value !== 'string') return DEFAULT_HEARTBEAT_MS
  const number = Number(value)
  return Number.isSafeInteger(number) && number > 0 && number <= 2_147_483_647
    ? number : DEFAULT_HEARTBEAT_MS
}

function modelName(config) {
  return [config?.provider, config?.model].filter(value => typeof value === 'string' && value).join('/') || undefined
}

// SessionEvent data shapes come from @deepseek-ai/dsh-session 0.2.1-rc.3.
// This fold never replays stored events or interprets injected context as a prompt.
export function normalizeEvent(state, event) {
  const data = event?.data
  if (!data || typeof data !== 'object') return undefined
  switch (event.type) {
    case 'turn/start':
      state.lastAssistantMessage = undefined
      return undefined
    case 'request/header':
      state.model = modelName(data.header?.config) || state.model
      return undefined
    case 'request/context':
      state.model = modelName(data) || state.model
      return undefined
    case 'user/message':
      if (data.source?.kind !== 'user') return undefined
      return { hook_event_name: 'UserPromptSubmit', prompt: textContent(data.content) }
    case 'tool/call':
      if (typeof data.callId !== 'string' || typeof data.name !== 'string') return undefined
      state.tools.set(data.callId, data.name)
      return {
        hook_event_name: 'PreToolUse',
        tool_name: preview(data.name),
        tool_input: preview(data.arguments),
      }
    case 'tool/result': {
      const callId = data.message?.toolCallId
      if (typeof callId !== 'string') return undefined
      const toolName = state.tools.get(callId)
      state.tools.delete(callId)
      return { hook_event_name: 'PostToolUse', tool_name: preview(toolName) }
    }
    case 'assistant/message':
      state.lastAssistantMessage = textContent(data.message?.content) || state.lastAssistantMessage
      state.model = modelName(data.message?.source) || state.model
      return undefined
    case 'turn/end':
      state.tools.clear()
      return { hook_event_name: 'Stop', last_assistant_message: state.lastAssistantMessage }
    default:
      return undefined
  }
}

// One bounded FIFO preserves lifecycle order. Sending never awaits an app reply.
// Down sockets, serialization errors, and overload drop observations, not agent work.
export function createSocketTransport(socketPath, { timeoutMs = 500, maxPending = 64 } = {}) {
  const queue = []
  let active
  let closed = false
  const drainers = new Set()

  function drained() {
    if (active || queue.length) return
    for (const resolve of drainers) resolve()
    drainers.clear()
  }

  function pump() {
    if (active || closed) return
    const item = queue.shift()
    if (!item) return drained()
    let socket
    let timer
    let settled = false
    let written = false
    function finish(sent) {
      if (settled) return
      settled = true
      clearTimeout(timer)
      socket?.destroy()
      active = undefined
      item.resolve(sent)
      pump()
      drained()
    }
    active = { cancel: () => finish(false) }
    try {
      timer = setTimeout(() => finish(false), timeoutMs)
      timer.unref()
      socket = connect({ path: socketPath }, () => {
        // Keep the read half open until the bridge closes it. Destroying here
        // can make its initial greeting fail before it reads our command.
        socket.end(item.line, () => { written = true })
      })
      socket.unref()
      socket.once('error', () => finish(false))
      socket.once('end', () => finish(written))
      socket.once('close', () => finish(written))
      // The Swift bridge greets new clients. Replies are deliberately ignored.
      socket.on('data', () => {})
    } catch {
      finish(false)
    }
  }

  return {
    send(envelope) {
      if (closed || queue.length + Number(Boolean(active)) >= maxPending) return Promise.resolve(false)
      let line
      try {
        const encoded = JSON.stringify(envelope)
        if (typeof encoded !== 'string') return Promise.resolve(false)
        line = encoded + '\n'
      } catch {
        return Promise.resolve(false)
      }
      return new Promise(resolve => {
        queue.push({ line, resolve })
        pump()
      })
    },
    flush() {
      if (!active && !queue.length) return Promise.resolve()
      return new Promise(resolve => drainers.add(resolve))
    },
    close() {
      closed = true
      for (const item of queue.splice(0)) item.resolve(false)
      active?.cancel()
      drained()
    },
  }
}

const FOCUS_CHANNEL = '/open-island-dsh'
const failure = error => ({ ok: false, error })
const validId = value => typeof value === 'string' && value.length > 0
  && value.length <= 512 && !/[\u0000-\u001f\u007f]/.test(value)

// The only local command is selection + composer focus. Each host owns one random
// endpoint, and each request replaces older work rather than replaying stale clicks.
export async function createFocusRelay({ hasSession, timeoutMs = 5800, pollMs = 1000 } = {}) {
  const directory = `/tmp/oi-dsh-focus-${randomBytes(12).toString('hex')}`
  await mkdir(directory, { mode: 0o700 })
  const ownedDirectory = await lstat(directory)
  if (!ownedDirectory.isDirectory() || ownedDirectory.uid !== process.getuid()
    || (ownedDirectory.mode & 0o077) !== 0) throw new Error('unsafe focus directory')
  const socketPath = directory + '/focus.sock'
  async function removeOwnDirectory() {
    const current = await lstat(directory).catch(() => undefined)
    if (current?.isDirectory() && current.dev === ownedDirectory.dev && current.ino === ownedDirectory.ino) {
      // rmdir never follows links or removes contents left by somebody else.
      await rmdir(directory).catch(() => {})
    }
  }
  const clients = new Map()
  const sockets = new Set()
  let pending
  let disposed = false
  let focusSequence = 0

  function finish(result) {
    if (!pending) return
    const request = pending
    pending = undefined
    clearTimeout(request.timer)
    request.resolve(result)
  }

  function dispatch() {
    if (!pending || pending.clientId) return
    if (!hasSession(pending.sessionId)) return finish(failure('not-found'))
    const now = Date.now()
    for (const [id, client] of clients) {
      if (now - client.seen > 3500) {
        client.poll?.(null)
        clients.delete(id)
      }
    }
    const chosen = [...clients.values()].filter(client => client.focus > 0)
      .sort((a, b) => b.focus - a.focus)[0]
    if (!chosen?.poll) return
    pending.clientId = chosen.id
    chosen.poll({ request_id: pending.id, session_id: pending.sessionId, expires_at: pending.expiresAt })
  }

  function request(sessionId, budget) {
    if (disposed) return Promise.resolve(failure('disposed'))
    if (!hasSession(sessionId)) return Promise.resolve(failure('not-found'))
    finish(failure('superseded'))
    return new Promise(resolve => {
      pending = { id: randomBytes(16).toString('hex'), sessionId, resolve,
        expiresAt: Date.now() + budget }
      pending.timer = setTimeout(() => finish(failure(!hasSession(sessionId) ? 'not-found'
        : pending?.clientId ? 'timeout' : 'no-client')), budget)
      pending.timer.unref()
      dispatch()
    })
  }

  async function rpc(endpoint, body, signal) {
    if (disposed) return failure('disposed')
    if (!body || !validId(body.client_id)) return failure('invalid-request')
    if (endpoint === 'ack') {
      if (!pending || pending.clientId !== body.client_id || pending.id !== body.request_id) return failure('superseded')
      const result = !hasSession(pending.sessionId) ? failure('not-found')
        : body.ok === true ? { ok: true } : failure('focus-failed')
      finish(result)
      return { ok: true }
    }
    if (endpoint === 'leave') {
      clients.get(body.client_id)?.poll?.(null)
      clients.delete(body.client_id)
      return { ok: true }
    }
    if (endpoint !== 'poll' || body.standalone !== true || typeof body.focused !== 'boolean'
      || !Number.isSafeInteger(body.focus_epoch) || body.focus_epoch < 0) return failure('invalid-request')
    if (signal.aborted) return failure('disposed')
    let client = clients.get(body.client_id)
    if (!client) {
      if (clients.size >= 16) {
        for (const [id, stale] of clients) {
          if (Date.now() - stale.seen > 3500) {
            stale.poll?.(null)
            clients.delete(id)
          }
        }
        if (clients.size >= 16) return failure('busy')
      }
      client = { id: body.client_id, focus: 0, epoch: -1 }
      clients.set(client.id, client)
    }
    client.seen = Date.now()
    if (body.focused && body.focus_epoch !== client.epoch) client.focus = ++focusSequence
    client.epoch = body.focus_epoch
    client.poll?.(null)
    return new Promise(resolve => {
      let timer
      const done = command => {
        clearTimeout(timer)
        signal.removeEventListener('abort', abort)
        if (client.poll === done) client.poll = undefined
        resolve({ ok: true, command })
      }
      const abort = () => done(null)
      client.poll = done
      signal.addEventListener('abort', abort, { once: true })
      timer = setTimeout(() => done(null), pollMs)
      timer.unref()
      dispatch()
    })
  }

  const server = createServer({ allowHalfOpen: true }, socket => {
    socket.unref()
    socket.on('error', () => {})
    if (disposed || sockets.size >= 16) {
      socket.end(JSON.stringify(failure('busy')) + '\n', () => socket.destroy())
      return
    }
    sockets.add(socket)
    socket.setEncoding('utf8')
    const deadline = Date.now() + timeoutMs
    let bytes = 0
    let buffer = ''
    let accepted = false
    const reply = result => {
      if (!socket.destroyed && !socket.writableEnded) {
        socket.end(JSON.stringify(result) + '\n', () => socket.destroy())
      }
    }
    const timer = setTimeout(() => {
      reply(failure('timeout'))
      socket.destroySoon()
    }, timeoutMs)
    timer.unref()
    socket.once('close', () => {
      clearTimeout(timer)
      sockets.delete(socket)
    })
    socket.on('data', chunk => {
      if (accepted) return
      bytes += Buffer.byteLength(chunk)
      if (bytes > 8192) {
        accepted = true
        return reply(failure('invalid-request'))
      }
      buffer += chunk.toString('utf8')
      if (!buffer.includes('\n')) return
      accepted = true
      let body
      try { body = JSON.parse(buffer.trim()) } catch { return reply(failure('invalid-request')) }
      if (!body || !validId(body.session_id) || Object.keys(body).length !== 1) return reply(failure('invalid-request'))
      void request(body.session_id, Math.max(1, deadline - Date.now() - 20)).then(reply)
    })
  })
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject)
      server.listen(socketPath, resolve)
    })
    await chmod(socketPath, 0o600)
    const stat = await lstat(socketPath)
    if (!stat.isSocket() || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0) throw new Error('unsafe focus socket')
    server.unref()
  } catch (error) {
    await new Promise(resolve => server.close(resolve))
    await removeOwnDirectory()
    throw error
  }
  return {
    socketPath, rpc,
    async close() {
      if (disposed) return
      disposed = true
      finish(failure('disposed'))
      for (const client of clients.values()) client.poll?.(null)
      clients.clear()
      for (const socket of sockets) {
        if (socket.writableEnded) socket.destroy()
        else socket.end(JSON.stringify(failure('disposed')) + '\n', () => socket.destroy())
      }
      // Node unlinks the bound path on close. Its random private parent prevents
      // replacement by other users. Never scan paths or recursively delete.
      await new Promise(resolve => server.close(resolve))
      await removeOwnDirectory()
    },
  }
}

export function apply(ctx, config = {}) {
  const store = ctx.sessions
  const socketPath = config.socketPath || process.env.OPEN_ISLAND_SOCKET_PATH
    || process.env.VIBE_ISLAND_SOCKET_PATH
    || join(process.env.HOME || homedir(), 'Library/Application Support/OpenIsland/bridge.sock')
  const heartbeatMs = validInterval(config.heartbeatIntervalMs ?? process.env.OPEN_ISLAND_HEARTBEAT_INTERVAL_MS)
  const transport = createSocketTransport(socketPath)
  const sessions = new Map()
  let disposed = false
  let webMetadata = {}

  // Web services are optional. The sessions-only CLI observer keeps working.
  ctx.inject(['connection', 'webApp'], webCtx => {
    webCtx.effect(() => {
      let cancelled = false
      let relay
      let unregister
      const ready = createFocusRelay({
        hasSession: id => !disposed && store.get(id) !== undefined
          && sessions.has(store.get(id)),
      }).then(async value => {
        relay = value
        if (cancelled) return
        const connection = webCtx.connection
        unregister = connection.rpc.handle(FOCUS_CHANNEL, async (endpoint, payload, signal, peer) => {
          if (peer !== connection.browserPeer) return { ok: false, error: { code: 'FORBIDDEN', message: 'Owner browser required', details: {} } }
          return { ok: true, value: await relay.rpc(endpoint, payload, signal) }
        })
        const url = new URL(webCtx.webApp.getAdvertisedUrl())
        const local = ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)
        if (url.protocol !== 'http:' || !local || url.username || url.password) return
        webMetadata = { web_origin: url.origin + '/', web_focus_socket: relay.socketPath }
        for (const [session, state] of sessions) send(session, state, { hook_event_name: 'Heartbeat' })
      }).catch(() => {}) // Focus is optional and must never break lifecycle observation.
      return async () => {
        cancelled = true
        webMetadata = {}
        await ready
        try { await unregister?.() } finally { await relay?.close() }
      }
    }, 'open-island-dsh: private focus relay')
  })

  function send(session, state, lifecycle) {
    const payload = {
      session_id: session.id,
      cwd: session.header?.cwd || process.cwd(),
      model: state.model,
      ...webMetadata,
      ...lifecycle,
    }
    void transport.send({ type: 'command', command: { type: 'processDshHook', dshHook: payload } })
  }

  function end(session) {
    const state = sessions.get(session)
    if (!state) return
    clearInterval(state.timer)
    sessions.delete(session)
    send(session, state, { hook_event_name: 'SessionEnd' })
  }

  function start(session) {
    if (disposed || sessions.has(session) || store.get(session.id) !== session) return
    const state = { tools: new Map(), model: modelName(session.requestHeader?.()?.config) }
    sessions.set(session, state)
    send(session, state, { hook_event_name: 'SessionStart' })
    state.timer = setInterval(() => {
      if (store.get(session.id) !== session) return end(session)
      send(session, state, { hook_event_name: 'Heartbeat' })
    }, heartbeatMs)
    state.timer.unref()
  }

  ctx.on('session/created', start)
  ctx.on('session/disposed', end)
  ctx.on('session/event', (session, event) => {
    if (disposed || store.get(session.id) !== session) return
    start(session)
    const state = sessions.get(session)
    if (!state) return
    const lifecycle = normalizeEvent(state, event)
    if (lifecycle) send(session, state, lifecycle)
  })
  // list() contains loaded live sessions, not the persistence catalog.
  for (const session of store.list()) start(session)
  ctx.effect(() => async () => {
    disposed = true
    for (const session of sessions.keys()) end(session)
    let deadline
    await Promise.race([
      transport.flush(),
      new Promise(resolve => { deadline = setTimeout(resolve, 500) }),
    ])
    clearTimeout(deadline)
    transport.close()
  }, 'open-island: session observers and socket transport')
}
