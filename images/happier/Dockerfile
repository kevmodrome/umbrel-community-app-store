# syntax=docker/dockerfile:1
FROM node:22.23.4-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da AS node

FROM happierdev/dev-box:stable-a2c45c86804b@sha256:1c81eb28143e12346cabe4c1a86c26d8712a7a16f352d0abb1e9cf2a05685eea

LABEL org.opencontainers.image.title="Happier runner for Umbrel" \
      org.opencontainers.image.version="stable-a2c45c86804b-1" \
      org.opencontainers.image.source="https://github.com/kevmodrome/umbrel-community-app-store" \
      org.opencontainers.image.description="Headless Happier runner with pinned Codex and Claude Code CLIs"

USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN apt-get update \
    && apt-get install -y --no-install-recommends libatomic1 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && npm install --global --prefix /usr/local --no-audit --no-fund \
         --cache /tmp/happier-agent-npm-cache \
         @openai/codex@0.166.0 \
         @anthropic-ai/claude-code@2.1.312 \
    && rm -rf /tmp/happier-agent-npm-cache

# Install agents outside the persistent home so fresh bind mounts cannot hide
# their binaries. Preserve upstream's non-root entrypoint and workspace owner.
COPY --chmod=755 images/happier/start-runner.sh /usr/local/bin/happier-umbrel-runner
ENV HOME=/home/happier \
    HAPPIER_HOME_DIR=/home/happier/.happier \
    HAPPIER_DAEMON_WAIT_FOR_AUTH=1 \
    HAPPIER_DAEMON_WAIT_FOR_AUTH_TIMEOUT_MS=0 \
    HAPPIER_SESSION_AUTOSTART_DAEMON=0 \
    HAPPIER_CLI_UPDATE_CHECK=0

USER happier
RUN node --version && npm --version && happier --version \
    && codex --version && claude --version

# The upstream entrypoint execs this launcher; the daemon remains foreground.
CMD ["happier-umbrel-runner"]
