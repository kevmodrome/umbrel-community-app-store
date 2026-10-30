#!/usr/bin/env node
'use strict';

// Black-box protocol probe for happier-dev/happier a2c45c86804b24e60ac0b76146a3ef36dfcaa15b.
// Test-client dependencies: socket.io-client@4.8.1 and tweetnacl@1.0.3.
// Use a fresh, disposable local relay + runner and fresh mounted data directories.
//
// HAPPIER_SMOKE_BASE_URL=http://127.0.0.1:<published relay port>
// HAPPIER_SMOKE_CLI_ARGV='["docker","exec","test-runner","happier"]'
// HAPPIER_SMOKE_STATE=<temporary file outside the source checkout>
// HAPPIER_SMOKE_WORKSPACE=/workspace (optional)
// HAPPIER_SMOKE_CANONICAL_URL=<native-client-reachable server URL> (optional)
//
// node happier-blackbox-smoke.cjs prepare
// <recreate both containers, retaining their data mounts>
// node happier-blackbox-smoke.cjs verify
//
// The runner must start its daemon once auth wait writes credentials. This probe
// intentionally does not call the daemon's loopback control API or seed access.key.
// It exercises public REST, production CLI pairing, and encrypted Socket.IO RPC.

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const nacl = require('tweetnacl');
const { io } = require('socket.io-client');

const phase = process.argv[2];
assert(['prepare', 'verify'].includes(phase), 'Use prepare or verify');
const baseUrl = new URL(required('HAPPIER_SMOKE_BASE_URL'));
// Prevent accidentally enrolling a synthetic account on a public production relay.
assert(['127.0.0.1', 'localhost', '[::1]'].includes(baseUrl.hostname), 'Use a loopback test endpoint');
assert(['http:', 'https:'].includes(baseUrl.protocol), 'Use HTTP(S)');
const base = baseUrl.toString().replace(/\/$/, '');
const statePath = path.resolve(required('HAPPIER_SMOKE_STATE'));
const workspace = process.env.HAPPIER_SMOKE_WORKSPACE || '/workspace';
const cliArgv = JSON.parse(required('HAPPIER_SMOKE_CLI_ARGV'));
assert(Array.isArray(cliArgv) && cliArgv.length > 0 && cliArgv.every(x => typeof x === 'string'), 'CLI argv must be a nonempty JSON string array');

function required(name) {
  assert(process.env[name], `${name} is required`);
  return process.env[name];
}

const b64 = value => Buffer.from(value).toString('base64');
const unb64 = value => new Uint8Array(Buffer.from(value, 'base64'));
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
let lastTargetDiagnostic;

function describeTargetResult(result) {
  const type = result === null ? 'null' : Array.isArray(result) ? 'array' : typeof result;
  if (type !== 'object') return { type };
  const fields = ['success', 'stdout', 'stderr', 'exitCode', 'error', 'errorCode', 'code', 'v', 'ok', 'result', 'details', 'acknowledgement', 'type', 'message'];
  const keys = Object.keys(result);
  const classify = value => {
    if (typeof value !== 'string') return value === undefined ? 'absent' : typeof value;
    const prefixes = [
      ['Command failed', 'command_failed'], ['Command timed out', 'command_timeout'],
      ['Access denied:', 'path_access_denied'], ['Path is required', 'path_required'],
      ['Path contains invalid characters', 'path_invalid'], ['Invalid RPC params', 'rpc_params_invalid'],
      ['Method not found', 'method_not_found'], ['RPC method not available', 'method_unavailable'],
      ['Forbidden', 'forbidden'], ['spawn sh ENOENT', 'shell_not_found'],
      ['spawn cat ENOENT', 'cat_not_found'], ['spawn sh EACCES', 'shell_access_denied'],
      ['mkdir:', 'mkdir_error'], ['cat:', 'cat_error'], ['sh:', 'shell_error'],
    ];
    return prefixes.find(([prefix]) => value.startsWith(prefix))?.[1] || (value.length ? 'unrecognized' : 'empty');
  };
  const knownCodes = ['RPC_METHOD_NOT_AVAILABLE', 'RPC_METHOD_NOT_FOUND', 'RPC_FORBIDDEN', 'RPC_SESSION_MACHINE_CONTROL_UNAVAILABLE', 'MACHINE_RPC_ENCRYPTION_ERROR', 'ENOENT', 'EACCES', 'ETIMEDOUT'];
  return {
    type, keys: fields.filter(key => keys.includes(key)), unknownKeys: keys.filter(key => !fields.includes(key)).length,
    success: typeof result.success === 'boolean' ? result.success : typeof result.success,
    exitCode: typeof result.exitCode === 'number' ? result.exitCode : typeof result.exitCode,
    errorCode: knownCodes.includes(result.errorCode) ? result.errorCode : typeof result.errorCode,
    error: classify(result.error), stderr: classify(result.stderr), stdoutType: typeof result.stdout,
  };
}

