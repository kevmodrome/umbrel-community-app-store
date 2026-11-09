#!/usr/bin/env bash
set -euo pipefail
export OPENSESSION_SMOKE_IMAGE="${1:?Usage: bash images/opensession/smoke-test.sh IMAGE}"

# All data and shell commands below belong to this disposable container.
# No real provider sign-in, GitHub token or model request is involved.
node --input-type=module <<'JS'
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const root = mkdtempSync(join(tmpdir(), 'opensession-smoke-'));
const home = join(root, 'home');
const workspace = join(root, 'workspace');
mkdirSync(home); mkdirSync(workspace);
const image = process.env.OPENSESSION_SMOKE_IMAGE;
const seedImage = process.env.OPENSESSION_SMOKE_SEED_IMAGE || image;
const name = `opensession-smoke-${process.pid}`;
const docker = (...args) => execFileSync('docker', args, { encoding: 'utf8' }).trim();
let created = false;
let socket;
async function start(reference = image) {
  docker('run', '--detach', '--name', name,
    '--env', 'OPENSESSION_UI_BASE=http://umbrel.local:13850',
    '--publish', '127.0.0.1::3850',
    '--volume', `${home}:/home/opensession`, '--volume', `${workspace}:/workspace`, reference);
  created = true;
  const origin = `http://${docker('port', name, '3850/tcp')}`;
  for (let attempt = 0; attempt < 120; attempt++) {
    try { if ((await fetch(`${origin}/ready`)).ok) return origin; } catch {}
    if (docker('inspect', '--format', '{{.State.Running}}', name) === 'false') break;
    await delay(1000);
  }
  throw new Error('Open Session did not become ready within 120 seconds');
}
function remove() {
  docker('rm', '--force', name);
  created = false;
}
const inside = code => docker('exec', '--user', '1000:1000', name, 'node', '--input-type=module', '-e', code);
function checkVersion(reference) {
  const label = docker('image', 'inspect', '--format', '{{index .Config.Labels "org.opencontainers.image.version"}}', reference);
  const release = inside(`import fs from 'node:fs'; console.log(JSON.parse(fs.readFileSync('/opt/opensession/release.json')).version);`);
  assert.equal(release.replace(/^v/, ''), label.replace(/-\d+$/, ''), 'release archive does not match image version');
}

