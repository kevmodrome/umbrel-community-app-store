# syntax=docker/dockerfile:1
FROM ghcr.io/getpaseo/paseo:0.14.0@sha256:2a370238230689406d7123e44b218ede221fd77dd23200a18672ed03873682b0

LABEL org.opencontainers.image.title="Paseo for Umbrel" \
      org.opencontainers.image.version="0.14.0-1" \
      org.opencontainers.image.source="https://github.com/kevmodrome/umbrel-community-app-store" \
      org.opencontainers.image.description="Paseo browser UI with pinned Codex and Claude Code CLIs"

# The upstream root entrypoint prepares the persistent home and then uses gosu
# to run the daemon and agents as paseo (1000:1000). Keep that entrypoint/user.
USER root
RUN npm install --global --no-audit --no-fund --cache /tmp/paseo-agent-npm-cache \
      @openai/codex@0.166.0 \
      @anthropic-ai/claude-code@2.1.312 \
    && rm -rf /tmp/paseo-agent-npm-cache \
    && gosu paseo codex --version \
    && gosu paseo claude --version
