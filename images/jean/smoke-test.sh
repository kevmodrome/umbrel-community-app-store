#!/usr/bin/env bash
set -euo pipefail

# Requires Docker and Node.js 22+. Installs a managed Codex CLI only when
# JEAN_SMOKE_CODEX_VERSION is supplied; no provider sign-in or model request is performed.
export JEAN_SMOKE_IMAGE="${1:-${JEAN_SMOKE_IMAGE:-}}"
if [ -z "$JEAN_SMOKE_IMAGE" ]; then
  echo "Usage: bash images/jean/smoke-test.sh IMAGE" >&2
  exit 2
fi
export JEAN_SMOKE_PACKAGE_HOME="$(cd "$(dirname "$0")/../../kevmodrome-jean/data/home" && pwd)"

node --input-type=module <<'JS'
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const home = mkdtempSync(join(tmpdir(), 'jean-smoke-'));
cpSync(process.env.JEAN_SMOKE_PACKAGE_HOME, home, { recursive: true });
const name = `jean-smoke-${process.pid}`;
const token = 'a'.repeat(64);
const image = process.env.JEAN_SMOKE_IMAGE;
let created = false;
const docker = (...args) => execFileSync('docker', args, { encoding: 'utf8' }).trim();

function fixtureOwner(uid, gid) {
  // Umbrel installs package data as 1000:1000. CI runners can be UID 1001;
  // adjust only this disposable bind source to reproduce Umbrel's ownership.
  docker('run', '--rm', '--network', 'none', '--user', '0',
    '--entrypoint', '/bin/chown', '--volume', `${home}:/fixture`, image,
    '-R', `${uid}:${gid}`, '/fixture');
}

function removeContainer() {
  docker('rm', '--force', name);
  created = false;
}

async function start() {
  docker('run', '--detach', '--name', name, '--init',
    '--env', 'JEAN_HEADLESS=1', '--env', 'JEAN_HOST=0.0.0.0',
    '--env', 'JEAN_PORT=3456', '--env', `JEAN_TOKEN=${token}`,
    '--publish', '127.0.0.1::3456', '--volume', `${home}:/home/jean`, image);
  created = true;
  const mapping = docker('port', name, '3456/tcp');
  const origin = `http://${mapping}`;
  for (let attempt = 0; attempt < 60; attempt++) {
    try {
      const response = await fetch(`${origin}/readyz`);
      if (response.ok) return origin;
    } catch {}
    await delay(1000);
  }
  throw new Error('Jean did not become ready within 60 seconds');
}

async function connect(origin) {
  const socket = new WebSocket(`${origin.replace('http:', 'ws:')}/ws?token=${token}`);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('WebSocket open timed out')), 10000);
    socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
    socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('WebSocket failed')); }, { once: true });
  });
  let nextId = 0;
  return {
    close: () => socket.close(),
    invoke(command, args = {}, timeoutMs = 30000) {
      const id = String(++nextId);
      return new Promise((resolve, reject) => {
        const finish = (error, data) => {
          clearTimeout(timer);
          socket.removeEventListener('message', onMessage);
          socket.removeEventListener('close', onClose);
          error ? reject(error) : resolve(data);
        };
        const onClose = () => finish(new Error(`${command}: WebSocket closed`));
        const onMessage = ({ data }) => {
          const response = JSON.parse(data);
          if (response.id !== id) return;
          finish(response.type === 'error' ? new Error(`${command}: ${response.error}`) : null, response.data);
        };
        const timer = setTimeout(() => finish(new Error(`${command} timed out`)), timeoutMs);
        socket.addEventListener('message', onMessage);
        socket.addEventListener('close', onClose, { once: true });
        socket.send(JSON.stringify({ type: 'invoke', id, command, args }));
      });
    },
  };
}