async function request(route, { token, body, ...options } = {}) {
  const response = await fetch(`${base}${route}`, {
    ...options,
    signal: AbortSignal.timeout(15_000),
    headers: {
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  let data;
  try { data = await response.json(); } catch { data = null; }
  return { status: response.status, data };
}

async function eventually(operation, timeoutMs = 90_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  do {
    try { return await operation(); } catch (error) { lastError = error; }
    await pause(1000);
  } while (Date.now() < deadline);
  throw lastError || new Error('Condition did not become ready');
}

async function health() {
  await eventually(async () => {
    for (const route of ['/health', '/ready']) {
      const result = await request(route);
      assert.equal(result.status, 200, `${route} status`);
      assert.equal(result.data?.status, 'ok', `${route} body`);
      assert.equal(result.data?.service, 'happier-server', `${route} service`);
    }
  });
  const unauthenticated = await request('/v1/auth/ping');
  assert.equal(unauthenticated.status, 401, 'Unauthenticated native endpoint must reject access');
}

function runCli(args) {
  const result = spawnSync(cliArgv[0], [...cliArgv.slice(1), ...args], {
    encoding: 'utf8', timeout: 60_000, maxBuffer: 2 * 1024 * 1024,
  });
  // Never echo CLI stdout: request/wait JSON contains synthetic pairing secrets.
  assert(!result.error, `CLI ${args[0]} ${args[1]} process failed`);
  assert.equal(result.status, 0, `CLI ${args[0]} ${args[1]} exit status`);
  try { return JSON.parse(result.stdout.trim()); }
  catch { throw new Error(`CLI ${args[0]} ${args[1]} did not return JSON`); }
}

async function signIn(seed, machineKey) {
  const pair = nacl.sign.keyPair.fromSeed(seed);
  const challenge = new Uint8Array(crypto.randomBytes(32));
  const body = {
    publicKey: b64(pair.publicKey), challenge: b64(challenge),
    signature: b64(nacl.sign.detached(challenge, pair.secretKey)),
  };
  if (machineKey) {
    const contentPublicKey = nacl.box.keyPair.fromSecretKey(machineKey).publicKey;
    // Stable protocol auth/accountKeyProvisioning.ts signing message.
    const binding = Buffer.concat([Buffer.from('Happy content key v1\0', 'utf8'), Buffer.from(contentPublicKey)]);
    body.contentPublicKey = b64(contentPublicKey);
    body.contentPublicKeySig = b64(nacl.sign.detached(binding, pair.secretKey));
  }
  const invalid = await request('/v1/auth', {
    method: 'POST', body: { ...body, signature: b64(crypto.randomBytes(64)) },
  });
  assert.equal(invalid.status, 401, 'Invalid signature must be rejected');
  const result = await request('/v1/auth', { method: 'POST', body });
  assert.equal(result.status, 200, 'Synthetic key-challenge sign-in');
  assert.equal(typeof result.data?.token, 'string');
  assert(result.data.token.length > 0, 'Expected account token');
  return result.data.token;
}

async function profile(token) {
  const result = await request('/v1/account/profile', { token });
  assert.equal(result.status, 200, 'Native profile');
  assert.equal(typeof result.data?.id, 'string', 'Profile account id');
  return result.data;
}

function sealDataKey(publicKey, machineKey) {
  const ephemeral = nacl.box.keyPair();
  const nonce = new Uint8Array(crypto.randomBytes(nacl.box.nonceLength));
  // Negotiated terminal provisioning v2 data-key plaintext: [0][32-byte key].
  const plaintext = new Uint8Array(33);
  plaintext.set(machineKey, 1);
  const ciphertext = nacl.box(plaintext, nonce, publicKey, ephemeral.secretKey);
  return b64(Buffer.concat([Buffer.from(ephemeral.publicKey), Buffer.from(nonce), Buffer.from(ciphertext)]));
}

function encryptLegacy(value, key) {
  const nonce = new Uint8Array(crypto.randomBytes(nacl.secretbox.nonceLength));
  const ciphertext = nacl.secretbox(new TextEncoder().encode(JSON.stringify(value)), nonce, key);
  return b64(Buffer.concat([Buffer.from(nonce), Buffer.from(ciphertext)]));
}

async function assertSession(state) {
  const result = await request(`/v2/sessions/${encodeURIComponent(state.sessionId)}`, { token: state.token });
  assert.equal(result.status, 200, 'Native encrypted session retrieval');
  assert.equal(result.data?.session?.id, state.sessionId, 'Persisted session identity');
  const bundle = unb64(result.data.session.metadata);
  const plaintext = nacl.secretbox.open(bundle.slice(24), bundle.slice(0, 24), unb64(state.accountSeed));
  assert(plaintext, 'Client must decrypt the stored session metadata');
  const metadata = JSON.parse(new TextDecoder().decode(plaintext));
  assert.equal(metadata.smokeNonce, state.nonce, 'Persisted session metadata');
}

function encryptRpc(value, key) {
  const nonce = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, nonce);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  return b64(Buffer.concat([Buffer.from([0]), nonce, ciphertext, cipher.getAuthTag()]));
}

function decryptRpc(encoded, key) {
  assert.equal(typeof encoded, 'string', 'Encrypted RPC result');
  const bundle = Buffer.from(encoded, 'base64');
  assert(bundle.length >= 29 && bundle[0] === 0, 'AES-GCM v0 result');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, bundle.subarray(1, 13));
  decipher.setAuthTag(bundle.subarray(-16));
  const serialized = Buffer.concat([decipher.update(bundle.subarray(13, -16)), decipher.final()]).toString('utf8');
  if (serialized === 'undefined') return undefined;
  const parsed = JSON.parse(serialized);
  // Released CLI encryption uses protocol stringifySerializedJsonValue. Accept
  // legacy raw JSON too, as its production parseSerializedJsonValue does.
  if (parsed && typeof parsed === 'object' && parsed.__happierSerializedJsonValueV1 === true) {
    if (parsed.type === 'undefined') return undefined;
    if (parsed.type === 'json' && Object.hasOwn(parsed, 'value')) return parsed.value;
  }
  return parsed;
}

function openPublishedMachineKey(encoded, provisionedKey) {
  assert.equal(typeof encoded, 'string', 'Machine must publish its encrypted data key');
  const envelope = unb64(encoded);
  assert(envelope.length >= 73 && envelope[0] === 0, 'Published machine key envelope version');
  const publicKey = envelope.slice(1, 33);
  const nonce = envelope.slice(33, 57);
  const ciphertext = envelope.slice(57);
  // Production openBoxBundle tries raw private key, then legacy seed derivation.
  const direct = nacl.box.open(ciphertext, nonce, publicKey, provisionedKey);
  const derived = direct || nacl.box.open(ciphertext, nonce, publicKey,
    new Uint8Array(crypto.createHash('sha512').update(provisionedKey).digest().subarray(0, 32)));
  assert(derived?.length === 32, 'Client must open the authoritative published machine key');
  return Buffer.from(derived);
}

async function remoteShell(state, task) {
  let key;
  await eventually(async () => {
    const result = await request('/v1/machines', { token: state.token });
    assert.equal(result.status, 200, 'Native machine list');
    const machines = Array.isArray(result.data) ? result.data : result.data?.machines;
    assert(Array.isArray(machines), 'Expected machine list');
    const machine = machines.find(row => row.id === state.machineId);
    assert(machine, 'Paired daemon must retain the same machine identity');
    assert.equal(machine.active, true, 'Paired daemon must report online');
    key = openPublishedMachineKey(machine.dataEncryptionKey, unb64(state.machineKey));
    assert.equal(b64(key), state.machineKey, 'Fresh paired machine must preserve the provisioned key');
    assert(decryptRpc(machine.metadata, key), 'Client must decrypt published machine metadata');
  });

  const socket = io(base, {
    path: '/v1/updates', auth: { token: state.token, clientType: 'user-scoped' },
    transports: ['websocket'], autoConnect: false, reconnection: false, timeout: 15_000,
  });
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Native WebSocket connect timeout')), 15_000);
      socket.once('connect', () => { clearTimeout(timer); resolve(); });
      socket.once('connect_error', () => { clearTimeout(timer); reject(new Error('Native WebSocket authentication/transport failed')); });
      socket.connect();
    });
    // Idempotent marker creation/read permits a short wait for daemon RPC registration.
    return await eventually(async () => {
      const ack = await socket.timeout(15_000).emitWithAck('rpc-call', {
        method: `${state.machineId}:bash`,
        requestId: crypto.randomUUID(),
        params: encryptRpc({ ...task, cwd: workspace, timeout: 10_000 }, key),
        timeoutMs: 10_000,
      });
      assert.equal(ack?.ok, true, 'Relay must route machine bash RPC');
      const result = decryptRpc(ack.result, key);
      // Only fixed field names, primitive statuses, and known error categories.
      // Never print raw target errors, stdout, stderr, encrypted params, or keys.
      lastTargetDiagnostic = describeTargetResult(result);
      assert.equal(result?.success, true, 'Runner must execute the project task');
      assert.equal(result.exitCode, 0, 'Project task exit status');
      assert.equal(result.stdout, state.nonce, 'Project task output');
      return result;
    }, 45_000);
  } finally {
    socket.close();
  }
}

