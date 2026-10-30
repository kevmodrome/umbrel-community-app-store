#!/bin/sh
set -eu

# Leave pairing requests out of shared service logs. The owner requests and
# approves one explicitly in the runner's terminal, using a native client.
printf '%s\n' \
  '[Happier] Starting the foreground runner; it waits safely until paired.' \
  '[Happier] To pair, open the runner in Umbrel App Settings → Open Terminal and run:' \
  '  happier auth login --no-open --method mobile --no-daemon-start' \
  '[Happier] Approve the displayed QR/link in the native Happier app on your relay.'

exec happier daemon start-sync
