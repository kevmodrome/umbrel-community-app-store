# syntax=docker/dockerfile:1
FROM node:22.23.4-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da AS node

FROM ghcr.io/coollabsio/jean-server:v1.0.13@sha256:24f5bbcf89695d4bbe7b7b77de295232766920655817cb3bb14e69859fac0a8f

LABEL org.opencontainers.image.title="Jean for Umbrel" \
      org.opencontainers.image.version="1.0.13-1" \
      org.opencontainers.image.source="https://github.com/kevmodrome/umbrel-community-app-store" \
      org.opencontainers.image.description="Jean headless server with Node.js and npm for browser onboarding"

# Jean's onboarding requires Node/npm before users can install their agents.
# Keep these in the image so a fresh persistent home needs no bootstrap download.
USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN apt-get update \
    && apt-get install -y --no-install-recommends libatomic1 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Preserve the upstream entrypoint and non-root agent execution.
USER jean
RUN node --version && npm --version && npx --version
