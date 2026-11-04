// DSH loads client files as lazy closure factories, not raw ESM.
window.__ModuleLoader__.load({
  id: 'open-island-dsh',
  factory: () => {
    const name = 'open-island-dsh'
    const inject = ['connection', 'sessions', 'uiWorkspace', 'conversation']
    const channel = '/open-island-dsh'

    function apply(ctx) {
      ctx.effect(() => {
        const lifetime = new AbortController()
        const clientId = crypto.randomUUID()
        let pollController
        let focusEpoch = 0
        let generation = 0
        const standalone = () => !window.dshMiniWindow && location.hash !== '#dsh-mini-preview'
          && ['standalone', 'fullscreen', 'minimal-ui'].some(mode => window.matchMedia(`(display-mode: ${mode})`).matches)
        const focused = () => document.visibilityState === 'visible' && document.hasFocus()
        const selected = id => (ctx.sessions.retainInfo(id).getSnapshot().retainedBy.mainView ?? 0) > 0
        const call = async (endpoint, payload, signal = lifetime.signal) => {
          const result = await ctx.connection.rpc.call(channel, endpoint, { client_id: clientId, ...payload }, signal)
          if (!result.ok || result.value?.ok !== true) throw new Error('focus relay unavailable')
          return result.value
        }
        const delay = ms => new Promise(resolve => {
          const timer = setTimeout(done, ms)
          function done() {
            clearTimeout(timer)
            lifetime.signal.removeEventListener('abort', done)
            resolve()
          }
          lifetime.signal.addEventListener('abort', done, { once: true })
          if (lifetime.signal.aborted) done()
        })
        const nextPaint = () => new Promise(resolve => {
          const timer = setTimeout(done, 80)
          const frame = requestAnimationFrame(done)
          function done() {
            clearTimeout(timer)
            cancelAnimationFrame(frame)
            lifetime.signal.removeEventListener('abort', done)
            resolve()
          }
          lifetime.signal.addEventListener('abort', done, { once: true })
        })

        async function focus(command, ownGeneration) {
          const current = () => !lifetime.signal.aborted && ownGeneration === generation
            && Date.now() < command.expires_at && standalone()
          if (!current() || !focused()) return false
          // Clear the previous editor's focus so it cannot be mistaken for the
          // newly mounted scoped composer. Navigation and focus use public APIs.
          if (document.activeElement?.isContentEditable) document.activeElement.blur()
          ctx.uiWorkspace.openSession(command.session_id)
          await nextPaint()
          await nextPaint()
          const deadline = Math.min(command.expires_at, Date.now() + 1800)
          while (current() && Date.now() < deadline) {
            if (!selected(command.session_id) || !focused()) return false
            const scope = ctx.sessions.scope(command.session_id)
            if (scope) {
              ctx.conversation.input.for(scope).focus()
              await nextPaint()
              if (!current() || !selected(command.session_id)) return false
              if (focused() && document.activeElement?.isContentEditable) return true
            }
            await delay(40)
          }
          return false
        }

        function changed() {
          if (focused()) focusEpoch += 1
          pollController?.abort()
        }
        window.addEventListener('focus', changed)
        window.addEventListener('blur', changed)
        document.addEventListener('visibilitychange', changed)
        if (focused()) focusEpoch += 1

        async function loop() {
          while (!lifetime.signal.aborted) {
            if (!standalone()) {
              await delay(1000)
              continue
            }
            pollController = new AbortController()
            const abort = () => pollController?.abort()
            lifetime.signal.addEventListener('abort', abort, { once: true })
            try {
              const result = await call('poll', { standalone: true, focused: focused(), focus_epoch: focusEpoch }, pollController.signal)
              const command = result?.command
              if (command && typeof command.request_id === 'string' && typeof command.session_id === 'string'
                && Number.isFinite(command.expires_at)) {
                const ownGeneration = ++generation
                // Continue polling while rendering. A newer selection invalidates
                // every older asynchronous mount/focus continuation.
                void focus(command, ownGeneration).catch(() => false).then(ok => {
                  if (lifetime.signal.aborted || ownGeneration !== generation) return
                  return call('ack', { request_id: command.request_id, ok }).catch(() => {})
                })
              }
            } catch {
              if (!pollController.signal.aborted) await delay(500)
            } finally {
              lifetime.signal.removeEventListener('abort', abort)
            }
          }
        }
        void loop()
        return () => {
          generation += 1
          lifetime.abort()
          pollController?.abort()
          window.removeEventListener('focus', changed)
          window.removeEventListener('blur', changed)
          document.removeEventListener('visibilitychange', changed)
          void call('leave', {}, AbortSignal.timeout(500)).catch(() => {})
        }
      }, 'open-island-dsh: standalone conversation focus')
    }
    return { name, inject, apply }
  },
})
