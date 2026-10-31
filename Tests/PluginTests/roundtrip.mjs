import fs from 'node:fs';
const source = fs.readFileSync(new URL('../../Sources/OpenIslandApp/Resources/open-island-opencode.js', import.meta.url), 'utf8');
const { default: createPlugin } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const plugin = await createPlugin({ serverUrl: new URL('http://localhost:4096'), client: { _client: { getConfig: () => ({ fetch: async request => {
  process.stdout.write(await request.text());
  return new Response('{}');
} }) } } });
await plugin.event({ event: { type: 'question.asked', properties: { id: 'q1', sessionID: 'contract', questions: [
  { question: 'Choose colors', options: [{label:'Red'}, {label:'Blue'}], multiSelect: true },
  { question: 'Choose size', options: [{label:'Small'}, {label:'Large'}] }
] } } });
