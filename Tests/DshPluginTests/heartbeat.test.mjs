import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import test from 'node:test'

let cordisURL
let sessionURL
let agentURL
try {
  const require = process.env.DSH_PACKAGE_ROOT
    ? createRequire(join(process.env.DSH_PACKAGE_ROOT, 'package.json')) : createRequire(import.meta.url)
  cordisURL = pathToFileURL(require.resolve('@deepseek-ai/cordis')).href
  sessionURL = pathToFileURL(require.resolve('@deepseek-ai/dsh-session')).href
  agentURL = pathToFileURL(require.resolve('@deepseek-ai/dsh-agent')).href
} catch (error) {
  if (process.env.DSH_PACKAGE_ROOT) throw error
}

const pluginURL = new URL('../../Sources/OpenIslandApp/Resources/open-island-dsh/open-island-dsh.js', import.meta.url).href

test('loaded sessions and an unavailable bridge never keep a host process alive', {
  skip: !cordisURL && 'Set DSH_PACKAGE_ROOT for real API coverage',
}, () => {
  const script = `
    import { Context } from ${JSON.stringify(cordisURL)}
    import SessionStore from ${JSON.stringify(sessionURL)}
    import AgentRegistry from ${JSON.stringify(agentURL)}
    import * as observer from ${JSON.stringify(pluginURL)}
    const ctx = new Context()
    await ctx.plugin(SessionStore).inertia
    const session = ctx.sessions.create('live-at-exit', { meta: { cwd: '/workspace' } })
    await ctx.plugin(AgentRegistry).inertia
    await ctx.agents.register({ id: session.id, session, ctx })
    const plugin = ctx.plugin(observer, { socketPath: '/tmp/oi-dsh-not-running/bridge.sock' })
    await plugin.inertia
    if (plugin.state !== 2) throw new Error('Observer did not activate')
    // Intentionally leave the session and observer loaded, as at normal CLI exit.
  `
  const child = spawnSync(process.execPath, ['--input-type=module', '-e', script], {
    timeout: 2000,
    encoding: 'utf8',
  })
  assert.ifError(child.error)
  assert.equal(child.status, 0, child.stderr)
  assert.equal(child.stderr, '')
})
