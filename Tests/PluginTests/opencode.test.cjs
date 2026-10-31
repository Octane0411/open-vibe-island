const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { EventEmitter } = require('node:events');
const source = fs.readFileSync(new URL('../../Sources/OpenIslandApp/Resources/open-island-opencode.js', `file://${__filename}`), 'utf8');
function fixture() {
  const socket = new EventEmitter();
  socket.write = () => {};
  socket.end = () => {};
  socket.setTimeout = () => {};
  socket.destroy = () => { socket.destroyed = true; };
  const context = { Buffer, setTimeout, clearTimeout, process: { env: {} }, Request,
    homedir: () => '/unused', appendFileSync: () => {},
    connect: (_, connected) => { queueMicrotask(connected); return socket; } };
  vm.createContext(context);
  vm.runInContext(source.replace(/^import .*;\n/gm, '').replace('export default', 'globalThis.plugin ='), context);
  return { socket, context };
}
const hello = JSON.stringify({ type: 'hello', hello: { protocolVersion: 2 } }) + '\n';
const response = JSON.stringify({ type: 'response', response: { type: 'openCodeHookDirective', directive: { type: 'allow' } } }) + '\n';
test('only complete response envelopes resolve a fragmented producer request', async () => {
  for (let split = 1; split < response.length; split++) {
    const { socket, context } = fixture();
    const result = context.sendAndWaitResponse({});
    socket.emit('data', Buffer.from(hello + '{"type":"event"}\n' + response.slice(0, split)));
    assert.ok(!socket.destroyed, `premature completion at byte ${split}`);
    socket.emit('data', Buffer.from(response.slice(split)));
    assert.equal((await result)?.response?.directive?.type, 'allow');
  }
});
test('an incomplete response at EOF is not accepted', async () => {
  const { socket, context } = fixture();
  const result = context.sendAndWaitResponse({});
  socket.emit('data', Buffer.from(hello + response.trimEnd()));
  socket.emit('end');
  assert.equal(await result, null);
});
test('unsupported hello is rejected', async () => {
  const { socket, context } = fixture();
  const result = context.sendAndWaitResponse({});
  socket.emit('data', Buffer.from(hello.replace(':2', ':99') + response));
  assert.equal(await result, null);
});
test('oversized unterminated frames close the connection', async () => {
  const { socket, context } = fixture();
  const result = context.sendAndWaitResponse({});
  socket.emit('data', Buffer.alloc(4 * 1024 * 1024 + 1, 120));
  assert.equal(await result, null);
  assert.ok(socket.destroyed);
});
test('a silent peer is closed by the total deadline', async () => {
  const { socket, context } = fixture();
  assert.equal(await context.sendAndWaitResponse({}, 10), null);
  assert.ok(socket.destroyed);
});
