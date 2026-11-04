// Lifecycle observer, private focus relay, and leased explicit human interactions.
import { connect, createServer } from 'node:net'
import { randomBytes, randomUUID } from 'node:crypto'
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

// One private endpoint carries focus commands and an optional interaction observer.
export async function createFocusRelay({ hasSession, interactions, timeoutMs = 5800, pollMs = 1000 } = {}) {
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
      if (bytes > 1048576 || (bytes > 8192 && !/^\s*\{/.test(buffer + chunk))) {
        accepted = true
        return reply(failure('invalid-request'))
      }
      buffer += chunk.toString('utf8')
      if (!buffer.includes('\n')) return
      accepted = true
      let body
      try { body = JSON.parse(buffer.trim()) } catch { return reply(failure('invalid-request')) }
      if (body?.type === 'observe_interactions' && interactions) {
        clearTimeout(timer)
        return interactions.attach(socket, body)
      }
      if (body?.type === 'respond_interaction' && interactions) return reply(interactions.respond(body))
      if (bytes > 8192 || !body || !validId(body.session_id) || Object.keys(body).length !== 1) return reply(failure('invalid-request'))
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

// Own exactly one answerer at a time. Losing the native observer first revokes
// all request IDs, then delegates to the original DSH waterfall. Never race next().
export function createInteractionController({ isLive, callIdFor, pingMs = 1000, leaseMs = 4000 } = {}) {
  const pending = new Map()
  let observer
  let disposed = false
  const aborted = () => Object.assign(new Error('Question lifetime ended'), { name: 'UserQuestionError', code: 'ASK_ABORTED' })
  const validUUID = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
  const keysOnly = (value, keys) => value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).every(key => keys.includes(key))
  const write = (socket, frame) => {
    if (socket.destroyed || socket.writableEnded || socket.writableLength > 1048576) return false
    try {
      socket.write(JSON.stringify(frame) + '\n')
      return true
    } catch { return false }
  }
  function publish(entry, status, resolution) {
    if (!observer) return false
    const presentation = status === 'pending' ? entry.presentation
      : { request_id: entry.presentation.request_id, kind: entry.presentation.kind, call_id: entry.presentation.call_id }
    return write(observer.socket, { type: 'interaction', session_id: entry.session.id,
      interaction: { ...presentation, status, ...(resolution ? { resolution } : {}) } })
  }
  function finish(entry, action, value) {
    if (pending.get(entry.presentation.request_id) !== entry) return
    pending.delete(entry.presentation.request_id)
    entry.signal?.removeEventListener('abort', entry.abort)
    if (!publish(entry, 'resolved', action) && observer) detach(observer)
    // Promise scheduling prevents a downstream handler from running before every
    // stale ID has been revoked during observer shutdown.
    if (action === 'delegate') Promise.resolve().then(entry.next).then(entry.resolve, entry.reject)
    else if (action === 'cancelled') {
      if (entry.presentation.kind === 'approval') entry.resolve('cancelled')
      else entry.reject(aborted())
    } else entry.resolve(value)
  }
  function detach(client) {
    if (observer !== client) return
    observer = undefined
    clearInterval(client.timer)
    for (const entry of [...pending.values()]) finish(entry, 'delegate')
    client.socket.destroy()
  }
  function attach(socket, body) {
    if (disposed || !keysOnly(body, ['type', 'protocol_version', 'observer_id']) || body.protocol_version !== 1 || !validUUID(body.observer_id)) {
      return socket.end(JSON.stringify(failure('invalid-request')) + '\n')
    }
    if (observer) return socket.end(JSON.stringify(failure('busy')) + '\n')
    const client = { socket, id: body.observer_id, seen: Date.now(), nonce: undefined }
    observer = client
    let buffer = ''
    socket.on('data', chunk => {
      buffer += chunk.toString('utf8')
      if (Buffer.byteLength(buffer) > 8192) return detach(client)
      while (buffer.includes('\n')) {
        const index = buffer.indexOf('\n')
        const line = buffer.slice(0, index)
        buffer = buffer.slice(index + 1)
        let frame
        try { frame = JSON.parse(line) } catch { return detach(client) }
        if (!keysOnly(frame, ['type', 'nonce', 'observer_id']) || frame.type !== 'interaction_pong'
          || frame.observer_id !== client.id || !client.nonce || frame.nonce !== client.nonce) return detach(client)
        client.seen = Date.now()
        client.nonce = undefined
      }
    })
    socket.once('close', () => detach(client))
    socket.once('end', () => detach(client))
    socket.once('error', () => detach(client))
    client.timer = setInterval(() => {
      if (Date.now() - client.seen >= leaseMs) return detach(client)
      // Keep only one challenge outstanding. Repeating it while a busy app is
      // catching up would produce duplicate pongs and revoke a healthy observer.
      if (client.nonce) return
      client.nonce = randomUUID()
      if (!write(socket, { type: 'interaction_ping', observer_id: client.id, nonce: client.nonce })) detach(client)
    }, pingMs)
    client.timer.unref()
    if (!write(socket, { type: 'interaction_ready', protocol_version: 1, observer_id: client.id })) detach(client)
  }
  function questionsOf(request) {
    const questions = request.questions
    if (!Array.isArray(questions) || questions.length < 1 || questions.length > 16) return undefined
    const ids = new Set()
    for (const question of questions) {
      if (!validId(question?.id) || ids.has(question.id) || typeof question.question !== 'string'
        || (question.detail !== undefined && typeof question.detail !== 'string')
        || (question.header !== undefined && typeof question.header !== 'string')
        || (question.multiSelect !== undefined && typeof question.multiSelect !== 'boolean')) return undefined
      ids.add(question.id)
      if (question.options !== undefined && (!Array.isArray(question.options) || question.options.length > 64
        || question.options.some(option => !validId(option?.label)
          || (option.description !== undefined && typeof option.description !== 'string'))
        || new Set(question.options.map(option => option.label)).size !== question.options.length)) return undefined
      if (question.intent !== undefined && (question.intent.kind !== 'plan-review'
        || !question.options?.some(option => option.label === question.intent.approve))) return undefined
    }
    // Do not truncate a decision's meaning. Oversized requests retain native UI.
    if (Buffer.byteLength(JSON.stringify(questions)) > 900000) return undefined
    return questions.map(question => ({ id: question.id, question: question.question,
      ...(question.detail === undefined ? {} : { detail: question.detail }),
      ...(question.header === undefined ? {} : { header: question.header }),
      ...(question.options === undefined ? {} : { options: question.options.map(option => ({
        label: option.label, ...(option.description === undefined ? {} : { description: option.description }),
      })) }),
      ...(question.multiSelect === undefined ? {} : { multiSelect: question.multiSelect }),
      ...(question.intent === undefined ? {} : { intent: { ...question.intent } }),
    }))
  }
  function request(kind, req, next) {
    const session = req.agent?.session
    // Timed waits need a separate public attachWait claim. This slice deliberately
    // leaves their existing countdown and late-answer UI in native DSH.
    if (disposed || !observer || pending.size >= 128 || !session || !isLive(req.agent) || req.wait?.timed === true) return next()
    if (req.signal?.aborted) return kind === 'approval' ? Promise.resolve('cancelled') : Promise.reject(aborted())
    let presentation
    if (kind === 'approval') {
      if (!validId(req.toolName) || (req.reason !== undefined && typeof req.reason !== 'string')) return next()
      presentation = { kind, tool_name: req.toolName, ...(req.reason === undefined ? {} : { reason: req.reason }),
        ...(req.callId === undefined ? {} : { call_id: req.callId }) }
    } else {
      let questions
      try { questions = questionsOf(req) } catch { return next() }
      if (!questions) return next()
      const plan = questions.length === 1 && questions[0].intent?.kind === 'plan-review'
      const callId = req.wait?.callId ?? questions[0].intent?.callId ?? callIdFor?.(session)
      presentation = { kind: plan ? 'plan' : 'question', questions, ...(callId ? { call_id: callId } : {}) }
    }
    presentation.request_id = randomUUID()
    return new Promise((resolve, reject) => {
      const entry = { session, agent: req.agent, presentation, next, resolve, reject, signal: req.signal }
      entry.abort = () => finish(entry, 'cancelled')
      pending.set(presentation.request_id, entry)
      req.signal?.addEventListener('abort', entry.abort, { once: true })
      if (req.signal?.aborted) return entry.abort()
      if (!publish(entry, 'pending')) detach(observer)
    })
  }
  function respond(body) {
    if (!keysOnly(body, ['type', 'observer_id', 'session_id', 'request_id', 'decision', 'answers'])
      || !validId(body.session_id) || !validUUID(body.request_id)) return failure('invalid-request')
    if (!observer || body.observer_id !== observer.id) return failure('stale-request')
    const entry = pending.get(body.request_id)
    if (!entry || entry.session.id !== body.session_id || !isLiveSession(entry)) return failure('stale-request')
    if (body.decision === 'delegate' && body.answers === undefined) {
      finish(entry, 'delegate')
      return { ok: true }
    }
    if (entry.presentation.kind === 'approval') {
      if (body.answers !== undefined || !['allowed-once', 'rejected'].includes(body.decision)) return failure('invalid-request')
      finish(entry, 'answered', body.decision)
      return { ok: true }
    }
    const questions = entry.presentation.questions
    if (body.decision !== undefined || !Array.isArray(body.answers) || body.answers.length !== questions.length) return failure('invalid-request')
    const ids = new Set()
    for (const answer of body.answers) {
      const question = questions.find(item => item.id === answer?.id)
      if (!keysOnly(answer, ['id', 'selected', 'custom']) || !question || ids.has(answer.id)
        || !Array.isArray(answer.selected) || new Set(answer.selected).size !== answer.selected.length
        || answer.selected.some(label => !question.options?.some(option => option.label === label))
        || (!question.multiSelect && answer.selected.length > 1)
        || (answer.custom !== undefined && (typeof answer.custom !== 'string' || answer.custom.length > 4096))) return failure('invalid-request')
      ids.add(answer.id)
    }
    finish(entry, 'answered', { answers: body.answers.map(answer => ({ id: answer.id,
      selected: [...answer.selected], ...(answer.custom === undefined ? {} : { custom: answer.custom }),
    })) })
    return { ok: true }
  }
  function isLiveSession(entry) {
    return !disposed && !entry.signal?.aborted && isLive(entry.agent)
  }
  return {
    attach, respond,
    request,
    cancelSession(session) {
      for (const entry of [...pending.values()]) if (entry.session === session) finish(entry, 'cancelled')
    },
    cancelCall(session, callId) {
      if (!validId(callId)) return
      for (const entry of [...pending.values()]) if (entry.session === session && entry.presentation.call_id === callId) finish(entry, 'cancelled')
    },
    close() {
      disposed = true
      if (observer) detach(observer)
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
  const interactions = createInteractionController({
    isLive: agent => !disposed && !!agent && store.get(agent.session?.id) === agent.session
      && sessions.has(agent.session) && ctx.get('agents')?.get(agent.id) === agent
      && ctx.get('agents')?.roots().includes(agent),
    callIdFor: session => {
      const calls = [...(sessions.get(session)?.tools ?? [])].filter(([, tool]) => tool === 'ask_user_question')
      return calls.length === 1 ? calls[0][0] : undefined
    },
  })
  ctx.on('user-questions/request', (request, next) => interactions.request('question', request, next), { prepend: true })
  ctx.on('approval/request', (request, next) => interactions.request('approval', request, next), { prepend: true })

  // Web services are optional. The sessions-only CLI observer keeps working.
  ctx.inject(['connection', 'webApp'], webCtx => {
    webCtx.effect(() => {
      let cancelled = false
      let relay
      let unregister
      const ready = createFocusRelay({
        interactions,
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
    interactions.cancelSession(session)
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
    if (event.type === 'tool/result') interactions.cancelCall(session, event.data?.message?.toolCallId)
    if (event.type === 'turn/end') interactions.cancelSession(session)
    const lifecycle = normalizeEvent(state, event)
    if (lifecycle) send(session, state, lifecycle)
  })
  // list() contains loaded live sessions, not the persistence catalog.
  for (const session of store.list()) start(session)
  ctx.effect(() => async () => {
    disposed = true
    for (const session of sessions.keys()) end(session)
    interactions.close()
    let deadline
    await Promise.race([
      transport.flush(),
      new Promise(resolve => { deadline = setTimeout(resolve, 500) }),
    ])
    clearTimeout(deadline)
    transport.close()
  }, 'open-island: session observers and socket transport')
}
