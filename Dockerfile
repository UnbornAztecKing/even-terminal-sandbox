# syntax=docker/dockerfile:1.7
#
# even-terminal-sandbox runtime image.
#
# Pin policy: BASE_IMAGE_DIGEST and EVEN_TERMINAL_VERSION are the two
# supply-chain inputs. Both are surfaced as build args so CI can re-pin by
# digest on every release and dependabot can bump the npm package via PR.
#
# Reproducibility: SOURCE_DATE_EPOCH is honored if passed; `npm ci`-style
# install with --ignore-scripts blocks postinstall hooks.

ARG BASE_IMAGE=node:22-bookworm-slim
ARG BASE_IMAGE_DIGEST=
ARG EVEN_TERMINAL_VERSION=0.7.9

# ─── builder ────────────────────────────────────────────────────────────────
FROM ${BASE_IMAGE}${BASE_IMAGE_DIGEST:+@${BASE_IMAGE_DIGEST}} AS builder

ARG EVEN_TERMINAL_VERSION

WORKDIR /opt/install

# Install ET into an isolated prefix so we can copy only what we need into the
# runtime image. --ignore-scripts blocks postinstall side effects from any
# transitive dependency. --no-audit / --no-fund quiet the output for
# deterministic logs.
RUN --mount=type=cache,target=/root/.npm,id=npm-cache \
    npm install --prefix /opt/install --global \
        --ignore-scripts --no-audit --no-fund \
        "@evenrealities/even-terminal@${EVEN_TERMINAL_VERSION}"

# ─── runtime ────────────────────────────────────────────────────────────────
FROM ${BASE_IMAGE}${BASE_IMAGE_DIGEST:+@${BASE_IMAGE_DIGEST}} AS runtime

ARG EVEN_TERMINAL_VERSION
ARG SOURCE_COMMIT=unknown
ARG SOURCE_DATE_EPOCH=0

# Install only what the runtime needs: tini for PID 1, ca-certs for TLS,
# tiny set of read-only command surface. Deliberately no curl/wget/git/ssh
# inside the runtime image - the agent has no reason to need them, and they
# are the most common LotL exfiltration tools.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        tini \
        ca-certificates \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Non-root user; UID/GID chosen to avoid collisions with common host users.
RUN groupadd -g 10001 even \
 && useradd -m -u 10001 -g 10001 -s /sbin/nologin -d /home/even even \
 && mkdir -p /work /home/even/.claude /home/even/.config \
 && chown -R 10001:10001 /work /home/even

# Copy ET's installed tree from builder. The package lives at
# /opt/install/lib/node_modules/@evenrealities/even-terminal; the global bin
# symlink lives at /opt/install/bin/even-terminal.
COPY --from=builder --chown=root:root /opt/install /opt/even-terminal

# Make the binary discoverable on PATH without granting write.
RUN ln -s /opt/even-terminal/bin/even-terminal /usr/local/bin/even-terminal

# Sandbox entrypoint reads Docker secrets into env then execs ET.
COPY --chown=root:root --chmod=0555 entrypoint.sh /usr/local/bin/sandbox-entrypoint

USER 10001:10001
WORKDIR /work

# ET reads these. PORT is fixed; we publish-map at the host level.
ENV NODE_ENV=production \
    PORT=3456 \
    PROJECT_DIR=/work \
    EVEN_TERMINAL_NAME=sandbox \
    HOME=/home/even \
    NPM_CONFIG_CACHE=/tmp/.npm \
    NPM_CONFIG_PREFIX=/home/even/.npm-global \
    PATH=/home/even/.npm-global/bin:/usr/local/bin:/usr/bin:/bin

EXPOSE 3456

# Healthcheck: unauthenticated request to /api/info should be rejected with
# 401, proving (a) the server is up and (b) the auth middleware is wired in.
# Uses node's built-in http; no curl/wget required in the image.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["node","-e", \
        "require('http').get('http://127.0.0.1:3456/api/info',r=>process.exit(r.statusCode===401?0:1)).on('error',()=>process.exit(1))"]

# OCI image labels for traceability and `cosign verify`-style attestation.
LABEL org.opencontainers.image.title="even-terminal-sandbox" \
      org.opencontainers.image.description="Hardened sandbox for @evenrealities/even-terminal." \
      org.opencontainers.image.source="https://github.com/UnbornAztecKing/even-terminal-sandbox" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.vendor="UnbornAztecKing" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.version="${EVEN_TERMINAL_VERSION}" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      io.evenrealities.even-terminal.version="${EVEN_TERMINAL_VERSION}"

ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/sandbox-entrypoint"]
CMD ["--cwd","/work","--provider","claude"]
