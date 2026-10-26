'use strict';

const vscode = require('vscode');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

const AUTHORITY = 'open-island.terminal-jump';
const REFRESH_INTERVAL_MS = 15_000;
let companion;

class TerminalCompanion {
  constructor() {
    this.output = vscode.window.createOutputChannel('Open Island Terminal Jump');
    this.directory = path.join(os.homedir(), '.cache', 'open-island', 'vscode-terminals');
    this.terminals = new Map();
    this.tokens = new Map();
    this.listeners = [];
    this.queue = Promise.resolve();
    this.stopped = false;
    this.refreshPending = false;
  }

  start() {
    // Subscribe before enumerating so terminals opened during activation are not lost.
    this.listeners.push(
      vscode.window.onDidOpenTerminal(terminal => this.add(terminal)),
      vscode.window.onDidCloseTerminal(terminal => this.close(terminal)),
      vscode.window.registerUriHandler({ handleUri: uri => this.handleUri(uri) })
    );
    for (const terminal of vscode.window.terminals) this.add(terminal);
    this.timer = setInterval(() => this.refresh(), REFRESH_INTERVAL_MS);
    this.output.appendLine(`Activated (${vscode.env.remoteName || 'local'}); ${this.terminals.size} existing terminals.`);
  }

  report(error, operation) {
    const message = error instanceof Error ? error.message : String(error);
    this.output.appendLine(`${operation}: ${message}`);
  }

  enqueue(operation, description) {
    // One publication/cleanup queue prevents a slow refresh from overtaking close.
    this.queue = this.queue.then(operation).catch(error => this.report(error, description));
    return this.queue;
  }

  isLive(state) {
    return !this.stopped && !state.closed && this.terminals.get(state.terminal) === state;
  }

  add(terminal) {
    if (this.stopped || this.terminals.has(terminal)) return;
    const state = {
      terminal,
      token: randomUUID(),
      pid: undefined,
      uri: undefined,
      closed: false
    };
    // A closed terminal must not leave activation or shutdown waiting for processId.
    state.cancelled = new Promise(resolve => { state.cancel = resolve; });
    this.terminals.set(terminal, state);
    this.tokens.set(state.token, state);
    this.enqueue(() => this.publish(state), 'Register terminal');
  }

  close(terminal) {
    const state = this.terminals.get(terminal);
    if (!state) return;
    state.closed = true;
    state.cancel();
    this.terminals.delete(terminal);
    this.tokens.delete(state.token);
    this.enqueue(() => this.removeRecord(state), 'Remove closed terminal');
  }

  refresh() {
    if (this.stopped || this.refreshPending) return;
    this.refreshPending = true;
    this.enqueue(async () => {
      try {
        for (const state of this.terminals.values()) {
          try {
            await this.publish(state);
          } catch (error) {
            this.report(error, `Refresh terminal ${state.pid || state.terminal.name}`);
          }
        }
      } finally {
        this.refreshPending = false;
      }
    }, 'Refresh registry');
  }

  async publish(state) {
    if (!this.isLive(state)) return;
    const pid = await Promise.race([state.terminal.processId, state.cancelled]);
    if (!this.isLive(state) || !Number.isSafeInteger(pid) || pid <= 0) return;
    state.pid = pid;
    const internalURI = vscode.Uri.parse(`${vscode.env.uriScheme}://${AUTHORITY}/focus?token=${state.token}`);
    const externalURI = await Promise.race([
      vscode.env.asExternalUri(internalURI), state.cancelled
    ]);
    if (!this.isLive(state)) return;
    if (!['vscode', 'vscode-insiders'].includes(externalURI.scheme) ||
        externalURI.authority !== AUTHORITY || externalURI.path !== '/focus') {
      throw new Error('VS Code returned an unsupported terminal focus URI.');
    }
    await fs.mkdir(this.directory, { recursive: true, mode: 0o700 });
    await fs.chmod(this.directory, 0o700);
    if (!this.isLive(state)) return;

    const uri = externalURI.toString();
    const filename = path.join(this.directory, `${pid}.json`);
    const temporary = path.join(this.directory, `.${pid}.${randomUUID()}.tmp`);
    try {
      await fs.writeFile(temporary, JSON.stringify({
        uri,
        remote: Boolean(vscode.env.remoteName),
        updatedAt: Date.now()
      }) + '\n', { flag: 'wx', mode: 0o600 });
      if (!this.isLive(state)) return;
      await fs.rename(temporary, filename);
      state.uri = uri;
      // close/deactivate can run while rename is in flight.
      if (!this.isLive(state)) await this.removeRecord(state);
    } finally {
      await this.unlinkIfPresent(temporary);
    }
  }

  async unlinkIfPresent(filename) {
    try {
      await fs.unlink(filename);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }

  async removeRecord(state) {
    if (!state.pid || !state.uri) return;
    const filename = path.join(this.directory, `${state.pid}.json`);
    let record;
    try {
      record = JSON.parse(await fs.readFile(filename, 'utf8'));
    } catch (error) {
      if (error.code === 'ENOENT') return;
      throw error;
    }
    // Another extension host may have registered the same restored process.
    // Never remove a record whose window/token does not belong to this instance.
    if (record.uri === state.uri) await this.unlinkIfPresent(filename);
  }

  async handleUri(uri) {
    try {
      if (!['vscode', 'vscode-insiders'].includes(uri.scheme) ||
          uri.authority !== AUTHORITY || uri.path !== '/focus') {
        await vscode.window.showWarningMessage('Open Island: invalid terminal focus link.');
        return;
      }
      const tokens = new URLSearchParams(uri.query).getAll('token');
      const state = tokens.length === 1 ? this.tokens.get(tokens[0]) : undefined;
      if (!state || !this.isLive(state) || !vscode.window.terminals.includes(state.terminal)) {
        await vscode.window.showWarningMessage('Open Island: this terminal link is missing or stale. Select a running session again.');
        return;
      }
      state.terminal.show(false);
      await vscode.commands.executeCommand('workbench.action.focusWindow');
      this.output.appendLine(`Focused pid=${state.pid ?? 'unknown'} name=${JSON.stringify(state.terminal.name)} activeTerminalMatches=${vscode.window.activeTerminal === state.terminal} windowFocused=${vscode.window.state.focused} (immediate observation)`);
    } catch (error) {
      this.report(error, 'Focus terminal');
      try {
        await vscode.window.showErrorMessage('Open Island could not focus the selected terminal. See the Open Island Terminal Jump output channel.');
      } catch (notificationError) {
        this.report(notificationError, 'Show focus error');
      }
    }
  }

  async stop() {
    if (this.stopped) return this.queue;
    this.stopped = true;
    clearInterval(this.timer);
    for (const listener of this.listeners) listener.dispose();
    const states = [...this.terminals.values()];
    for (const state of states) {
      state.closed = true;
      state.cancel();
    }
    this.terminals.clear();
    this.tokens.clear();
    await this.enqueue(async () => {
      for (const state of states) {
        try {
          await this.removeRecord(state);
        } catch (error) {
          this.report(error, `Remove terminal ${state.pid}`);
        }
      }
    }, 'Deactivate');
    this.output.dispose();
  }
}

function activate() {
  companion = new TerminalCompanion();
  companion.start();
}

async function deactivate() {
  if (companion) await companion.stop();
  companion = undefined;
}

module.exports = { activate, deactivate };
