// Read-only DSH host observer. No client UI or approval answerer is registered.
import { connect } from 'node:net'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const name = 'open-island'
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
        socket.end(item.line, () => finish(true))
      })
      socket.unref()
      socket.once('error', () => finish(false))
      socket.once('close', () => finish(false))
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

export function apply(ctx, config = {}) {
  const store = ctx.sessions
  const socketPath = config.socketPath || process.env.OPEN_ISLAND_SOCKET_PATH
    || process.env.VIBE_ISLAND_SOCKET_PATH
    || join(process.env.HOME || homedir(), 'Library/Application Support/OpenIsland/bridge.sock')
  const heartbeatMs = validInterval(config.heartbeatIntervalMs ?? process.env.OPEN_ISLAND_HEARTBEAT_INTERVAL_MS)
  const transport = createSocketTransport(socketPath)
  const sessions = new Map()
  let disposed = false

  function send(session, state, lifecycle) {
    const payload = {
      session_id: session.id,
      cwd: session.header?.cwd || process.cwd(),
      model: state.model,
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
