import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { createServer as createSocket } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';

const listen = async server => {
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return server.address().port;
};
const unusedPort = async () => {
  const server = createSocket();
  const port = await listen(server);
  await new Promise(resolve => server.close(resolve));
  return port;
};

test('Caddy overwrites origin headers and rejects forged Runner ingress', { timeout: 20000 }, async t => {
  const root = await mkdtemp(join(tmpdir(), 'opensession-proxy-'));
  const backend = createServer((req, res) => {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ headers: req.headers, peer: req.socket.remoteAddress }));
  });
  const backendPort = await listen(backend);
  let proxy;
  let logs = '';
  t.after(async () => {
    if (proxy && proxy.exitCode === null && proxy.signalCode === null) {
      const exited = once(proxy, 'exit');
      proxy.kill('SIGTERM');
      const force = setTimeout(() => proxy.kill('SIGKILL'), 3000);
      await exited;
      clearTimeout(force);
    }
    backend.closeAllConnections();
    await new Promise(resolve => backend.close(resolve));
    await rm(root, { recursive: true, force: true });
  });
  // Never bind the real application's ports when running in its own workspace.
  const browser = await unusedPort();
  let runner = await unusedPort();
  while (runner === browser) runner = await unusedPort();
  const template = await readFile(new URL('./Caddyfile', import.meta.url), 'utf8');
  await writeFile(join(root, 'Caddyfile'), template
    .replace('http://:3850 {', `http://127.0.0.1:${browser} {`)
    .replace('http://:3851 {', `http://127.0.0.1:${runner} {`)
    .replaceAll('127.0.0.1:13852', `127.0.0.1:${backendPort}`));
  proxy = spawn(process.env.CADDY_BIN || 'caddy', ['run', '--config', join(root, 'Caddyfile'), '--adapter', 'caddyfile'], {
    env: { ...process.env, XDG_DATA_HOME: root, XDG_CONFIG_HOME: root }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  proxy.stdout.on('data', chunk => { logs = (logs + chunk).slice(-10000); });
  proxy.stderr.on('data', chunk => { logs = (logs + chunk).slice(-10000); });
  proxy.on('error', error => { logs += error.message; });
  const request = (port, path, options = {}) => fetch(`http://127.0.0.1:${port}${path}`, {
    ...options, signal: AbortSignal.timeout(2000),
  });
  let ready = false;
  for (let attempt = 0; attempt < 100; attempt++) {
    try { if ((await request(browser, '/ready')).ok) { ready = true; break; } } catch {}
    if (proxy.exitCode !== null) break;
    await delay(50);
  }
  assert.ok(ready, logs);
  const forged = { 'X-Forwarded-For': '100.64.1.2', Forwarded: 'for=100.64.1.2', 'X-Real-IP': '100.64.1.2' };
  const { headers, peer } = await (await request(browser, '/api/health', { headers: forged })).json();
  assert.equal(peer, '127.0.0.1');
  assert.equal(headers['x-forwarded-for'], '127.0.0.1');
  assert.equal(headers['x-forwarded-host'], `127.0.0.1:${browser}`);
  assert.equal(headers.forwarded, undefined);
  assert.equal(headers['x-real-ip'], undefined);
  for (const port of [browser, runner]) {
    for (const path of ['/api/runners/register', '/api/runners/heartbeat', '/runner-ws']) {
      const response = await request(port, path, { headers: forged });
      assert.equal(response.status, 403, `${port}${path}`);
      assert.match(await response.text(), port === browser ? /dedicated Tailscale/ : /Tailscale source/);
    }
  }
});
