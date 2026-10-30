#!/usr/bin/env bash
set -euo pipefail

# Characterize the production startup contract without an account or provider use.
# A regression to dev-box's default shell, missing auth wait, root runtime, or
# leaked pairing requests must fail this test.
image="${HAPPIER_TEST_IMAGE:-happier-umbrel:test}"
name="happier-runner-smoke-${RANDOM}-$$"
home_volume="${name}-home"
workspace_volume="${name}-workspace"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$home_volume" "$workspace_volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "$home_volume" >/dev/null
docker volume create "$workspace_volume" >/dev/null
# Docker initializes these test volumes from the image-owned UID 1000 directories,
# matching the ownership of committed Umbrel application data directories.
docker run --detach --name "$name" \
  --env HAPPIER_SERVER_URL=http://happier-smoke.example:13005 \
  --env HAPPIER_PUBLIC_SERVER_URL=http://happier-smoke.example:13005 \
  --env HAPPIER_LOCAL_SERVER_URL=http://127.0.0.1:9 \
  --mount "type=volume,src=$home_volume,dst=/home/happier" \
  --mount "type=volume,src=$workspace_volume,dst=/workspace" \
  "$image" >/dev/null
sleep 3
if [ "$(docker inspect --format '{{.State.Running}}' "$name")" != true ]; then
  docker logs "$name" >&2
  echo 'FAIL: an unpaired runner must keep running.' >&2
  exit 1
fi

docker exec "$name" sh -ec '
  test "$(id -u)" = 1000
  test "$(id -g)" = 1000
  test "$HOME" = /home/happier
  test "$HAPPIER_HOME_DIR" = /home/happier/.happier
  test -w "$HOME"
  test -w /workspace
  test "$HAPPIER_DAEMON_WAIT_FOR_AUTH" = 1
  test "$HAPPIER_DAEMON_WAIT_FOR_AUTH_TIMEOUT_MS" = 0
  test "$HAPPIER_SESSION_AUTOSTART_DAEMON" = 0
  test -x /opt/happier/cli/happier
  test "$(node --version)" = v22.23.4
  codex --version | head -1 | grep -F "0.166.0"
  claude --version | grep -F "2.1.312"
  printf persisted > /workspace/restart-proof
'
logs="$(docker logs "$name" 2>&1)"
if ! printf '%s\n' "$logs" | grep -F 'happier auth login --no-open --method mobile --no-daemon-start' >/dev/null; then
  echo 'FAIL: startup must provide the safe native pairing command.' >&2
  exit 1
fi
if printf '%s\n' "$logs" | grep -E 'happier://|/terminal/connect|publicKey[=:]|claimSecret' >/dev/null; then
  echo 'FAIL: startup logs must not contain pairing credentials or links.' >&2
  exit 1
fi

docker restart "$name" >/dev/null
sleep 2
test "$(docker inspect --format '{{.State.Running}}' "$name")" = true
docker exec "$name" sh -ec 'test "$(cat /workspace/restart-proof)" = persisted'
test "$(docker inspect --format '{{.RestartCount}}' "$name")" = 0
# The foreground daemon owns shutdown, so Docker should not need SIGKILL.
docker stop --time 10 "$name" >/dev/null
test "$(docker inspect --format '{{.State.ExitCode}}' "$name")" != 137
printf 'PASS: unpaired startup, non-root tooling, persistent workspace, safe logs, restart, shutdown.\n'