async function prepare() {
  await health();
  const accountSeed = new Uint8Array(crypto.randomBytes(32));
  const machineKey = new Uint8Array(crypto.randomBytes(32));
  const approverToken = await signIn(accountSeed, machineKey);
  const account = await profile(approverToken);
  const terminal = runCli(['auth', 'request', '--json']);
  if (process.env.HAPPIER_SMOKE_CANONICAL_URL) {
    const canonical = process.env.HAPPIER_SMOKE_CANONICAL_URL.replace(/\/$/, '');
    assert.equal(terminal.serverUrl?.replace(/\/$/, ''), canonical, 'Pairing must retain the public canonical server identity');
    assert.equal(terminal.publicServerUrl?.replace(/\/$/, ''), canonical, 'Pairing must advertise the public server URL');
  }
  assert.equal(typeof terminal.publicKey, 'string', 'CLI terminal public key');
  assert.equal(typeof terminal.claimSecret, 'string', 'CLI claim secret');
  assert.equal(unb64(terminal.publicKey).length, 32, 'Terminal public key size');
  const statusRoute = `/v1/auth/request/status?publicKey=${encodeURIComponent(terminal.publicKey)}`;
  const pending = await request(statusRoute);
  assert.equal(pending.data?.status, 'pending', 'Production pairing must start pending');
  const wrongClaim = await request('/v1/auth/request/claim', {
    method: 'POST', body: { publicKey: terminal.publicKey, claimSecret: crypto.randomBytes(32).toString('base64url') },
  });
  assert.equal(wrongClaim.status, 401, 'Wrong claim secret must fail');
  const approved = await request('/v1/auth/response', {
    token: approverToken, method: 'POST',
    body: { publicKey: terminal.publicKey, response: sealDataKey(unb64(terminal.publicKey), machineKey) },
  });
  assert.equal(approved.status, 200, 'Synthetic native-client approval');
  assert.equal(approved.data?.success, true);
  const authorized = await request(statusRoute);
  assert.equal(authorized.data?.status, 'authorized');
  assert(!('token' in authorized.data) && !('response' in authorized.data), 'Public status must not disclose credentials');
  const credentials = runCli(['auth', 'wait', '--public-key', terminal.publicKey, '--json']);
  assert.equal(credentials.success, true, 'Packaged CLI must claim and write credentials');
  assert.equal(credentials.encryptionType, 'dataKey', 'Pairing must provision E2EE data-key credentials');
  assert.equal(typeof credentials.machineId, 'string');
  assert(credentials.machineId.length > 0);
  assert.equal((await profile(credentials.token)).id, account.id, 'Paired runner account binding');
  const state = {
    version: 1, source: 'a2c45c86804b24e60ac0b76146a3ef36dfcaa15b',
    accountSeed: b64(accountSeed), accountId: account.id,
    token: credentials.token, machineKey: b64(machineKey), machineId: credentials.machineId,
    nonce: crypto.randomBytes(16).toString('hex'),
  };
  state.marker = `.happier-smoke-${state.nonce}/proof`;
  const session = await request('/v1/sessions', {
    token: state.token, method: 'POST',
    body: {
      tag: `umbrel-smoke-${state.nonce}`, encryptionMode: 'e2ee', agentState: null,
      metadata: encryptLegacy({ path: workspace, host: 'umbrel-smoke', smokeNonce: state.nonce }, accountSeed),
    },
  });
  assert.equal(session.status, 200, 'Native encrypted session creation');
  assert.equal(typeof session.data?.session?.id, 'string');
  state.sessionId = session.data.session.id;
  await assertSession(state);
  await fs.mkdir(path.dirname(statePath), { recursive: true, mode: 0o700 });
  await fs.writeFile(statePath, `${JSON.stringify(state)}\n`, { mode: 0o600, flag: 'wx' });
  await remoteShell(state, {
    argv: ['sh', '-c', 'umask 077; mkdir -p "$1" && printf "%s" "$2" > "$1/proof" && printf "%s" "$2"',
      'happier-smoke', path.posix.dirname(state.marker), state.nonce],
  });
  console.log('PASS: relay readiness, signed account auth, encrypted session, claim-gated CLI pairing, encrypted remote shell task');
}

