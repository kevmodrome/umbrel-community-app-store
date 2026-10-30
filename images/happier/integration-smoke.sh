#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: bash images/happier/integration-smoke.sh RUNNER_IMAGE RELAY_IMAGE" >&2
  exit 2
fi
runner_image="$1"
relay_image="$2"
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$script_dir/../.." && pwd)"
package="$repo/kevmodrome-happier/docker-compose.yml"
if [ -d /private/tmp ]; then
  scratch="$(mktemp -d /private/tmp/happier-integration.XXXXXX)"
else
  scratch="$(mktemp -d /tmp/happier-integration.XXXXXX)"
fi
project="happier-smoke-$RANDOM-$$"
override="$scratch/compose-test.yml"
owner_uid="$(id -u)"
owner_gid="$(id -g)"
stage=initialization
export APP_DATA_DIR="$scratch"
export DEVICE_DOMAIN_NAME=happier-smoke.invalid
export HAPPIER_TEST_RUNNER_IMAGE="$runner_image"
export HAPPIER_TEST_RELAY_IMAGE="$relay_image"

mkdir -p "$scratch/data"
cp -R "$repo/kevmodrome-happier/data/." "$scratch/data/"
rm -f "$scratch/data/relay/.gitkeep" "$scratch/data/home/.gitkeep" "$scratch/data/workspace/.gitkeep"
cat > "$override" <<'YAML'
services:
  # Only relay and runner start. This unused image satisfies plain Compose's
  # schema; Umbrel supplies/removes app_proxy itself at runtime.
  app_proxy:
    image: $HAPPIER_TEST_RELAY_IMAGE
  relay:
    image: $HAPPIER_TEST_RELAY_IMAGE
    ports:
      - "127.0.0.1::3005"
  runner:
    image: $HAPPIER_TEST_RUNNER_IMAGE
YAML

compose() {
  docker compose --project-name "$project" --project-directory "$repo" -f "$package" -f "$override" "$@"
}
fixture_owner() {
  # Reproduce Umbrel's ownership, changing only this disposable copied fixture.
  docker run --rm --pull never --network none --user 0 --entrypoint /bin/chown --volume "$scratch/data:/fixture" "$runner_image" -R "$1:$2" /fixture
}
finish() {
  result=$?
  if [ "$result" -ne 0 ]; then
    printf 'Happier integration failed during: %s\n' "$stage" >&2
    if [ -n "${runner_id:-}" ]; then
      docker inspect --format 'Runner state: running={{.State.Running}} restarts={{.RestartCount}} exitCode={{.State.ExitCode}} startedAt={{.State.StartedAt}}' "$runner_id" >&2 || true
    fi
    compose logs --no-color --tail 100 relay runner >&2 || true
  fi
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fixture_owner "$owner_uid" "$owner_gid" >/dev/null 2>&1 || true
  rm -rf "$scratch"
  return "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

stage="prepare app-style persistent directories"
fixture_owner 1000 1000
stage="start actual relay and runner Compose services"
compose up --detach --wait --wait-timeout 120 relay runner

relay_id="$(compose ps -q relay)"
runner_id="$(compose ps -q runner)"
test -n "$relay_id"
test -n "$runner_id"
test "$(docker exec "$relay_id" id -u)" = 1000
test "$(docker exec "$runner_id" id -u)" = 1000

stage="check native-only relay and advertised identity"
mapping="$(compose port relay 3005)"
export HAPPIER_SMOKE_BASE_URL="http://$mapping"
export HAPPIER_SMOKE_CANONICAL_URL=http://happier-smoke.invalid:13005
export HAPPIER_SMOKE_STATE="$scratch/protocol-state.json"
export HAPPIER_SMOKE_WORKSPACE=/workspace
export HAPPIER_SMOKE_CLI_ARGV="$(node -e 'process.stdout.write(JSON.stringify(["docker","exec","--user","1000:1000",process.argv[1],"happier"]))' "$runner_id")"
node --input-type=module <<'JS'
import assert from 'node:assert/strict';
const base = process.env.HAPPIER_SMOKE_BASE_URL;
const response = await fetch(base, { signal: AbortSignal.timeout(15000) });
assert.equal(response.status, 200);
const text = await response.text();
assert.match(text, /Welcome to Happier Server/);
assert.doesNotMatch(text, /<html/i, 'Relay must not serve a browser app');
const featuresResponse = await fetch(base + '/v1/features', { signal: AbortSignal.timeout(15000) });
assert.equal(featuresResponse.status, 200);
const features = await featuresResponse.json();
assert.equal(features.capabilities.server.canonicalServerUrl, process.env.HAPPIER_SMOKE_CANONICAL_URL);
console.log('PASS: non-root headless relay with canonical public URL');
JS

stage="prove unpaired runner stays up without exposing pairing secrets"
sleep 2
test "$(docker inspect --format '{{.State.Running}}' "$runner_id")" = true
unpaired_restarts="$(docker inspect --format '{{.RestartCount}}' "$runner_id")"
printf 'Runner restarts before pairing: %s\n' "$unpaired_restarts"
logs="$(docker logs "$runner_id" 2>&1)"
if printf '%s\n' "$logs" | grep -E 'happier://|/terminal/connect|claimSecret' >/dev/null; then
  echo "Runner startup must not log pairing credentials." >&2
  exit 1
fi
# The fixture host can differ from the app UID; create state as the app user.
docker exec "$runner_id" sh -c 'printf synthetic-provider-state > "$HOME/.provider-persistence-marker"'
master_before="$(docker exec "$relay_id" sha256sum /data/handy-master-secret.txt)"

stage="pair through production CLI and execute encrypted native machine RPC"
node "$script_dir/tests/protocol-smoke.cjs" prepare
test "$(docker inspect --format '{{.RestartCount}}' "$runner_id")" = "$unpaired_restarts"

stage="replace both containers while retaining app data"
compose up --detach --force-recreate --wait --wait-timeout 120 relay runner
relay_id="$(compose ps -q relay)"
runner_id="$(compose ps -q runner)"
mapping="$(compose port relay 3005)"
export HAPPIER_SMOKE_BASE_URL="http://$mapping"
export HAPPIER_SMOKE_CLI_ARGV="$(node -e 'process.stdout.write(JSON.stringify(["docker","exec","--user","1000:1000",process.argv[1],"happier"]))' "$runner_id")"
test "$(docker exec "$relay_id" sha256sum /data/handy-master-secret.txt)" = "$master_before"
test "$(docker exec "$runner_id" sh -c 'cat "$HOME/.provider-persistence-marker"')" = synthetic-provider-state
stage="verify original account, encrypted session, machine identity and workspace"
node "$script_dir/tests/protocol-smoke.cjs" verify
printf 'PASS: native pairing, encrypted project command, relay identity and container-replacement persistence.\n'

