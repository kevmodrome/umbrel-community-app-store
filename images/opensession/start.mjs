import { randomBytes } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

const home = process.env.HOME;
const state = join(home, '.opensession');
const configPath = join(state, 'config.json');
mkdirSync(join(state, 'bin'), { recursive: true });
mkdirSync(join(home, '.local', 'bin'), { recursive: true });
const shim = join(state, 'bin', 'opensession');
if (!existsSync(shim)) symlinkSync('/opt/opensession/opensession', shim);

if (!existsSync(configPath)) {
  const setup = spawnSync('opensession', ['onboard', '--defaults'], {
    cwd: '/opt/opensession', stdio: 'inherit',
  });
  if (setup.error) throw setup.error;
  if (setup.status !== 0) process.exit(setup.status ?? 1);
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  config.server.host = process.env.HOST || '0.0.0.0';
  config.server.publicBaseUrl = process.env.OPENSESSION_UI_BASE || 'http://umbrel.local:13850';
  config.paths.worktreesDir = '/workspace/.worktrees';
  config.paths.mcpConfig = join(state, 'mcp-config.json');
  writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
  writeFileSync(config.paths.mcpConfig, '{"mcpServers":{}}\n', { mode: 0o600, flag: 'wx' });
}

// The UI persists integration settings in this dotenv file. Parse it as data:
// provider secrets must never become shell commands. Container settings win.
const envPath = join(home, '.opensession.env');
const savedEnv = {};
if (existsSync(envPath)) {
  // Match upstream readEnvFileValues/formatEnvLine, including escaped quotes
  // and backslashes. Generic dotenv parsers do not round-trip this format.
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const match = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    const quoted = value.match(/^"((?:[^"\\]|\\.)*)"$/);
    if (quoted) value = quoted[1].replace(/\\(.)/g, '$1');
    else {
      const single = value.match(/^'([^']*)'$/);
      if (single) value = single[1];
    }
    savedEnv[match[1]] = value;
  }
}
const env = {
  ...savedEnv, ...process.env,
  OPENSESSION_WORKTREES_DIR: '/workspace/.worktrees',
  OPENSESSION_SESSION_KERNEL_TOKEN: randomBytes(48).toString('hex'),
};
const children = new Set();
let stopping = false;

function stop(code) {
  if (stopping) return;
  stopping = true;
  for (const child of children) child.kill('SIGTERM');
  const force = setTimeout(() => {
    for (const child of children) child.kill('SIGKILL');
    process.exit(code);
  }, 20000);
  force.unref();
  Promise.all([...children].map(child => new Promise(resolve => {
    if (child.exitCode !== null || child.signalCode !== null) resolve();
    else child.once('exit', resolve);
  }))).then(() => process.exit(code));
}
process.on('SIGTERM', () => stop(0));
process.on('SIGINT', () => stop(0));

function start(command, critical = true) {
  const child = spawn('opensession', [command], {
    cwd: '/opt/opensession', env, stdio: 'inherit',
  });
  children.add(child);
  child.once('error', error => {
    console.error(`Open Session ${command} failed: ${error.message}`);
    stop(1);
  });
  child.once('exit', (code, signal) => {
    children.delete(child);
    if (critical && !stopping) {
      console.error(`Open Session ${command} exited (${signal || code}); restarting the container.`);
      stop(1);
    }
  });
  return child;
}

start('session-kernel-service');
let ready = false;
for (let attempt = 0; attempt < 120 && !stopping; attempt++) {
  try {
    const response = await fetch('http://127.0.0.1:3849/ready', { signal: AbortSignal.timeout(2000) });
    if (response.ok) { ready = true; break; }
  } catch {}
  await delay(500);
}
if (!ready || stopping) {
  console.error('Open Session session kernel did not become ready.');
  stop(1);
} else {
  const seed = start('seed-session-catalogs', false);
  const seeded = await new Promise(resolve => {
    seed.once('exit', code => resolve(code));
    seed.once('error', () => resolve(1));
  });
  if (seeded !== 0 || stopping) stop(1);
  else start('server');
}