async function verify() {
  const state = JSON.parse(await fs.readFile(statePath, 'utf8'));
  assert.equal(state.version, 1);
  await health();
  const ping = await request('/v1/auth/ping', { token: state.token });
  assert.equal(ping.status, 200, 'Issued runner token must survive relay recreation');
  assert.equal(ping.data?.ok, true);
  assert.equal((await profile(state.token)).id, state.accountId, 'Persisted token account');
  const renewedToken = await signIn(unb64(state.accountSeed));
  assert.equal((await profile(renewedToken)).id, state.accountId, 'Account database must survive relay recreation');
  await assertSession(state);
  await remoteShell(state, { argv: ['cat', state.marker] });
  console.log('PASS: recreated relay and runner preserve account, token, encrypted session, pairing, machine identity, and project file');
}

(phase === 'prepare' ? prepare() : verify()).catch(error => {
  // Assertion labels are controlled by this file. Other exception messages can
  // contain JSON input or CLI output, so report only their exception type.
  const label = error instanceof assert.AssertionError
    ? error.message.split('\n')[0]
    : error instanceof Error ? error.name : 'unknown error';
  console.error(`FAIL: ${phase}: ${label}`);
  if (lastTargetDiagnostic) console.error(`Target result diagnostic: ${JSON.stringify(lastTargetDiagnostic)}`);
  process.exitCode = 1;
});