try {
  let origin = await start(seedImage);
  checkVersion(seedImage);
  assert.equal((await fetch(origin)).status, 200);
  assert.equal((await (await fetch(`${origin}/api/health?brief=1`)).json()).ok, true);
  assert.equal((await (await fetch(`${origin}/api/setup/onboarding`)).json()).completed, false);
  assert.match(docker('exec', '--user', '1000:1000', name, 'bash', '-lc',
    'git --version; gh --version; node --version; npm --version; bun --version; codex --version; claude --version; rg --version'), /codex-cli 0\.166\.0/);
  assert.equal(inside(`import fs from 'node:fs';
    const config = JSON.parse(fs.readFileSync('/home/opensession/.opensession/config.json'));
    const pi = JSON.parse(fs.readFileSync('/home/opensession/.opensession/pi.json'));
    if (pi.enabled !== true || config.paths.worktreesDir !== '/workspace/.worktrees') process.exit(1);
    fs.accessSync(config.paths.mcpConfig, fs.constants.W_OK);
    console.log('engine/config writable');`), 'engine/config writable');

  const settings = `${origin}/api/settings/general`;
  const update = (body, headers) => fetch(settings, {
    method: 'PUT', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body),
  });
  assert.equal((await update({ organizationName: 'rejected' }, { Origin: 'https://evil.example' })).status, 403);
  assert.equal((await update({ organizationName: 'rejected' }, { Origin: origin, 'Sec-Fetch-Site': 'cross-site' })).status, 403);
  assert.equal((await update({ organizationName: 'Umbrel Smoke Persistence' }, { Origin: origin })).status, 200);
  console.log('Browser, onboarding, engine configuration and origin protection: passed');

  // Exercise the actual browser terminal transport without opening a model turn.
  socket = new WebSocket(`${origin.replace('http:', 'ws:')}/ws`);
  let transcript = '';
  const terminal = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Browser terminal proof timed out')), 20000);
    socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error('WebSocket failed')); });
    socket.addEventListener('open', () => socket.send(JSON.stringify({
      type: 'term_start', sessionId: 'umbrel-smoke-no-session', termId: 'smoke', cols: 80, rows: 24,
    })));
    socket.addEventListener('message', ({ data }) => {
      const message = JSON.parse(data);
      if (message.type === 'term_ready' && message.termId === 'smoke') {
        const command = "cd /workspace && printf '\\n%s%s:%s\\n' 'UMBREL_' 'PTY_OK' \"$(id -u)\"\r";
        socket.send(JSON.stringify({ type: 'term_input', termId: 'smoke', data: Buffer.from(command).toString('base64') }));
      }
      if (message.type === 'term_data' && message.termId === 'smoke') {
        transcript += Buffer.from(message.data, 'base64').toString('utf8');
        if (transcript.includes('UMBREL_PTY_OK:1000')) { clearTimeout(timer); resolve(); }
      }
      if (message.type === 'term_error') { clearTimeout(timer); reject(new Error(JSON.stringify(message))); }
    });
  });
  await terminal;
  socket.send(JSON.stringify({ type: 'term_stop', termId: 'smoke' }));
  socket.close(); socket = undefined;
  inside(`import fs from 'node:fs'; import { execFileSync } from 'node:child_process';
    fs.writeFileSync('/workspace/smoke-project.txt', 'persistent project');
    fs.mkdirSync('/home/opensession/.codex-accounts', {recursive:true});
    fs.writeFileSync('/home/opensession/.codex-accounts/smoke-marker', 'persistent home');
    execFileSync('git', ['-C','/home/opensession/.opensession/scratch','worktree','add','-b','umbrel-smoke','/workspace/smoke-worktree']);
    console.log('worktree created');`);
  console.log('Browser WebSocket terminal, non-root commands and Git worktree creation: passed');

  // Use the upstream env-file serializer's escaping, with shell syntax that
  // must remain literal data when saved integration settings are reloaded.
  const literal = 'quote" backslash\\ dollar$(touch /tmp/opensession-smoke-should-not-exist)';
  inside(`import fs from 'node:fs';
    fs.appendFileSync('/home/opensession/.opensession.env', ${JSON.stringify('\nOPENSESSION_SMOKE_VALUE=' + JSON.stringify(literal) + '\n')});`);

  remove();
  origin = await start();
  checkVersion(image);
  if (process.env.OPENSESSION_SMOKE_CODEMODE === '1') {
    inside(`import fs from 'node:fs';
      fs.accessSync('/opt/opensession/quickjs.wasm');
      fs.accessSync('/opt/opensession/codemode-worker.js');`);
    const result = docker('exec', '--user', '1000:1000', '--workdir', '/workspace', name, 'opensession', 'codemode-smoke');
    assert.match(result, /Script completed/);
    assert.match(result, /\b42\b/);
    console.log('Compiled codemode worker and QuickJS execution outside the release directory: passed');
  }
  assert.equal((await (await fetch(`${origin}/api/settings/general`)).json()).organizationName, 'Umbrel Smoke Persistence');
  inside(`import fs from 'node:fs'; import assert from 'node:assert/strict';
    assert.equal(fs.readFileSync('/workspace/smoke-project.txt','utf8'), 'persistent project');
    assert.equal(fs.readFileSync('/home/opensession/.codex-accounts/smoke-marker','utf8'), 'persistent home');
    fs.accessSync('/workspace/smoke-worktree/README.md');`);
  inside(`import fs from 'node:fs'; import assert from 'node:assert/strict';
    const pid=fs.readdirSync('/proc').filter(x=>/^\\d+$/.test(x)).find(x=>{
      try { const args=fs.readFileSync('/proc/'+x+'/cmdline','utf8').split('\\0');
        return args.includes('server') && args[0].includes('opensession'); } catch { return false; }
    });
    assert.ok(pid, 'server process missing');
    assert.match(fs.readFileSync('/proc/'+pid+'/status','utf8'), /^Uid:\\s+1000\\s/m);
    const env=fs.readFileSync('/proc/'+pid+'/environ','utf8').split('\\0');
    assert.ok(env.includes('OPENSESSION_WORKTREES_DIR=/workspace/.worktrees'));
    assert.ok(env.includes('OPENSESSION_SMOKE_VALUE=' + ${JSON.stringify(literal)}));
    assert.equal(fs.existsSync('/tmp/opensession-smoke-should-not-exist'), false);`);
  console.log(`Settings, project, worktree and full-home persistence after ${seedImage === image ? 'container replacement' : 'version upgrade'}: passed`);
  console.log('Effective worktree path and literal saved-environment round trip: passed');

  // A dead kernel must stop the container, so restart:on-failure can recover it.
  inside(`import fs from 'node:fs';
    const pid=fs.readdirSync('/proc').filter(x=>/^\\d+$/.test(x)).find(x=>{
      try { return fs.readFileSync('/proc/'+x+'/cmdline','utf8').split('\\0').includes('session-kernel-service'); } catch { return false; }
    });
    if (!pid) throw new Error('session kernel process missing');
    const status=fs.readFileSync('/proc/'+pid+'/status','utf8');
    if (!/^Uid:\\s+1000\\s/m.test(status)) throw new Error('session kernel is not running as UID1000');
    process.kill(Number(pid),'SIGKILL');`);
  let exited = false;
  for (let attempt = 0; attempt < 30; attempt++) {
    if (docker('inspect', '--format', '{{.State.Running}}', name) === 'false') { exited = true; break; }
    await delay(1000);
  }
  assert.equal(exited, true, 'container stayed alive after its session kernel died');
  assert.notEqual(docker('inspect', '--format', '{{.State.ExitCode}}', name), '0');
  console.log('Kernel failure propagation and Docker restart eligibility: passed');
} catch (error) {
  if (created) { try { console.error(docker('logs', '--tail', '80', name)); } catch {} }
  throw error;
} finally {
  socket?.close();
  if (created) { try { remove(); } catch {} }
  try {
    docker('run', '--rm', '--network', 'none', '--user', '0', '--entrypoint', '/bin/chown',
      '--volume', `${root}:/fixture`, image, '-R', `${process.getuid()}:${process.getgid()}`, '/fixture');
  } finally { rmSync(root, { recursive: true, force: true }); }
}
JS
