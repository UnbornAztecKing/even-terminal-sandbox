# syntax=docker/dockerfile:1.7
#
# Egress allowlist proxy for even-terminal-sandbox.
#
# tinyproxy is used in HTTP-CONNECT-only mode. It rejects CONNECT to anything
# not in the allowlist BEFORE establishing the tunnel, so no custom CA needs
# to be installed in the agent image and the LLM provider's TLS session
# remains end-to-end between agent and provider.

FROM debian:bookworm-slim

ARG SOURCE_COMMIT=unknown

# tinyproxy + tini (PID 1) + ca-certs for outbound TLS.
# The proxy itself does not terminate TLS; it only does CONNECT-tunneling.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        tinyproxy \
        tini \
        ca-certificates \
        gawk \
        netcat-openbsd \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN groupadd -g 10001 eveproxy \
 && useradd  -u 10001 -g 10001 -s /sbin/nologin -d /var/empty -M eveproxy \
 && mkdir -p /etc/even-egress /run/tinyproxy /var/log/tinyproxy \
 && chown -R 10001:10001 /run/tinyproxy /var/log/tinyproxy

COPY --chown=root:root --chmod=0444 allowlist.txt /etc/even-egress/allowlist.txt
COPY --chown=root:root --chmod=0555 entrypoint.sh /usr/local/bin/proxy-entrypoint

LABEL org.opencontainers.image.title="even-terminal-sandbox/egress-proxy" \
      org.opencontainers.image.description="HTTP-CONNECT allowlist proxy in front of even-terminal." \
      org.opencontainers.image.source="https://github.com/UnbornAztecKing/even-terminal-sandbox" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}"

USER 10001:10001
EXPOSE 3128

ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/proxy-entrypoint"]
