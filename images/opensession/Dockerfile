# syntax=docker/dockerfile:1
FROM oven/bun:1.4.0@sha256:5ff609364c049b54eb0ff560ec96319729a972078ef2c755d758f0c6ef89c2d6 AS bun
FROM node:22.23.4-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da

ARG TARGETARCH
LABEL org.opencontainers.image.title="Open Session for Umbrel" \
      org.opencontainers.image.version="0.4.82-2" \
      io.opensession.umbrel.runner-ingress="1" \
      org.opencontainers.image.source="https://github.com/kevmodrome/umbrel-community-app-store" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.description="Open Session browser workspace with persistent projects and provider sign-ins"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates caddy curl git gh openssh-client ripgrep tini gosu \
       libatomic1 libstdc++6 python3 build-essential unzip \
    && rm -rf /var/lib/apt/lists/* \
    && groupmod -n opensession node \
    && usermod -l opensession -d /home/opensession -m node

# Retain the complete release: the compiled binary uses worker, image and WASM
# sidecars. Verify the immutable upstream archive before extracting it.
RUN case "$TARGETARCH" in \
      amd64) upstream_arch=x64; checksum=42269c52df840d496d2386f6dadafc9080f2da8085ec17e86dbe9b0df4e3b601 ;; \
      arm64) upstream_arch=arm64; checksum=5552524e222a7be8773f042a48c179e986dcb14ce97213dd0fc26e3463419de6 ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && curl --fail --location --retry 3 \
       "https://github.com/tellahq/opensession/releases/download/v0.4.82/opensession-linux-${upstream_arch}.tar.gz" \
       --output /tmp/opensession.tar.gz \
    && printf '%s  /tmp/opensession.tar.gz\n' "$checksum" | sha256sum --check --strict \
    && mkdir -p /opt/opensession \
    && tar -xzf /tmp/opensession.tar.gz -C /opt/opensession --strip-components=1 \
    && rm /tmp/opensession.tar.gz \
    && ln -s /opt/opensession/opensession /usr/local/bin/opensession

COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
RUN ln -s bun /usr/local/bin/bunx \
    && npm install --global --prefix /usr/local --no-audit --no-fund \
       --cache /tmp/opensession-agent-cache \
       @openai/codex@0.166.0 @anthropic-ai/claude-code@2.1.312 \
    && rm -rf /tmp/opensession-agent-cache \
    && gosu opensession codex --version \
    && gosu opensession claude --version \
    && bun --version && node --version && rg --version

COPY --chmod=755 images/opensession/entrypoint.sh /usr/local/bin/opensession-umbrel
COPY images/opensession/start.mjs /usr/local/lib/opensession/start.mjs
COPY images/opensession/Caddyfile /usr/local/lib/opensession/Caddyfile
ENV HOME=/home/opensession \
    SHELL=/bin/bash \
    PATH=/home/opensession/.local/bin:/home/opensession/.opensession/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    NPM_CONFIG_PREFIX=/home/opensession/.local \
    NODE_ENV=production \
    OPENSESSION_CLAUDE_AUTO_UPDATE=0
WORKDIR /workspace
EXPOSE 3850
# 3851 is an opt-in, source-checked Runner listener; never publish it globally.
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD curl --fail --silent http://127.0.0.1:3850/ready >/dev/null || exit 1
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/opensession-umbrel"]