try {
  fixtureOwner(1000, 1000);
  let origin = await start();
  assert.equal((await fetch(`${origin}/healthz`)).status, 200);
  assert.equal((await fetch(origin)).status, 200);
  assert.equal((await fetch(`${origin}/api/init`)).status, 401);
  assert.equal((await fetch(`${origin}/api/auth`, {
    headers: { Authorization: 'Bearer incorrect-token' },
  })).status, 401);
  const headers = { Authorization: `Bearer ${token}` };
  assert.equal((await fetch(`${origin}/api/auth`, { headers })).status, 200);
  const nativeOrigin = 'tauri://localhost';
  const nativeAuth = await fetch(`${origin}/api/auth?token=${token}`, {
    headers: { Origin: nativeOrigin },
  });
  assert.equal(nativeAuth.status, 200);
  assert.equal(nativeAuth.headers.get('access-control-allow-origin'), nativeOrigin);
  assert.equal((await nativeAuth.json()).ok, true);
  const nativePreflight = await fetch(`${origin}/api/auth`, {
    method: 'OPTIONS',
    headers: {
      Origin: nativeOrigin,
      'Access-Control-Request-Method': 'GET',
      'Access-Control-Request-Headers': 'authorization',
    },
  });
  assert.equal(nativePreflight.status, 200);
  assert.equal(nativePreflight.headers.get('access-control-allow-origin'), nativeOrigin);
  const init = await (await fetch(`${origin}/api/init`, { headers })).json();
  assert.equal(init.appVersion, '1.0.13');
  assert.equal(init.serverPlatform, 'linux');
  assert.equal(init.appDataDir, '/home/jean/.local/share/com.jean.desktop');
  console.log(`HTTP/token/native-origin/init: passed (Jean ${init.appVersion})`);
  console.log('Container tools:', docker('exec', name, 'sh', '-c',
    'id; git --version; gh --version | head -1; node --version; npm --version; npx --version'));

  let rpc = await connect(origin);
  const prerequisites = await rpc.invoke('check_system_prerequisites');
  assert.equal(prerequisites.gitInstalled, true);
  assert.equal(prerequisites.nodeInstalled, true);
  assert.equal(prerequisites.npmInstalled, true);
  console.log('Onboarding prerequisites:', JSON.stringify({
    gitInstalled: prerequisites.gitInstalled,
    nodeInstalled: prerequisites.nodeInstalled,
    npmInstalled: prerequisites.npmInstalled,
    automaticInstallSupported: prerequisites.automaticInstallSupported,
  }));
  console.log('Initial Codex status:', JSON.stringify(await rpc.invoke('check_codex_cli_installed')));
  const gh = await rpc.invoke('check_gh_cli_installed');
  assert.equal(gh.installed, true);
  await rpc.invoke('patch_preferences', { patch: { theme: 'light' } });

  if (process.env.JEAN_SMOKE_CODEX_VERSION) {
    console.log(`Installing Jean-managed Codex ${process.env.JEAN_SMOKE_CODEX_VERSION}...`);
    await rpc.invoke('install_codex_cli', { version: process.env.JEAN_SMOKE_CODEX_VERSION }, 600000);
    const codex = await rpc.invoke('check_codex_cli_installed');
    assert.equal(codex.installed, true);
    assert.equal(codex.version, process.env.JEAN_SMOKE_CODEX_VERSION);
    console.log('Installed Codex status:', JSON.stringify(codex));
  }
  rpc.close();
  docker('exec', name, 'sh', '-c',
    'mkdir -p /home/jean/projects; printf "persisted-project\n" > /home/jean/projects/smoke.txt');
  removeContainer();
  origin = await start();
  assert.equal(docker('exec', name, 'cat', '/home/jean/projects/smoke.txt'), 'persisted-project');
  const restored = await (await fetch(`${origin}/api/init`, { headers })).json();
  assert.equal(restored.preferences.theme, 'light');
  assert.equal(restored.preferences.default_execution_mode, 'yolo');
  assert.match(docker('exec', name, 'bash', '-l', '-i', '-c', 'node --version; npm --version; npx --version'), /v22\./);
  rpc = await connect(origin);
  const restoredPrerequisites = await rpc.invoke('check_system_prerequisites');
  assert.equal(restoredPrerequisites.nodeInstalled, true);
  assert.equal(restoredPrerequisites.npmInstalled, true);
  if (process.env.JEAN_SMOKE_CODEX_VERSION) {
    const codex = await rpc.invoke('check_codex_cli_installed');
    assert.equal(codex.installed, true);
    assert.equal(codex.version, process.env.JEAN_SMOKE_CODEX_VERSION);
    console.log('Restored Codex status:', JSON.stringify(codex));
  }
  rpc.close();
  console.log('WebSocket, writable home and container-replacement persistence: passed');
} catch (error) {
  if (created) {
    try { console.error(docker('logs', '--tail', '80', name)); } catch {}
  }
  throw error;
} finally {
  if (created) {
    try { removeContainer(); } catch {}
  }
  fixtureOwner(process.getuid(), process.getgid());
  rmSync(home, { recursive: true, force: true });
}
JS
