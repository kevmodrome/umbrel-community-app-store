#!/usr/bin/env bash
set -euo pipefail

# Exercise a built image without provider accounts or host-published ports.
image="${1:?Usage: smoke-test.sh IMAGE}"
name="umbrel-paseo-smoke-$$"
home_volume="${name}-home"
workspace_volume="${name}-workspace"
current_stage=initialization

stage() {
  current_stage="$1"
  printf 'Paseo smoke: %s\n' "$current_stage"
}

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$home_volume" "$workspace_volume" >/dev/null 2>&1 || true
}
finish() {
  result=$?
  if [ "$result" -ne 0 ]; then
    printf 'Paseo smoke failed during: %s (exit %s)\n' "$current_stage" "$result" >&2
    docker logs "$name" >&2 || true
    docker exec "$name" ps -eo pid,uid,args >&2 || true
  fi
  cleanup
  return "$result"
}
trap finish EXIT

stage 'prepare persistent volumes'
docker volume create "$home_volume" >/dev/null
docker volume create "$workspace_volume" >/dev/null
# Umbrel creates app-data sources as 1000:1000; reproduce that ownership.
docker run --rm --entrypoint sh \
  -v "$home_volume:/home/paseo" -v "$workspace_volume:/workspace" \
  "$image" -c 'chown 1000:1000 /home/paseo /workspace'

start() {
  docker run -d --name "$name" \
    -e PASEO_PASSWORD=smoke-test-only-password \
    -e PASEO_HOSTNAMES=smoke.local \
    -e PASEO_RELAY_ENABLED=false \
    -v "$home_volume:/home/paseo" -v "$workspace_volume:/workspace" \
    "$image" >/dev/null

  for attempt in $(seq 1 60); do
    if docker exec "$name" node -e \
      'const request = require("http").get("http://127.0.0.1:6767/api/health", r => process.exit(r.statusCode === 200 ? 0 : 1)); request.setTimeout(1500, () => request.destroy(new Error("health request timed out"))); request.on("error", () => process.exit(1))' \
      >/dev/null 2>&1; then
      return
    fi
    if [ "$(docker inspect --format '{{.State.Running}}' "$name")" != true ]; then
      break
    fi
    sleep 1
  done
  docker logs "$name"
  return 1
}

stage 'start daemon and wait for health'
start
stage 'run agent CLIs and write persistent files as UID 1000'
docker exec --user paseo "$name" sh -ec '
  test "$(id -u)" = 1000
  codex --version
  claude --version
  test -w "$HOME"
  test -w /workspace
  printf retained > "$HOME/smoke-persistence"
  printf retained > /workspace/smoke-persistence
'
# The running supervisor, not just docker exec, must drop privileges.
stage 'verify running supervisor UID'
docker exec "$name" sh -ec '
  # Upstream explicitly sets process.title, replacing the original Node argv.
  pid="$(pgrep -f "^Paseo Supervisor$" || true)"
  test -n "$pid"
  test "$(ps -o uid= -p "$pid" | tr -d " ")" = 1000
'
stage 'verify browser UI, HTTP password, and hostname validation'
docker exec -i "$name" node <<'NODE'
const assert = require('node:assert/strict');
const http = require('node:http');
function get(path, host, token) {
  return new Promise((resolve, reject) => {
    const headers = { Host: host };
    if (token) headers.Authorization = `Bearer ${token}`;
    const request = http.get({ hostname: '127.0.0.1', port: 6767, path, headers }, response => {
      let body = '';
      response.on('data', chunk => { body += chunk; });
      response.on('end', () => resolve({ status: response.statusCode, body }));
    });
    request.setTimeout(5000, () => request.destroy(new Error('request timed out')));
    request.on('error', reject);
  });
}
(async () => {
  const ui = await get('/', 'smoke.local');
  assert.equal(ui.status, 200, 'bundled browser UI');
  assert.match(ui.body, /<html/i, 'browser UI contains HTML');
  assert.equal((await get('/api/status', 'smoke.local')).status, 401, 'password required');
  assert.equal((await get('/api/status', 'smoke.local', 'wrong-password')).status, 401, 'wrong password rejected');
  assert.equal((await get('/api/status', 'smoke.local', process.env.PASEO_PASSWORD)).status, 200, 'configured password accepted');
  assert.equal((await get('/api/health', 'untrusted.invalid')).status, 403, 'unknown hostname rejected');
})().catch(error => { console.error(error); process.exitCode = 1; });
NODE
# Use Paseo's own client protocol to exercise the authenticated WebSocket path.
stage 'connect authenticated Paseo WebSocket client'
docker exec --user paseo "$name" node -e '
  const { spawnSync } = require("node:child_process");
  const result = spawnSync("paseo", ["project", "ls", "--host", "127.0.0.1:6767"], { stdio: "inherit", timeout: 20000 });
  if (result.error) console.error(result.error);
  process.exit(result.status === 0 ? 0 : 1);
'

stage 'replace container and verify persistent files'
docker rm -f "$name" >/dev/null
start
docker exec --user paseo "$name" sh -ec '
  test "$(cat "$HOME/smoke-persistence")" = retained
  test "$(cat /workspace/smoke-persistence)" = retained
'
printf '%s\n' 'Paseo smoke checks passed: browser UI, health, password, host allowlist, non-root agents, and persistence.'
