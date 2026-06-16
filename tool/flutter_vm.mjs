/**
 * Minimal Flutter VM service client (Node 24 native WebSocket).
 * Usage: node tool/flutter_vm.mjs <ws-url> <command>
 * Commands: reload, extensions, getIsolate
 */
const WS_URL = process.argv[2];
const COMMAND = process.argv[3] ?? 'reload';

if (!WS_URL) {
  console.error('Usage: node tool/flutter_vm.mjs <ws-url> [reload|extensions|getIsolate]');
  process.exit(1);
}

let id = 1;
const pending = new Map();
const ws = new WebSocket(WS_URL);

function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    const reqId = id++;
    pending.set(reqId, { resolve, reject });
    ws.send(JSON.stringify({ jsonrpc: '2.0', id: reqId, method, params }));
  });
}

ws.addEventListener('error', (e) => { console.error('WS error:', e.message); process.exit(1); });

ws.addEventListener('message', (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id != null && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
  }
});

ws.addEventListener('open', async () => {
  try {
    const vm = await rpc('getVM');
    const isolateRef = vm.isolates?.[0];
    if (!isolateRef) throw new Error('No isolates found');
    const isolateId = isolateRef.id;
    console.log('Isolate:', isolateId, '-', isolateRef.name);

    if (COMMAND === 'reload') {
      const r = await rpc('reloadSources', { isolateId });
      console.log('Hot reload:', r.status ?? JSON.stringify(r));
    } else if (COMMAND === 'reassemble') {
      const r = await rpc('callServiceExtension', {
        isolateId,
        method: 'ext.flutter.reassemble',
      });
      console.log('Reassemble:', JSON.stringify(r));
    } else if (COMMAND === 'getIsolate' || COMMAND === 'extensions') {
      const iso = await rpc('getIsolate', { isolateId });
      if (COMMAND === 'extensions') {
        (iso.extensionRPCs ?? []).forEach(e => console.log(e));
      } else {
        console.log('Name:', iso.name);
        console.log('Extension count:', (iso.extensionRPCs ?? []).length);
        console.log('Extensions:', (iso.extensionRPCs ?? []).slice(0, 10).join(', '));
      }
    } else {
      console.error('Unknown command:', COMMAND);
    }
  } catch (e) {
    console.error('Error:', e.message);
  } finally {
    ws.close();
  }
});
