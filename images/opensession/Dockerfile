# syntax=docker/dockerfile:1
FROM oven/bun:1.4.0@sha256:5ff609364c049b54eb0ff560ec96319729a972078ef2c755d758f0c6ef89c2d6 AS bun
FROM node:22.23.4-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da

ARG TARGETARCH
LABEL org.opencontainers.image.title="Open Session for Umbrel" \
      org.opencontainers.image.version="0.4.79-1" \
      org.opencontainers.image.source="https://github.com/kevmodrome/umbrel-community-app-store" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.description="Open Session browser workspace with persistent projects and provider sign-ins"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl git gh openssh-client ripgrep tini gosu \
       libatomic1 libstdc++6 python3 build-essential unzip \
    && rm -rf /var/lib/apt/lists/* \
    && groupmod -n opensession node \
    && usermod -l opensession -d /home/opensession -m node

# Retain the complete release: the compiled binary uses worker, image and WASM
# sidecars. Verify the immutable upstream archive before extracting it.
RUN case "$TARGETARCH" in \
      amd64) upstream_arch=x64; checksum=38d1e5218a5c70e44ec3d106be48b76e3bfa6b148807fb157f76883e8f486b6d ;; \
      arm64) upstream_arch=arm64; checksum=a36a0c78adbe1a814c14c375ef54dcdf9d5e428e9efd1085d10550073cf5cd28 ;; \
      *) echo "Unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac \
    && curl --fail --location --retry 3 \
       "https://github.com/tellahq/opensession/releases/download/v0.4.79/opensession-linux-${upstream_arch}.tar.gz" \
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
ENV HOME=/home/opensession \
    SHELL=/bin/bash \
    PATH=/home/opensession/.local/bin:/home/opensession/.opensession/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    NPM_CONFIG_PREFIX=/home/opensession/.local \
    NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3850 \
    OPENSESSION_CLAUDE_AUTO_UPDATE=0
WORKDIR /workspace
EXPOSE 3850
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD curl --fail --silent http://127.0.0.1:3850/ready >/dev/null || exit 1
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/opensession-umbrel"]
