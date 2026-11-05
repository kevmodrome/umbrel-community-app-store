#!/usr/bin/env bash
set -euo pipefail

# Umbrel's fresh bind mounts hide the image's home. Prepare only the two mount
# roots, then drop privileges; never recursively chown a selected Projects folder.
if [ "$(id -u)" = 0 ]; then
  mkdir -p /home/opensession /workspace
  chown opensession:opensession /home/opensession /workspace
  exec gosu opensession "$0" "$@"
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
fi
exec node /usr/local/lib/opensession/start.mjs
